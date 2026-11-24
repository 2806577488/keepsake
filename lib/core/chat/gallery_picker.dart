import 'dart:async';

import 'package:flutter/services.dart';

/// 系统图库选图（原生通道 `keepsake/gallery`）——**备选路径**。
///
/// 「从相册选择」的主路径是 App 内相册（`media_gallery.dart` +
/// `features/chat/gallery/`），因为隐式选图 Intent 在国产 ROM 上会被文件管理器
/// 接管。但系统图库仍有它的用处（相册 App 的分类、云端相册、多选习惯），所以
/// 相册页在"没有相册权限"时保留了「用系统图库选」这个出口。
///
/// 原生侧（`MainActivity.kt` + `GalleryTargets.kt`）的顺序是：
/// 1. `ACTION_PICK_IMAGES`（Android 13+ 系统 Photo Picker，AOSP/带 GMS 机型）；
/// 2. 厂商图库：先用 `PackageManager` 找出真正处理 `ACTION_PICK` /
///    `ACTION_GET_CONTENT`（`image/*`）的 Activity，**把文件管理器、文档选择器
///    整体排除**（`OPEN_DOCUMENT` 的响应者 + 包名/类名命中文档特征的一律不要），
///    再逐个 `setPackage(图库包名)` 启动 —— 只有定向启动才不会被"默认应用"
///    带去文件管理器；
/// 3. 一个都用不了时回 `NEED_IN_APP_GALLERY`，由调用方留在 App 内选。
///
/// 返回的是原生复制到 `cacheDir/picked/` 的本地路径，可直接交给
/// `XFile` / 附件流程；用户取消时返回空列表。
class GalleryPicker {
  const GalleryPicker._();

  static const MethodChannel _channel = MethodChannel('keepsake/gallery');

  /// 选图的最长等待时间（M10）。
  ///
  /// 选图期间 App 进程可能被系统（低内存/省电策略）回收，原生侧的
  /// `pendingGalleryResult` 随进程消失，Dart 侧 `invokeMethod` 的 Future
  /// 就永远不完成 —— 界面会一直停在「点了没反应」。90 秒足够用户完成
  /// 一次正常选图（含从云端相册加载），超过就当作被系统打断。
  static const Duration pickTimeout = Duration(seconds: 90);

  /// 打开系统图库选图，返回本地缓存路径列表。
  ///
  /// 失败时抛 [PlatformException]，错误码见 `MainActivity.pickImages`：
  /// - `NEED_IN_APP_GALLERY`：系统里没有真正的图库（只剩文件管理器），
  ///   调用方应改为在 App 内相册里选，**不要**再弹文件管理器；
  /// - `BUSY`：上一次选图未结束；
  /// - `COPY_FAILED`：图库返回了图但一张都没读出来。
  ///
  /// 超过 [pickTimeout] 抛 `PICK_TIMEOUT`（M10：进程被系统回收时通道
  /// 永不返回，必须由 Dart 侧兜底）。
  static Future<List<String>> pickImages() async {
    final List<Object?>? result;
    try {
      result = await _channel
          .invokeMethod<List<Object?>>('pickImages')
          .timeout(pickTimeout);
    } on TimeoutException {
      throw PlatformException(
        code: 'PICK_TIMEOUT',
        message: '选图被系统中断（等待超时）',
      );
    }
    if (result == null) return const <String>[];
    return result.whereType<String>().toList(growable: false);
  }
}
