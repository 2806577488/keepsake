/// Keepsake（留声）— 微信式相册选择页（全屏）。
///
/// 为什么自己画相册，而不是继续调系统选图 Intent：
/// 国产 ROM 上 `ACTION_GET_CONTENT` 同时被「图库」和「文件管理」注册，系统按
/// 默认应用/上次选择直接进文件管理器（DocumentsUI 的「最近」）—— 连续几个
/// 版本调 Intent 顺序、`resolveActivity`、`<queries>` 都没能根治，因为只要还是
/// **隐式 Intent**，进哪个界面就由 ROM 决定。改成 App 内相册之后，数据来自
/// MediaStore（`keepsake/media` 通道），界面完全在 Flutter 里，**不可能**再跳出
/// 去打开文件管理器。
///
/// 交互对齐微信「从相册选择」：
/// - 顶部：✕ / 标题（`图片和视频 ▾` 或当前目录名，点开右侧抽屉切换分类）；
/// - 分类抽屉：`图片和视频 (2514)` / `截屏 (263)` / `微信 (502)` / `相机 (1163)` …
///   每行「名称 (张数)」，当前项打勾（Camera→相机、Screenshots→截屏、
///   WeiXin→微信；DCIM / QQ / 知乎 这类原样保留，和微信一致）；
/// - 网格：4 列方形缩略图，按天分组（今天 / 昨天 / 11月22日），选中项右上角
///   显示序号（1…N），再点取消；
/// - 底部：预览（空选时预览全部）/ 发送（n）；
/// - 预览页里可以左右翻、在 App 内裁剪/旋转/镜像后发出去。
library;

import 'dart:async';
import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/chat/gallery_picker.dart' show GalleryPicker;
import '../../../core/chat/media_gallery.dart';
import '../../../core/theme.dart';
import '../../../core/ui/toast.dart' show showTopToast;
import 'gallery_preview_page.dart';

/// 打开相册选择页；返回选中图片的**本地路径**（已复制到 App 私有目录）。
///
/// 用户取消时有三种情况都返回空列表：返回手势、左上角「取消」、没选就退出。
Future<List<String>> showGalleryPage(
  BuildContext context, {
  int maxCount = 9,
}) async {
  final List<String>? picked = await Navigator.of(context).push<List<String>>(
    MaterialPageRoute<List<String>>(
      fullscreenDialog: true,
      builder: (BuildContext routeContext) =>
          GalleryPage(maxCount: maxCount < 1 ? 1 : maxCount),
    ),
  );
  return picked ?? const <String>[];
}

/// 全屏相册选择页。
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key, required this.maxCount});

  /// 本次最多选几张（"这条消息还能再加几个附件"）。
  final int maxCount;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  /// 每页 60：4 列 × 15 行，滚到底再取下一批。
  static const int _pageSize = 60;

  final ScrollController _scroll = ScrollController();
  final List<MediaImage> _images = <MediaImage>[];

  /// 选中项按点击顺序排列（序号 = 位置 + 1），value 是该图的最新版本
  /// （可能已被编辑过，path 指向私有目录里的新文件）。
  final Map<String, MediaImage> _selected = <String, MediaImage>{};

  final List<MediaBucket> _buckets = <MediaBucket>[];

  late MediaBucket _bucket = const MediaBucket(id: '', name: '图片和视频');

  MediaAccess _access = MediaAccess.full;
  bool _probing = true;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _finishing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_loadingMore || !_hasMore) return;
    final ScrollPosition position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      unawaited(_loadMore());
    }
  }

  // -------------------------------------------------------------------------
  // 数据
  // -------------------------------------------------------------------------

  Future<void> _bootstrap() async {
    setState(() {
      _probing = true;
      _error = null;
    });
    MediaAccess access = await MediaGallery.access();
    if (access == MediaAccess.none) {
      await MediaGallery.request();
      access = await MediaGallery.access();
    }
    if (!mounted) return;
    setState(() {
      _access = access;
      _probing = false;
    });
    if (access == MediaAccess.none) return;
    unawaited(_loadCatalog());
    await _reload();
  }

  /// 目录名的中文化（微信里 Camera/Screenshots/WeiXin 也是换中文显示的）。
  ///
  /// 只映射"众所周知"的几个；DCIM / Pictures / QQ / 知乎 这类在微信里同样
  /// 原样显示 —— 硬翻成中文反而认不出来（用户的相机胶卷就叫 DCIM）。
  static const Map<String, String> _bucketAliases = <String, String>{
    'camera': '相机',
    'screenshots': '截屏',
    'screenshot': '截屏',
    'screen_shots': '截屏',
    'screen_shot': '截屏',
    'weixin': '微信',
    'wechat': '微信',
    'downloads': '下载',
  };

  String _localizedBucketName(String raw) {
    final String name = raw.trim();
    return _bucketAliases[name.toLowerCase()] ?? name;
  }

  Future<void> _loadCatalog() async {
    try {
      final MediaCatalog catalog = await MediaGallery.catalog();
      if (!mounted) return;
      setState(() {
        _buckets
          ..clear()
          ..add(MediaBucket(id: '', name: '图片和视频', count: catalog.total))
          ..addAll(
            catalog.buckets.map(
              (MediaBucket bucket) => MediaBucket(
                id: bucket.id,
                name: _localizedBucketName(bucket.name),
                count: bucket.count,
                cover: bucket.cover,
              ),
            ),
          );
        // 选中的目录可能因为张数变化需要替换（id 不变，标题跟着刷新）。
        for (final MediaBucket bucket in _buckets) {
          if (bucket.id == _bucket.id) {
            _bucket = bucket;
            break;
          }
        }
      });
    } catch (_) {
      // 分类拿不到不影响主流程：网格仍然按"图片和视频"显示。
    }
  }

  Future<void> _reload() async {
    setState(() {
      _images.clear();
      _hasMore = true;
      _loading = true;
      _error = null;
    });
    await _loadMore();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final List<MediaImage> page = await MediaGallery.list(
        offset: _images.length,
        limit: _pageSize,
        bucketId: _bucket.id,
      );
      if (!mounted) return;
      setState(() {
        _images.addAll(page);
        _hasMore = page.length >= _pageSize;
        _loadingMore = false;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = error.code == 'NO_PERMISSION'
            ? '还没有「照片和视频」权限'
            : (error.message ?? '读取相册失败');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = '读取相册失败：$error';
      });
    }
  }

  // -------------------------------------------------------------------------
  // 选择 / 预览 / 完成
  // -------------------------------------------------------------------------

  void _toggle(MediaImage image) {
    final bool selected = _selected.containsKey(image.id);
    if (!selected && _selected.length >= widget.maxCount) {
      _notify('这一条消息最多还能选 ${widget.maxCount} 张');
      return;
    }
    setState(() {
      if (selected) {
        _selected.remove(image.id);
      } else {
        _selected[image.id] = image;
      }
    });
  }

  /// 预览：没选中时预览当前列表里全部图（微信行为），选中后只翻选中的。
  ///
  /// [forceAll] 用于长按某一格："我想先看看这张大图"，即使已有选择也翻全量
  /// 列表；选择集合本身照样带进去，可以在预览里继续勾。
  Future<void> _openPreview({int initialIndex = 0, bool forceAll = false}) async {
    if (_images.isEmpty) return;
    final bool useSelection = _selected.isNotEmpty && !forceAll;
    final List<MediaImage> pool = useSelection
        ? _selected.values.toList(growable: false)
        : List<MediaImage>.of(_images);
    final int last = pool.length - 1;
    final int start =
        useSelection || initialIndex > last ? (useSelection ? 0 : last) : initialIndex;
    final GalleryPreviewResult? result =
        await Navigator.of(context).push<GalleryPreviewResult>(
      MaterialPageRoute<GalleryPreviewResult>(
        fullscreenDialog: true,
        builder: (BuildContext routeContext) => GalleryPreviewPage(
          images: pool,
          initialIndex: start < 0 ? 0 : start,
          selected: Map<String, MediaImage>.of(_selected),
          maxCount: widget.maxCount,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _selected
        ..clear()
        ..addAll(result.selection);
    });
    // 在预览页直接点了「完成」→ 相册页也立刻结束选择。
    if (result.done) await _finish();
  }

  /// 完成：编辑过的直接用私有目录里的新文件，其余复制到私有目录。
  Future<void> _finish() async {
    if (_finishing || _selected.isEmpty) return;
    setState(() => _finishing = true);
    final List<String> paths = <String>[];
    int seq = 0;
    for (final MediaImage image in _selected.values) {
      if (image.edited) {
        paths.add(image.path);
        continue;
      }
      paths.add(await MediaGallery.preserve(image, seq: seq));
      seq += 1;
    }
    if (!mounted) return;
    Navigator.of(context).pop(paths);
  }

  Future<void> _pickBucket() async {
    if (_buckets.length <= 1) {
      _notify('这台设备的相册里还没有分类');
      return;
    }
    final MediaBucket? picked = await _showBucketPanel();
    if (picked == null || !mounted || picked.id == _bucket.id) return;
    setState(() => _bucket = picked);
    await _reload();
  }

  /// 微信式的相册分类面板：从右侧滑出、盖住约 86% 宽度，左边留一条网格做"底"。
  ///
  /// 为什么不用 `showModalBottomSheet`：微信这个列表是**右侧整屏抽屉**，
  /// 用户能一眼看到"我在哪一层"（左边还是相册网格），底部弹层表达不出这层
  /// 结构。`showGeneralDialog` + `SlideTransition` 就能得到同样的手感。
  Future<MediaBucket?> _showBucketPanel() {
    return showGeneralDialog<MediaBucket>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '相册分类',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (
        BuildContext dialogContext,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        return _BucketPanel(buckets: _buckets, current: _bucket);
      },
      transitionBuilder: (
        BuildContext dialogContext,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget child,
      ) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        );
      },
    );
  }

  Future<void> _openSettings() async {
    final bool opened = await openAppSettings();
    if (!opened && mounted) {
      _notify('打不开系统设置：手动到 设置 > 应用 > Keepsake > 权限 里允许照片');
    }
  }

  /// 兜底出口：相册权限被拒时，交给系统图库选。
  ///
  /// 原生侧只允许启动真正的图库 Activity（`GalleryTargets.kt`），文件管理器
  /// 会被排除；一个都找不到时回 `NEED_IN_APP_GALLERY` —— 也就是"老老实实
  /// 回 App 内"，**不会再跳文件管理器**。
  Future<void> _pickFromSystemGallery() async {
    try {
      final List<String> paths = await GalleryPicker.pickImages();
      if (!mounted || paths.isEmpty) return;
      Navigator.of(context).pop(paths);
    } on PlatformException catch (error) {
      if (!mounted) return;
      switch (error.code) {
        case 'NEED_IN_APP_GALLERY':
          _notify('这台设备没有可用的系统图库，授权后就能用 App 内相册');
          break;
        case 'PICK_TIMEOUT':
          _notify('上次选图被系统中断了，请再试一次');
          break;
        case 'BUSY':
          _notify('上一次选图还没结束，稍等一下再点');
          break;
        default:
          _notify('打开系统图库失败：${error.message ?? error.code}');
      }
    } catch (error) {
      if (!mounted) return;
      _notify('打开系统图库失败：$error');
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    // 顶部浮层：底部 SnackBar 会压住「预览 / 发送」那一条。
    showTopToast(context, message);
  }

  // -------------------------------------------------------------------------
  // 构建
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final KeepsakeSkinColors skin = KeepsakeSkinColors.of(context);
    return Scaffold(
      backgroundColor: skin.c.surface,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildTopBar(skin),
            Expanded(child: _buildBody(skin)),
            if (_access != MediaAccess.none && _probing == false)
              _buildBottomBar(skin),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(KeepsakeSkinColors skin) {
    return SizedBox(
      height: 52,
      child: Row(
        children: <Widget>[
          // 微信左上角是 ✕（不是文字「取消」）：这里给同样的语义，
          // tooltip / 无障碍标签仍然写「取消」。
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            tooltip: '取消',
          ),
          Expanded(
            child: Center(
              // 微信顶部是「图片和视频 ⌃」这样一枚胶囊，点开就是分类抽屉。
              child: Material(
                color: skin.c.high,
                borderRadius: skin.rPill,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => unawaited(_pickBucket()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            _bucket.id.isEmpty ? '图片和视频' : _bucket.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: skin.fsBody,
                              fontWeight: skin.titleWeight,
                              color: skin.c.onS,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.expand_more, size: 20, color: skin.c.onV),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 右侧留白与左侧图标等宽，保证标题真正居中。
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildBody(KeepsakeSkinColors skin) {
    if (_probing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_access == MediaAccess.none) {
      return _buildPermissionPanel(skin);
    }
    if (_error != null) {
      return _buildMessagePanel(
        skin,
        icon: Icons.error_outline,
        title: _error!,
        actionLabel: '重试',
        onAction: () => unawaited(_reload()),
      );
    }
    if (_images.isEmpty) {
      if (_loading || _loadingMore) {
        return const Center(child: CircularProgressIndicator());
      }
      return _buildMessagePanel(
        skin,
        icon: Icons.photo_library_outlined,
        title: '这个相册里还没有图片',
        subtitle: '拍一张，或从「文件」入口选图片',
        actionLabel: '重新读取',
        onAction: () => unawaited(_reload()),
      );
    }
    return _buildGrid(skin);
  }

  /// 微信式网格：按"天"分组，每组一个日期小标题（今天 / 昨天 / 11月23日）。
  ///
  /// 用 `CustomScrollView` + 多个 `SliverGrid` 而不是一个 `GridView`：分组标题
  /// 必须是整行元素，而 `GridView` 的每个格子尺寸都一样；sliver 组合既保留了
  /// 网格的懒加载，又能插入任意高度的标题。
  Widget _buildGrid(KeepsakeSkinColors skin) {
    final List<String> order = _selected.keys.toList(growable: false);
    final List<Widget> slivers = <Widget>[];
    for (final List<MediaImage> group in _groupByDay()) {
      slivers.add(
        SliverToBoxAdapter(child: _DateHeader(date: group.first.addedAt)),
      );
      slivers.add(
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {
              final MediaImage image = group[index];
              final int position = order.indexOf(image.id);
              return _GalleryTile(
                image: image,
                order: position + 1,
                onTap: () => _toggle(image),
                onLongPress: () => unawaited(
                  _openPreview(
                    initialIndex: _images.indexOf(image),
                    forceAll: true,
                  ),
                ),
              );
            },
            childCount: group.length,
          ),
        ),
      );
    }
    if (_hasMore) {
      slivers.add(
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ),
      );
    }
    return CustomScrollView(controller: _scroll, slivers: slivers);
  }

  /// 把已加载的图片按"天"切组（列表本身已按时间倒序，切出来天然连续）。
  List<List<MediaImage>> _groupByDay() {
    final List<List<MediaImage>> groups = <List<MediaImage>>[];
    DateTime? currentDay;
    for (final MediaImage image in _images) {
      final DateTime added = image.addedAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final DateTime day = DateTime(added.year, added.month, added.day);
      if (currentDay == null || day != currentDay) {
        groups.add(<MediaImage>[]);
        currentDay = day;
      }
      groups.last.add(image);
    }
    return groups;
  }

  Widget _buildPermissionPanel(KeepsakeSkinColors skin) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.photo_library_outlined, size: 44, color: skin.c.onV),
            const SizedBox(height: 12),
            Text(
              '需要「照片和视频」权限才能显示相册',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: skin.fsBody,
                fontWeight: skin.titleWeight,
                color: skin.c.onS,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '只读取图片列表用于选择，不上传、不修改任何文件',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: skin.fsSub, color: skin.c.onV),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => unawaited(_bootstrap()),
              child: const Text('允许访问照片'),
            ),
            TextButton(
              onPressed: () => unawaited(_openSettings()),
              child: const Text('去设置授权'),
            ),
            TextButton(
              onPressed: () => unawaited(_pickFromSystemGallery()),
              child: const Text('用系统图库选'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagePanel(
    KeepsakeSkinColors skin, {
    required IconData icon,
    required String title,
    String? subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: skin.c.onV),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: skin.fsBody, color: skin.c.onS),
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: skin.fsSub, color: skin.c.onV),
              ),
            ],
            const SizedBox(height: 10),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(KeepsakeSkinColors skin) {
    final int count = _selected.length;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: skin.c.low,
        border: Border(top: BorderSide(color: skin.c.ov)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          TextButton(
            onPressed: _images.isEmpty ? null : () => unawaited(_openPreview()),
            child: Text(count > 0 ? '预览($count)' : '预览'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: count == 0 || _finishing
                ? null
                : () => unawaited(_finish()),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, KeepsakeTheme.sheetButtonHeight),
            ),
            // 微信这个位置的文案就是「发送」，不是「完成」。
            child: Text(_finishing ? '处理中…' : '发送($count)'),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// 日期小标题（今天 / 昨天 / 11月23日 / 2025年12月1日）。
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});

  /// 该组里最新一张的拍摄 / 加入时间；查不到时为 null（显示「更早」）。
  final DateTime? date;

  String get _label {
    final DateTime? value = date;
    if (value == null) return '更早';
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime(value.year, value.month, value.day);
    final int diffDays = today.difference(day).inDays;
    if (diffDays == 0) return '今天';
    if (diffDays == 1) return '昨天';
    if (value.year == now.year) return '${value.month}月${value.day}日';
    return '${value.year}年${value.month}月${value.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final KeepsakeSkinColors skin = KeepsakeSkinColors.of(context);
    return Container(
      color: skin.c.surface,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      alignment: Alignment.centerLeft,
      child: Text(
        _label,
        style: TextStyle(
          fontSize: skin.fsSub,
          fontWeight: skin.titleWeight,
          color: skin.c.onS,
        ),
      ),
    );
  }
}

/// 单个格子：缩略图 + 选中遮罩 + 序号徽标。
class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.image,
    required this.order,
    required this.onTap,
    this.onLongPress,
  });

  final MediaImage image;

  /// 选中序号（1 起；0 = 未选中）。
  final int order;

  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final KeepsakeSkinColors skin = KeepsakeSkinColors.of(context);
    final bool selected = order > 0;
    return Semantics(
      button: true,
      selected: selected,
      label: image.name,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.file(
              File(image.path),
              fit: BoxFit.cover,
              // 只按格子大小解码：原图 4000px 直接进内存会把网格拖垮。
              cacheWidth: 360,
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stack) {
                return Container(
                  color: skin.c.high,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 20,
                    color: skin.c.onV,
                  ),
                );
              },
            ),
            if (selected)
              Positioned.fill(
                child: Container(color: skin.c.pC.withValues(alpha: 0.28)),
              ),
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? skin.c.pC
                      : Colors.black.withValues(alpha: 0.28),
                  // 22×22 的胶囊 = 圆形，但仍走 token（页面不许自己 circular）。
                  borderRadius: skin.rPill,
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: selected
                    ? Text(
                        '$order',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: skin.c.onPC,
                        ),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 相册分类面板（微信式右侧抽屉：名称 (张数) + 当前项打勾）。
///
/// 对齐微信的几个细节：
/// - 从右侧滑出、宽约 86%，左边留一条相册网格（用户知道自己在哪一层）；
/// - 每行「名称 (张数)」，当前项右侧一个 ✓；
/// - 行与行之间一条 1px 分隔线，没有封面缩略图（微信也没有，列表更扫得快）。
class _BucketPanel extends StatelessWidget {
  const _BucketPanel({required this.buckets, required this.current});

  final List<MediaBucket> buckets;
  final MediaBucket current;

  @override
  Widget build(BuildContext context) {
    final KeepsakeSkinColors skin = KeepsakeSkinColors.of(context);
    final double panelWidth = MediaQuery.sizeOf(context).width * 0.86;
    final Color accent = Theme.of(context).colorScheme.primary;
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: skin.c.low,
        child: SizedBox(
          width: panelWidth,
          height: double.infinity,
          child: SafeArea(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: buckets.length,
              separatorBuilder: (BuildContext context, int index) =>
                  Divider(height: 1, thickness: 1, color: skin.c.ov),
              itemBuilder: (BuildContext context, int index) {
                final MediaBucket bucket = buckets[index];
                final bool active = bucket.id == current.id;
                return InkWell(
                  onTap: () => Navigator.of(context).pop(bucket),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
                    child: Row(
                      children: <Widget>[
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              text: bucket.name,
                              style: TextStyle(
                                fontSize: skin.fsTitle,
                                fontWeight: active
                                    ? skin.titleWeight
                                    : FontWeight.w400,
                                color: skin.c.onS,
                              ),
                              children: <InlineSpan>[
                                if (bucket.count > 0)
                                  TextSpan(
                                    text: ' (${bucket.count})',
                                    style: TextStyle(
                                      fontSize: skin.fsSub,
                                      fontWeight: FontWeight.w400,
                                      color: skin.c.onV,
                                    ),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (active) Icon(Icons.check, size: 22, color: accent),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
