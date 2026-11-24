/// Keepsake（留声）— 相册大图预览页（微信式）。
///
/// 从相册网格长按/点「预览」进入：
/// - 左右滑翻页，底部「勾选」把当前这张加入/移出选择；
/// - 底部「编辑」直接在 App 内裁剪 / 旋转 / 镜像（[showImageEditor]），
///   编辑产物落在私有目录，返回后当前这张自动选中；
/// - 「发送(n)」回到相册并带着选择集合，由相册页统一复制/回传路径。
///
/// 为什么固定黑底 + 白字：大图预览和图片编辑都用中性深色（照片判色更准），
/// 这里刻意不用皮肤 token —— 皮肤切换不该影响照片预览的对比度。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/chat/media_gallery.dart';
import '../../../core/ui/toast.dart' show showTopToast;
import 'image_editor_page.dart';

/// 预览页回传结果。
class GalleryPreviewResult {
  const GalleryPreviewResult({required this.selection, this.done = false});

  /// 预览页里更新过的选择（id → 最新版本，可能已被编辑）。
  final Map<String, MediaImage> selection;

  /// 是否在预览页直接点了「完成」（相册页据此立即结束选择）。
  final bool done;
}

/// 大图预览页。
class GalleryPreviewPage extends StatefulWidget {
  const GalleryPreviewPage({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.selected,
    required this.maxCount,
  });

  /// 预览池：没有选择时是整页列表，有选择时是已选中的那些。
  final List<MediaImage> images;

  /// 初始翻到第几张。
  final int initialIndex;

  /// 进入时的选择集合（有序）。
  final Map<String, MediaImage> selected;

  /// 最多能选几张。
  final int maxCount;

  @override
  State<GalleryPreviewPage> createState() => _GalleryPreviewPageState();
}

class _GalleryPreviewPageState extends State<GalleryPreviewPage> {
  late final PageController _controller;
  late final List<MediaImage> _items;
  late final Map<String, MediaImage> _selected;
  late int _index;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _items = List<MediaImage>.of(widget.images);
    _selected = Map<String, MediaImage>.of(widget.selected);
    // int.clamp 的返回类型是 num，这里手写边界判断，避免隐式类型问题。
    final int last = _items.isEmpty ? 0 : _items.length - 1;
    _index = widget.initialIndex < 0
        ? 0
        : (widget.initialIndex > last ? last : widget.initialIndex);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  MediaImage get _current => _items[_index];

  bool get _currentSelected => _selected.containsKey(_current.id);

  void _notify(String message) {
    if (!mounted) return;
    // 顶部浮层：黑底预览页底部那一条是「编辑 / 勾选 / 发送」，不能被提示盖住。
    showTopToast(context, message);
  }

  void _toggleCurrent() {
    final MediaImage image = _current;
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

  Future<void> _editCurrent() async {
    if (_editing) return;
    final MediaImage image = _current;
    setState(() => _editing = true);
    String? path;
    try {
      path = await showImageEditor(context, imagePath: image.path);
    } catch (error) {
      _notify('打开编辑器失败：$error');
    } finally {
      if (mounted) setState(() => _editing = false);
    }
    if (path == null || !mounted) return;
    final MediaImage edited = image.copyWith(path: path, edited: true);
    setState(() {
      _items[_index] = edited;
      // 编辑出来就是要用的：自动选中（微信编辑完也是直接带上）。
      _selected[edited.id] = edited;
    });
  }

  void _close({bool done = false}) {
    Navigator.of(context).pop(
      GalleryPreviewResult(selection: _selected, done: done),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<GalleryPreviewResult>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, GalleryPreviewResult? result) {
        if (didPop) return;
        _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: <Widget>[
            Positioned.fill(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (int index) => setState(() => _index = index),
                itemCount: _items.length,
                itemBuilder: (BuildContext context, int index) {
                  return Center(
                    child: Image.file(
                      File(_items[index].path),
                      fit: BoxFit.contain,
                      errorBuilder: (
                        BuildContext context,
                        Object error,
                        StackTrace? stack,
                      ) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            '这张图片打不开',
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _buildTopBar(),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomBar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: Colors.black.withValues(alpha: 0.35),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: <Widget>[
              IconButton(
                onPressed: () => _close(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                tooltip: '返回',
              ),
              const Spacer(),
              Text(
                '${_index + 1}/${_items.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final int count = _selected.length;
    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: <Widget>[
              TextButton(
                onPressed: _editing ? null : () => _editCurrent(),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: Text(_editing ? '处理中…' : '编辑'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _toggleCurrent,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                icon: Icon(
                  _currentSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: _currentSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white,
                ),
                label: Text(_currentSelected ? '已选' : '勾选'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: count == 0 ? null : () => _close(done: true),
                child: Text('发送($count)'),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}
