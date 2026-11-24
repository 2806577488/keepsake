/// Keepsake（留声）— 本机相册（MediaStore）读取通道 `keepsake/media`。
///
/// 为什么要有这一层（而不是继续用系统选图 Intent）：
/// 国产 ROM 上 `ACTION_GET_CONTENT` 同时被「图库」和「文件管理」注册，系统
/// 按"默认应用 / 上次的选择"直接进文件管理器（DocumentsUI 的「最近」）。
/// 连续几个版本都在调 Intent 顺序、`resolveActivity`、`<queries>`，但只要
/// 仍然是**隐式 Intent**，最终进哪个界面就仍然由 ROM 决定 —— 这条路上
/// "修语义"是修不干净的。
///
/// 所以「从相册选择」的主路径改成 App 自己画的网格：原生侧只做 MediaStore
/// 列表查询（本文件），界面完全在 Flutter 里，**不可能**跳到文件管理器。
/// 系统图库作为一个备选按钮保留，见 `lib/core/chat/gallery_picker.dart`。
///
/// 原生通道（Android 侧 `MediaLibrary.kt` + `MainActivity.kt`）：
/// - `access` → `full` / `partial` / `none`
/// - `request` → bool（是否拿到至少"部分照片"授权）
/// - `list` `{offset, limit}` → `List<Map>`（`path` / `name` / `size` / `dateAdded`）
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'attachments.dart' show AttachmentRules;

/// 相册授权状态。
///
/// - [full]：可以读全部照片；
/// - [partial]：Android 14 的「部分照片访问」，只能读用户挑过的那几张；
/// - [none]：还没授权（或用户拒绝），此时不该显示空网格，而该显示授权引导。
enum MediaAccess { none, partial, full }

/// 本机相册里的一张图（[path] 是可直接 `File(...)` 读取的绝对路径）。
class MediaImage {
  const MediaImage({
    required this.path,
    required this.name,
    this.size = 0,
    this.addedAt,
    this.edited = false,
    String? id,
  }) : id = id ?? path;

  /// 稳定标识：默认等于原图路径，**编辑后不变**。
  ///
  /// 为什么不能直接用 [path] 当 key：编辑会产出新文件（新路径），如果 key 跟着
  /// 变，选中集合里就会出现"同一张图两个 key"，序号/去重全乱。
  final String id;

  /// 设备上的绝对路径（MediaStore 的 `DATA` 列）；
  /// [edited] 为 true 时是 App 私有目录里编辑后的新文件。
  final String path;

  /// 显示名（一般就是 `IMG_20240101_120000.jpg`）。
  final String name;

  /// 字节数；查询不到时为 0。
  final int size;

  /// 加入相册的时间；查询不到时为 null。
  final DateTime? addedAt;

  /// 是否已经过 App 内编辑（编辑产物已经落在私有目录，不需要再复制）。
  final bool edited;

  MediaImage copyWith({
    String? path,
    String? name,
    int? size,
    bool? edited,
    String? id,
  }) =>
      MediaImage(
        id: id ?? this.id,
        path: path ?? this.path,
        name: name ?? this.name,
        size: size ?? this.size,
        addedAt: addedAt,
        edited: edited ?? this.edited,
      );

  @override
  String toString() => 'MediaImage($name, $path)';
}

/// 一个相册分类（MediaStore 的 bucket）。
///
/// 微信式相册顶部的「全部图片 ▾」就是这份列表：按目录分组，
/// [cover] 是该目录最新一张图，[count] 是张数。
class MediaBucket {
  const MediaBucket({
    required this.id,
    required this.name,
    this.count = 0,
    this.cover,
  });

  /// bucket id；空串表示"全部图片"（不按目录过滤）。
  final String id;

  /// 目录名（如「相机」「截图」「微信」）。
  final String name;

  /// 该目录下的图片数量。
  final int count;

  /// 封面图路径（取该目录最新一张）；可能为空。
  final String? cover;
}

/// 相册总览（微信式顶部「图片和视频 (n)」+ 各目录）。
class MediaCatalog {
  const MediaCatalog({required this.total, required this.buckets});

  /// 全部图片张数（微信「图片和视频 (2514)」里的 2514）。
  final int total;

  /// 各目录分类（**不含**"图片和视频"这一项，界面自己补在最前面）。
  final List<MediaBucket> buckets;
}

/// 相册通道的 Dart 侧封装。
class MediaGallery {
  const MediaGallery._();

  static const MethodChannel _channel = MethodChannel('keepsake/media');

  /// 当前授权状态。通道缺失（桌面/测试环境）时按"没有授权"处理。
  static Future<MediaAccess> access() async {
    try {
      final String? value = await _channel.invokeMethod<String>('access');
      switch (value) {
        case 'full':
          return MediaAccess.full;
        case 'partial':
          return MediaAccess.partial;
        default:
          return MediaAccess.none;
      }
    } on MissingPluginException {
      return MediaAccess.none;
    } on PlatformException {
      return MediaAccess.none;
    }
  }

  /// 申请相册权限；返回是否拿到至少"部分照片"授权。
  ///
  /// 系统在权限框里被用户点掉、或通道不在时返回 false（不抛异常，调用方
  /// 只需要一个"能不能继续"的答案）。
  static Future<bool> request() async {
    try {
      final bool? granted = await _channel.invokeMethod<bool>('request');
      return granted ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 取一页相册图片（按加入时间倒序）。
  ///
  /// [offset] / [limit] 直接下推给 MediaStore 的分页参数，不会把整库读进内存；
  /// [bucketId] 非空时只取该目录（微信式"全部图片 / 相机 / 截图"）。
  /// 失败时抛 [PlatformException]，错误码 `NO_PERMISSION` / `LIST_FAILED`。
  static Future<List<MediaImage>> list({
    required int offset,
    required int limit,
    String? bucketId,
  }) async {
    final List<Object?>? rows = await _channel.invokeMethod<List<Object?>>(
      'list',
      <String, Object?>{
        'offset': offset,
        'limit': limit,
        if (bucketId != null && bucketId.isNotEmpty) 'bucketId': bucketId,
      },
    );
    if (rows == null || rows.isEmpty) return const <MediaImage>[];
    final List<MediaImage> images = <MediaImage>[];
    for (final Object? row in rows) {
      if (row is! Map) continue;
      final String path = (row['path'] as String?)?.trim() ?? '';
      if (path.isEmpty) continue;
      final String rawName = (row['name'] as String?)?.trim() ?? '';
      final Object? date = row['dateAdded'];
      images.add(
        MediaImage(
          path: path,
          name: rawName.isEmpty ? AttachmentRules.fileNameOf(path) : rawName,
          size: (row['size'] as num?)?.toInt() ?? 0,
          addedAt: date is num && date > 0
              ? DateTime.fromMillisecondsSinceEpoch(date.toInt())
              : null,
        ),
      );
    }
    return images;
  }

  /// 取相册总览（微信式顶部「图片和视频 (n)」+ 各目录分类）。
  ///
  /// 只返回 MediaStore 里的真实目录（相机、截图、微信…），按张数从多到少；
  /// "图片和视频"这一项由界面自己补在最前面（它的 [MediaBucket.id] 为空串 =
  /// 不筛目录），总数用 [MediaCatalog.total]。失败时抛 [PlatformException]。
  static Future<MediaCatalog> catalog() async {
    final Object? raw = await _channel.invokeMethod<Object?>('buckets');
    if (raw is! Map) {
      return const MediaCatalog(total: 0, buckets: <MediaBucket>[]);
    }
    final List<MediaBucket> buckets = <MediaBucket>[];
    final Object? rows = raw['buckets'];
    if (rows is List) {
      for (final Object? row in rows) {
        if (row is! Map) continue;
        final String id = (row['id'] as String?)?.trim() ?? '';
        final String name = (row['name'] as String?)?.trim() ?? '';
        final String cover = (row['cover'] as String?)?.trim() ?? '';
        buckets.add(
          MediaBucket(
            id: id,
            name: name.isEmpty ? '未命名相册' : name,
            count: (row['count'] as num?)?.toInt() ?? 0,
            cover: cover.isEmpty ? null : cover,
          ),
        );
      }
    }
    return MediaCatalog(
      total: (raw['total'] as num?)?.toInt() ?? 0,
      buckets: buckets,
    );
  }

  /// 把选中图片复制到 App 私有目录 `picked/`，返回新路径。
  ///
  /// 为什么要复制：相册里的原图随时可能被用户删掉，而附件记录（DB 里的
  /// `path`）要在会话里长期可用。系统选图那条老路径也是先复制再用。
  ///
  /// [seq] 只是同一批里的序号，避免多张同名图（连拍 / 多目录）互相覆盖。
  static Future<String> preserve(MediaImage image, {int seq = 0}) async {
    try {
      final Directory support = await getApplicationSupportDirectory();
      final Directory dir = Directory('${support.path}/picked');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final String prefix = '${DateTime.now().millisecondsSinceEpoch}_${seq}_';
      final File target = File('${dir.path}/$prefix${_safeName(image.name)}');
      await File(image.path).copy(target.path);
      return target.path;
    } catch (_) {
      // 复制失败（空间不足 / 原图已被删掉）时退回原路径：至少还能试一次，
      // 真的读不出来会在附件校验里变成「文件不见了：…」这种可读文案。
      return image.path;
    }
  }

  /// 文件名清洗：去掉路径分隔符与非法字符，保留中文，超长截断。
  static String _safeName(String raw) {
    String name = raw.trim();
    final int slash = name.lastIndexOf('/');
    final int backslash = name.lastIndexOf(r'\');
    name = name.substring((slash > backslash ? slash : backslash) + 1);
    name = name.replaceAll('..', '_');
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    name = name.replaceAll(RegExp(r'^[._\-\s]+|[._\-\s]+$'), '');
    if (name.isEmpty) return 'image.jpg';
    if (name.length > 80) {
      final int dot = name.lastIndexOf('.');
      final String ext = dot > 0 && name.length - dot <= 8
          ? name.substring(dot)
          : '';
      name = name.substring(0, 80 - ext.length) + ext;
    }
    return name;
  }
}
