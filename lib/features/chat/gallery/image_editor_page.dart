/// Keepsake（留声）— 图片编辑页（裁剪 / 旋转 / 镜像）。
///
/// 入口：「相册预览页」的「编辑」按钮，见 [showImageEditor]。
///
/// 为什么把产物写到 App 私有目录 `edited/`：相册里的原图随时可能被用户 / 系统
/// 删掉，而编辑结果要在会话附件里长期可用；另外「编辑」不应覆盖原图（微信也是
/// 另存一张新图），所以每次都生成新文件并通过返回值交给调用方。
///
/// 坐标约定（很重要）：页面里所有裁剪坐标都是"图片显示区域"内的局部坐标
/// （自己按 contain 算出来的 `Rect`），不是全屏坐标、也不是原图像素。只有这
/// 样，留白 / 屏幕尺寸变化时才不会把裁剪框算歪，保存时再一次性映射回像素。
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/ui/toast.dart' show showTopToast;

/// 裁剪框最小边长 = 图片显示区域短边的 20%，并有 48dp 的绝对值下限。
/// （再小的话四角命中区会互相重叠，手指根本捏不住。）
const double _kMinCropRatio = 0.2;

/// 裁剪框最小边长的绝对下限（dp）。
const double _kMinCropSide = 48;

/// 四角命中半径：手指落在某个角 [_kCornerHitRadius] dp 内算"拖角改尺寸"，
/// 否则一律算"拖框移动"（框内框外都可以拖）。
const double _kCornerHitRadius = 32;

/// 输出 PNG 的长边上限（像素）。超过就等比缩小：整张 4K/8K 原图直接编码
/// PNG 又慢又占内存，聊天里也用不着那么大。
const int _kMaxOutputEdge = 2560;

/// 编辑区四周留白（dp）。
const double _kEditorPadding = 16;

/// 打开图片编辑页（裁剪 / 旋转 / 镜像）。
///
/// 返回编辑后新文件的绝对路径；用户取消或解码失败返回 null。
Future<String?> showImageEditor(
  BuildContext context, {
  required String imagePath,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (BuildContext routeContext) =>
          ImageEditorPage(imagePath: imagePath),
    ),
  );
}

/// 图片编辑页（微信式「编辑」：裁剪 / 旋转 / 镜像 / 保存）。
///
/// 页面自己负责返回结果：
/// - 点「完成」→ `Navigator.pop(新文件绝对路径)`；
/// - 点「取消」/「返回」或保存失败 → `Navigator.pop(null)`。
class ImageEditorPage extends StatefulWidget {
  const ImageEditorPage({super.key, required this.imagePath});

  /// 待编辑图片的绝对路径。
  final String imagePath;

  @override
  State<ImageEditorPage> createState() => _ImageEditorPageState();
}

class _ImageEditorPageState extends State<ImageEditorPage> {
  /// 当前编辑中的图；旋转 / 镜像之后是烘焙出来的新图。
  ui.Image? _image;

  /// 解码出来的原图，留给「重置」。
  ui.Image? _original;

  /// 图片显示区域（contain 之后的矩形，局部坐标），每次 build 重新算。
  Rect? _imageRect;

  /// 裁剪框（图片显示区域内的局部坐标）。
  Rect? _crop;

  /// 是否还在解码首帧。
  bool _loading = true;

  /// 是否正在保存（编码 + 写盘）。
  bool _saving = false;

  /// 旋转 / 镜像这类"烘焙"操作是否在跑。
  ///
  /// 为什么要这个闸门：烘焙是异步的，连点两次会同时替换 `_image`，容易把正在
  /// 用的 `ui.Image` dispose 掉。
  bool _busy = false;

  /// 本次手势是拖角还是移框。
  _DragMode _dragMode = _DragMode.none;

  /// 按下点（局部坐标）。
  Offset _dragStart = Offset.zero;

  /// 按下瞬间的裁剪框，拖动量都相对它计算，避免累积误差。
  Rect _cropStart = Rect.zero;

  /// 「完成」是否可点。
  bool get _canSave => _image != null && !_saving && !_busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // 旋转 / 镜像后 `_image` 与 `_original` 是两个不同对象，都要释放；
    // 注意"当前图"若就是原图，只能放一次。
    final ui.Image? current = _image;
    final ui.Image? original = _original;
    if (current != null && !identical(current, original)) {
      current.dispose();
    }
    original?.dispose();
    super.dispose();
  }

  /// 解码原图：`readAsBytes` + `instantiateImageCodec`，失败走「打不开」分支。
  Future<void> _load() async {
    ui.Codec? codec;
    try {
      final Uint8List bytes = await File(widget.imagePath).readAsBytes();
      codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _original = frame.image;
        _image = frame.image;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      // 解码失败不弹窗、也不自动退出：留在页面上显示「这张图片打不开」，
      // 由用户自己点「返回」，这样调用方拿到的仍然是 null。
      setState(() {
        _loading = false;
      });
    } finally {
      // codec 只是解码器，帧出来之后就可以释放；像素在 frame.image 里。
      codec?.dispose();
    }
  }

  /// 取消：返回 null（与系统返回键一致）。
  void _onCancel() {
    Navigator.of(context).pop();
  }

  /// 轻提示（烘焙失败等非致命错误）。
  ///
  /// 走顶部浮层：编辑器底部是「旋转 / 镜像 / 重置」工具条，底部 SnackBar 会盖上去。
  void _showTip(String message) {
    if (!mounted) return;
    showTopToast(context, message);
  }

  /// 顺时针旋转 90°。
  ///
  /// 旋转"烘焙"进新图：旋转后宽高互换，如果只存一个角度，裁剪框映射回原图时
  /// 还要多做一次坐标变换；换成一张方向正确的图，裁剪永远面对同一套坐标。
  Future<void> _rotateRight() async {
    final ui.Image? current = _image;
    if (current == null || _saving || _busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      final int sourceWidth = current.width;
      final int sourceHeight = current.height;
      final ui.Image rotated = await _bake(
        (Canvas canvas) {
          // 顺时针 90°：画布先向右平移"旧高度"，再绕原点旋转，旧图正好落进
          // 宽高互换后的新画布。
          canvas.translate(sourceHeight.toDouble(), 0);
          canvas.rotate(math.pi / 2);
          canvas.drawImage(current, Offset.zero, Paint());
        },
        width: sourceHeight,
        height: sourceWidth,
      );
      if (!mounted) {
        rotated.dispose();
        return;
      }
      setState(() {
        _image = rotated;
        // 宽高互换了，旧裁剪框的比例已经不对 → 清空，等 build 按新图重新铺满。
        _crop = null;
      });
      // 原图要留给「重置」，只释放被替换掉的中间图。
      if (!identical(current, _original)) {
        current.dispose();
      }
    } catch (_) {
      // 极端情况下（内存不足）烘焙失败：保持原图不动，别让页面卡死。
      if (mounted) {
        _showTip('旋转失败，请重试');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  /// 水平镜像。
  ///
  /// 宽高不变，所以裁剪框原样保留（用户只是想左右翻一下）。
  Future<void> _flipHorizontal() async {
    final ui.Image? current = _image;
    if (current == null || _saving || _busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      final int width = current.width;
      final int height = current.height;
      final ui.Image flipped = await _bake(
        (Canvas canvas) {
          // 水平镜像：先平移到右边缘，再沿 x 轴翻转画布，旧图就对称画回来了。
          canvas.translate(width.toDouble(), 0);
          canvas.scale(-1, 1);
          canvas.drawImage(current, Offset.zero, Paint());
        },
        width: width,
        height: height,
      );
      if (!mounted) {
        flipped.dispose();
        return;
      }
      setState(() {
        _image = flipped;
      });
      if (!identical(current, _original)) {
        current.dispose();
      }
    } catch (_) {
      if (mounted) {
        _showTip('镜像失败，请重试');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  /// 重置：回到解码出来的原图，并把裁剪框重新铺满。
  void _reset() {
    final ui.Image? original = _original;
    if (original == null || _saving || _busy) {
      return;
    }
    final ui.Image? current = _image;
    setState(() {
      _image = original;
      // 置空后 build 里会按当前显示区域重新铺满。
      _crop = null;
    });
    if (current != null && !identical(current, original)) {
      current.dispose();
    }
  }

  /// 用 [paint] 把当前图重画到一张新画布上，返回新的 `ui.Image`。
  ///
  /// 旋转 / 镜像都靠它"烘焙"成一张方向正确的图，见 [_rotateRight] 的说明。
  Future<ui.Image> _bake(
    void Function(Canvas canvas) paint, {
    required int width,
    required int height,
  }) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    paint(canvas);
    final ui.Picture picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  /// 「完成」：裁剪框 → 原图像素 → 输出 PNG（长边 ≤ [_kMaxOutputEdge]）→ 写盘。
  Future<void> _save() async {
    final ui.Image? image = _image;
    final Rect? imageRect = _imageRect;
    final Rect? crop = _crop;
    if (image == null || imageRect == null || crop == null) {
      return;
    }
    if (_saving || _busy) {
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      // 显示坐标 → 原图像素：裁剪框是图片显示区域内的局部坐标，先减掉区域
      // 左上角，再乘"像素 / 显示"的比例。
      final double scaleX = image.width / imageRect.width;
      final double scaleY = image.height / imageRect.height;
      final double maxX = image.width.toDouble();
      final double maxY = image.height.toDouble();
      final Rect src = Rect.fromLTRB(
        _clamp((crop.left - imageRect.left) * scaleX, 0, maxX),
        _clamp((crop.top - imageRect.top) * scaleY, 0, maxY),
        _clamp((crop.right - imageRect.left) * scaleX, 0, maxX),
        _clamp((crop.bottom - imageRect.top) * scaleY, 0, maxY),
      );

      // 长边上限 2560：只缩不放，保持等比；极小裁剪也至少输出 1px。
      final double longest = math.max(src.width, src.height);
      final double scale = longest > _kMaxOutputEdge
          ? _kMaxOutputEdge / longest
          : 1;
      final int outWidth = math.max(1, (src.width * scale).round());
      final int outHeight = math.max(1, (src.height * scale).round());

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        src,
        Rect.fromLTWH(0, 0, outWidth.toDouble(), outHeight.toDouble()),
        Paint(),
      );
      final ui.Picture picture = recorder.endRecording();
      final ui.Image output;
      try {
        output = await picture.toImage(outWidth, outHeight);
      } finally {
        picture.dispose();
      }

      final ByteData? data;
      try {
        data = await output.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        output.dispose();
      }
      if (data == null) {
        throw const FileSystemException('PNG 编码失败');
      }

      final Directory support = await getApplicationSupportDirectory();
      final Directory dir = Directory('${support.path}/edited');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      // 文件名带毫秒时间戳：同一张图反复编辑不会互相覆盖。
      final File file = File(
        '${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(
        // ByteData 的 offsetInBytes 不一定是 0：按真实窗口取字节，
        // 否则 PNG 头前面可能多出一段脏数据（图就坏了）。
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(file.path);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
      });
      // 先提示再退出：调用方拿到 null 只会当成"用户取消"，不提示的话用户
      // 会以为点了没反应。
      _showTip('保存失败：$error');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 刻意固定纯黑，不用 KeepsakeSkinColors：照片编辑需要中性的深色背景，
      // 皮肤 token 的彩色会干扰用户对亮度 / 色彩的判断（系统相册编辑页同理）。
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildTopBar(),
            Expanded(child: _buildEditor()),
            if (_image != null) _buildToolbar(),
          ],
        ),
      ),
    );
  }

  /// 顶部：左「取消」、右「完成」。
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: <Widget>[
          TextButton(
            // 保存 / 烘焙途中不放行退出：此时正在用 `_image` 编码，退出会释放它。
            onPressed: (_saving || _busy) ? null : _onCancel,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white38,
            ),
            child: const Text('取消'),
          ),
          const Spacer(),
          TextButton(
            onPressed: _canSave ? _save : null,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white38,
            ),
            child: Text(_saving ? '处理中…' : '完成'),
          ),
        ],
      ),
    );
  }

  /// 编辑区：加载态 / 解码失败态 / 图片 + 裁剪蒙层。
  Widget _buildEditor() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    final ui.Image? image = _image;
    if (image == null) {
      return _buildDecodeError();
    }
    return Padding(
      padding: const EdgeInsets.all(_kEditorPadding),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size area = Size(constraints.maxWidth, constraints.maxHeight);
          final Rect imageRect = _containRect(
            Size(image.width.toDouble(), image.height.toDouble()),
            area,
          );
          final Rect crop = _syncCrop(imageRect);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: (DragEndDetails details) {
              _endDrag();
            },
            onPanCancel: _endDrag,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // RawImage 只负责"把图铺满 contain 出来的矩形"，不参与手势。
                Positioned.fromRect(
                  rect: imageRect,
                  child: RawImage(
                    image: image,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                // 框外暗化 + 三分线 + 四角角标一次画完；4 块 Container 拼
                // 会有接缝，还会平白多出 4 个拦截手势的层。
                CustomPaint(painter: _CropOverlayPainter(crop: crop)),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 解码失败态：「这张图片打不开」+「返回」。
  Widget _buildDecodeError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            '这张图片打不开',
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _onCancel,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }

  /// 底部工具条：旋转 / 镜像 / 重置，三列均分。
  Widget _buildToolbar() {
    final bool enabled = _canSave;
    return Container(
      // 工具条也保持纯黑，和编辑区一致（同样刻意不用皮肤 token）。
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _ToolButton(
              icon: Icons.rotate_right,
              label: '旋转',
              onTap: enabled ? _rotateRight : null,
            ),
          ),
          Expanded(
            child: _ToolButton(
              icon: Icons.flip,
              label: '镜像',
              onTap: enabled ? _flipHorizontal : null,
            ),
          ),
          Expanded(
            child: _ToolButton(
              icon: Icons.restart_alt,
              label: '重置',
              onTap: enabled ? _reset : null,
            ),
          ),
        ],
      ),
    );
  }

  /// 在 [area] 里按 contain 算出图片显示矩形（居中、局部坐标）。
  Rect _containRect(Size imageSize, Size area) {
    if (imageSize.isEmpty || area.isEmpty) {
      return Offset.zero & area;
    }
    final double scale = math.min(
      area.width / imageSize.width,
      area.height / imageSize.height,
    );
    final double width = imageSize.width * scale;
    final double height = imageSize.height * scale;
    return Rect.fromLTWH(
      (area.width - width) / 2,
      (area.height - height) / 2,
      width,
      height,
    );
  }

  /// 布局阶段同步"图片显示区域 / 裁剪框"到字段，供手势与保存使用。
  ///
  /// 为什么在 build 里写字段：contain 的结果只有拿到约束时才知道，而手势回调
  /// 需要同一套局部坐标，所以在构建时缓存一次（不 setState，避免构建中刷新）。
  Rect _syncCrop(Rect imageRect) {
    final Rect? previous = _imageRect;
    if (previous == null || previous != imageRect) {
      // 首帧 / 转屏 / 旋转后图片尺寸变了：裁剪框重新铺满。
      _imageRect = imageRect;
      _crop = imageRect;
    }
    final Rect crop = _clampCrop(_crop ?? imageRect, imageRect);
    _crop = crop;
    return crop;
  }

  /// 判断按下点离哪个角最近（[threshold] 内才算拖角）。
  _DragMode _closestCorner(Rect crop, Offset point, double threshold) {
    final List<Offset> corners = <Offset>[
      crop.topLeft,
      crop.topRight,
      crop.bottomRight,
      crop.bottomLeft,
    ];
    final List<_DragMode> modes = <_DragMode>[
      _DragMode.topLeft,
      _DragMode.topRight,
      _DragMode.bottomRight,
      _DragMode.bottomLeft,
    ];
    _DragMode result = _DragMode.none;
    double nearest = threshold;
    for (int index = 0; index < corners.length; index++) {
      final double distance = (point - corners[index]).distance;
      if (distance <= nearest) {
        nearest = distance;
        result = modes[index];
      }
    }
    return result;
  }

  void _onPanStart(DragStartDetails details) {
    final Rect? crop = _crop;
    final Rect? imageRect = _imageRect;
    if (crop == null || imageRect == null || _saving || _busy) {
      return;
    }
    final Offset point = details.localPosition;
    // 角落 32dp 内算改尺寸；其余（框内或框外）都算搬整个框。
    _dragMode = _closestCorner(crop, point, _kCornerHitRadius);
    if (_dragMode == _DragMode.none) {
      _dragMode = _DragMode.move;
    }
    _dragStart = point;
    _cropStart = crop;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final Rect? bounds = _imageRect;
    if (bounds == null || _dragMode == _DragMode.none || _saving || _busy) {
      return;
    }
    final Offset delta = details.localPosition - _dragStart;
    final Rect base = _cropStart;
    Rect next;
    if (_dragMode == _DragMode.move) {
      // 整框平移：只夹平移量，尺寸不变，保证框始终在图片显示区域内。
      next = _shiftWithin(base, delta, bounds);
    } else {
      final double minSide = _minCropSide(bounds);
      double left = base.left;
      double top = base.top;
      double right = base.right;
      double bottom = base.bottom;
      final bool movingLeft =
          _dragMode == _DragMode.topLeft || _dragMode == _DragMode.bottomLeft;
      final bool movingTop =
          _dragMode == _DragMode.topLeft || _dragMode == _DragMode.topRight;
      final bool movingRight =
          _dragMode == _DragMode.topRight || _dragMode == _DragMode.bottomRight;
      final bool movingBottom =
          _dragMode == _DragMode.bottomLeft ||
          _dragMode == _DragMode.bottomRight;
      // 每次拖动都相对 `_cropStart` 计算，并用对角边 + 最小边长做 clamp。
      if (movingLeft) {
        left = _clamp(base.left + delta.dx, bounds.left, base.right - minSide);
      }
      if (movingTop) {
        top = _clamp(base.top + delta.dy, bounds.top, base.bottom - minSide);
      }
      if (movingRight) {
        right = _clamp(
          base.right + delta.dx,
          base.left + minSide,
          bounds.right,
        );
      }
      if (movingBottom) {
        bottom = _clamp(
          base.bottom + delta.dy,
          base.top + minSide,
          bounds.bottom,
        );
      }
      next = Rect.fromLTRB(left, top, right, bottom);
    }
    setState(() {
      _crop = next;
    });
  }

  void _endDrag() {
    _dragMode = _DragMode.none;
  }

  /// 图片显示区域短边的 20%，下限 48dp；显示区域本身更小时以显示区域为上限。
  double _minCropSide(Rect bounds) {
    final double shortSide = math.min(bounds.width, bounds.height);
    final double ratioSide = shortSide * _kMinCropRatio;
    return math.min(math.max(_kMinCropSide, ratioSide), shortSide);
  }

  /// 把裁剪框夹回 [bounds] 内（同时兜住最小边长）。
  Rect _clampCrop(Rect crop, Rect bounds) {
    final double minSide = _minCropSide(bounds);
    final double width = _clamp(crop.width, minSide, bounds.width);
    final double height = _clamp(crop.height, minSide, bounds.height);
    final double left = _clamp(crop.left, bounds.left, bounds.right - width);
    final double top = _clamp(crop.top, bounds.top, bounds.bottom - height);
    return Rect.fromLTWH(left, top, width, height);
  }

  /// 平移 [crop] 但不改尺寸，并保证结果仍在 [bounds] 内。
  Rect _shiftWithin(Rect crop, Offset delta, Rect bounds) {
    final double dx = _clamp(
      delta.dx,
      bounds.left - crop.left,
      bounds.right - crop.right,
    );
    final double dy = _clamp(
      delta.dy,
      bounds.top - crop.top,
      bounds.bottom - crop.bottom,
    );
    return crop.shift(Offset(dx, dy));
  }
}

/// 底部工具条的一个按钮：白色图标 + 12sp 文案（三列均分）。
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;

  final String label;

  /// null 表示禁用（加载中 / 保存中 / 没有图）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = onTap == null ? Colors.white38 : Colors.white;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 26, color: color),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

/// 裁剪蒙层：框外暗化 + 三分线 + 四角 L 形角标，一次画完。
///
/// 为什么用一个 CustomPainter：用 4 块半透明 Container 拼框外暗化会有接缝，
/// 也会多出 4 个拦截手势的层；这里一次 Path 差集 + 几条线就够。
class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({required this.crop});

  /// 裁剪框（图片显示区域内的局部坐标）。
  final Rect crop;

  /// 框外暗化透明度（需求固定 0.55）。
  static const double _scrimAlpha = 0.55;

  /// 操作提示线透明度和角标尺寸（每边 18dp、线宽 3dp）。
  static const double _gridAlpha = 0.2;
  static const double _cornerLength = 18;
  static const double _cornerWidth = 3;

  @override
  void paint(Canvas canvas, Size size) {
    // 框外暗化：整个画布减去裁剪框，一次画完。
    final Path outside = Path.combine(
      ui.PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(crop),
    );
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: _scrimAlpha),
    );

    // 三分线：白色 20%，只在框内，帮用户对齐主体。
    final Paint grid = Paint()
      ..color = Colors.white.withValues(alpha: _gridAlpha)
      ..strokeWidth = 1;
    final double x1 = crop.left + crop.width / 3;
    final double x2 = crop.left + crop.width * 2 / 3;
    final double y1 = crop.top + crop.height / 3;
    final double y2 = crop.top + crop.height * 2 / 3;
    canvas.drawLine(Offset(x1, crop.top), Offset(x1, crop.bottom), grid);
    canvas.drawLine(Offset(x2, crop.top), Offset(x2, crop.bottom), grid);
    canvas.drawLine(Offset(crop.left, y1), Offset(crop.right, y1), grid);
    canvas.drawLine(Offset(crop.left, y2), Offset(crop.right, y2), grid);

    // 四角 L 形角标。
    final Paint corner = Paint()
      ..color = Colors.white
      ..strokeWidth = _cornerWidth
      ..style = PaintingStyle.stroke;
    final Path corners = Path();
    // 左上
    corners.moveTo(crop.left, crop.top + _cornerLength);
    corners.lineTo(crop.left, crop.top);
    corners.lineTo(crop.left + _cornerLength, crop.top);
    // 右上
    corners.moveTo(crop.right - _cornerLength, crop.top);
    corners.lineTo(crop.right, crop.top);
    corners.lineTo(crop.right, crop.top + _cornerLength);
    // 右下
    corners.moveTo(crop.right, crop.bottom - _cornerLength);
    corners.lineTo(crop.right, crop.bottom);
    corners.lineTo(crop.right - _cornerLength, crop.bottom);
    // 左下
    corners.moveTo(crop.left + _cornerLength, crop.bottom);
    corners.lineTo(crop.left, crop.bottom);
    corners.lineTo(crop.left, crop.bottom - _cornerLength);
    canvas.drawPath(corners, corner);
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) =>
      oldDelegate.crop != crop;
}

/// 当前手势：拖框整体移动，或拖某个角改尺寸。
enum _DragMode { none, move, topLeft, topRight, bottomRight, bottomLeft }

/// 把 [value] 限制在 [min]~[max]。
///
/// 用自写的 clamp 而不是 `num.clamp`：后者返回 num，每处都要补 `.toDouble()`，
/// 拖角那段会变得很难读。
double _clamp(double value, double min, double max) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}
