/// Keepsake（留声）— 图片尺寸读取 / 缩放 / 压缩。
///
/// 符号证据（`reports/apk/dart-symbols.md` §2）：`compressImage`、`imageSizeOf`、
/// `shrinkImage`、`decodeResize`、`TargetImageSize`、`compressionQuality`；
/// 文案（ui-strings §3）：`已压缩 `、`正在读取…`。
///
/// 说明：Flutter 的 `dart:ui` 只能编码 PNG（`ImageByteFormat.png`），
/// 没有 JPEG 编码器；这里的「压缩」= 限制长边 + 按目标字节数逐级缩小，
/// 输出 PNG。行为对附件预览/上传足够（尺寸与体积都由 `compressImage` 保证）。
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 图片工具错误（可直接展示）。
class ImageUtilException implements Exception {
  const ImageUtilException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// 图片像素尺寸。
class ImageSize {
  const ImageSize(this.width, this.height);

  final int width;
  final int height;

  static const ImageSize zero = ImageSize(0, 0);

  int get longEdge => width > height ? width : height;

  int get shortEdge => width < height ? width : height;

  double get aspectRatio => height <= 0 ? 0 : width / height;

  bool get isValid => width > 0 && height > 0;

  @override
  String toString() => '${width}x$height';
}

/// 缩放目标尺寸（等比装进 [maxEdge]）。
class TargetImageSize {
  const TargetImageSize(this.width, this.height);

  final int width;
  final int height;

  int get longEdge => width > height ? width : height;

  /// 等比缩放到长边不超过 [maxEdge]；本来就不超时原样返回。
  factory TargetImageSize.contain(
    int width,
    int height, {
    int maxEdge = kDefaultMaxImageEdge,
  }) {
    if (width <= 0 || height <= 0 || maxEdge <= 0) {
      return TargetImageSize(math.max(0, width), math.max(0, height));
    }
    final edge = width > height ? width : height;
    if (edge <= maxEdge) return TargetImageSize(width, height);
    final scale = maxEdge / edge;
    return TargetImageSize(
      math.max(1, (width * scale).round()),
      math.max(1, (height * scale).round()),
    );
  }

  @override
  String toString() => '${width}x$height';
}

/// 默认长边上限（[推断]：聊天附件预览/导出用，越大越慢）。
const int kDefaultMaxImageEdge = 1600;

/// 默认压缩质量（0..100；PNG 无质量参数，仅作为 API 兼容/未来格式预留）。
const int kDefaultImageQuality = 85;

/// 附件图片的目标字节数（超过则继续缩小）。
const int kDefaultMaxImageBytes = 2 * 1024 * 1024;

/// 读取图片文件尺寸（不支持/损坏时抛 [ImageUtilException]）。
Future<ImageSize> imageSizeOf(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw ImageUtilException('文件不见了：$path');
  }
  final bytes = await _readHead(file, 256 * 1024);
  return decodeImageSizeAsync(bytes);
}

/// 从完整字节读取尺寸（带 `dart:ui` 解码兜底）。
Future<ImageSize> decodeImageSizeAsync(List<int> bytes) async {
  final data = Uint8List.fromList(bytes);
  try {
    return decodeImageSize(data);
  } on ImageUtilException {
    // 头解析不认识时交给 dart:ui（HEIC 等平台解码器）。
    final image = await decodeResize(data);
    try {
      return ImageSize(image.width, image.height);
    } finally {
      image.dispose();
    }
  }
}

/// 同步解析常见图片头（PNG/JPEG/GIF/WebP/BMP）；不认识时抛异常。
ImageSize decodeImageSize(Uint8List bytes) {
  if (bytes.length < 12) {
    throw const ImageUtilException('图片数据不完整');
  }

  // PNG: 89 50 4E 47 0D 0A 1A 0A，IHDR 在 16/20。
  if (bytes.length >= 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return ImageSize(_u32be(bytes, 16), _u32be(bytes, 20));
  }

  // GIF: GIF87a / GIF89a。
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return ImageSize(_u16le(bytes, 6), _u16le(bytes, 8));
  }

  // BMP。
  if (bytes[0] == 0x42 && bytes[1] == 0x4D && bytes.length >= 26) {
    final width = _i32le(bytes, 18).abs();
    final height = _i32le(bytes, 22).abs();
    return ImageSize(width, height);
  }

  // JPEG: 扫描 SOF 段。
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
    var i = 2;
    while (i + 9 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      var marker = bytes[i + 1];
      // 填充 0xFF。
      while (marker == 0xFF && i + 2 < bytes.length) {
        i++;
        marker = bytes[i + 1];
      }
      // SOF0..SOF15，排除 DHT(0xC4)/JPG(0xC8)/DAC(0xCC)。
      if (marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC) {
        final height = _u16be(bytes, i + 5);
        final width = _u16be(bytes, i + 7);
        if (width > 0 && height > 0) return ImageSize(width, height);
        break;
      }
      // 无长度的独立标记。
      if (marker == 0xD8 || marker == 0xD9 || (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      final length = _u16be(bytes, i + 2);
      if (length < 2) break;
      i += 2 + length;
    }
    throw const ImageUtilException('无法解析 JPEG 尺寸');
  }

  // WebP。
  if (bytes.length >= 30 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    final fourcc = String.fromCharCodes(bytes.sublist(12, 16));
    if (fourcc == 'VP8X' && bytes.length >= 30) {
      final width = _u24le(bytes, 24) + 1;
      final height = _u24le(bytes, 27) + 1;
      return ImageSize(width, height);
    }
    if (fourcc == 'VP8 ' && bytes.length >= 30) {
      final width = _u16le(bytes, 26) & 0x3FFF;
      final height = _u16le(bytes, 28) & 0x3FFF;
      return ImageSize(width, height);
    }
    if (fourcc == 'VP8L' && bytes.length >= 25) {
      final b1 = bytes[21];
      final b2 = bytes[22];
      final b3 = bytes[23];
      final b4 = bytes[24];
      final width = 1 + (((b2 & 0x3F) << 8) | b1);
      final height = 1 + (((b4 & 0x0F) << 10) | (b3 << 2) | ((b2 & 0xC0) >> 6));
      return ImageSize(width, height);
    }
  }

  throw const ImageUtilException('无法解析图片尺寸');
}

/// `dart:ui` 解码（可按目标尺寸降采样）。
Future<ui.Image> decodeResize(
  List<int> bytes, {
  int? width,
  int? height,
}) async {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(
      data,
      targetWidth: width,
      targetHeight: height,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  } on ImageUtilException {
    rethrow;
  } catch (error) {
    throw ImageUtilException('无法解析图片', cause: error);
  } finally {
    codec?.dispose();
  }
}

/// 按指定像素尺寸重新编码 PNG（不进行裁剪，调用方保证是等比尺寸）。
Future<Uint8List> shrinkImage(
  List<int> bytes, {
  required int width,
  required int height,
  int quality = kDefaultImageQuality,
}) async {
  final image = await decodeResize(bytes, width: width, height: height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw const ImageUtilException('图片编码失败');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// 压缩图片：限制长边，必要时（给了 [targetBytes]）逐级缩小到目标体积。
///
/// 返回 PNG 字节；`null` 表示无需压缩/压缩失败（调用方可直接用原图）。
Future<Uint8List?> compressImage(
  List<int> bytes, {
  int maxEdge = kDefaultMaxImageEdge,
  int quality = kDefaultImageQuality,
  int? targetBytes,
  int minEdge = 320,
}) async {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  ImageSize size;
  try {
    size = decodeImageSize(data);
  } on ImageUtilException {
    final image = await decodeResize(data);
    size = ImageSize(image.width, image.height);
    image.dispose();
  }
  if (!size.isValid) return null;

  var target = TargetImageSize.contain(size.width, size.height, maxEdge: maxEdge);
  final goal = targetBytes ?? 0;

  Uint8List? best;
  while (true) {
    final encoded = await shrinkImage(
      data,
      width: target.width,
      height: target.height,
      quality: quality,
    );
    best = encoded;
    if (goal <= 0 || encoded.length <= goal) break;
    if (target.longEdge <= minEdge) break;
    final nextEdge = math.max(minEdge, (target.longEdge * 0.85).round());
    if (nextEdge >= target.longEdge) break;
    target = TargetImageSize.contain(
      target.width,
      target.height,
      maxEdge: nextEdge,
    );
  }
  return best;
}

/// 压缩本地图片文件；返回新字节（PNG）。
Future<Uint8List?> compressImageFile(
  String path, {
  int maxEdge = kDefaultMaxImageEdge,
  int quality = kDefaultImageQuality,
  int? targetBytes = kDefaultMaxImageBytes,
  int minEdge = 320,
}) async {
  final file = File(path);
  if (!await file.exists()) {
    throw ImageUtilException('文件不见了：$path');
  }
  final bytes = await file.readAsBytes();
  return compressImage(
    bytes,
    maxEdge: maxEdge,
    quality: quality,
    targetBytes: targetBytes,
    minEdge: minEdge,
  );
}

/// 读取文件头 [maxBytes] 字节（用于解析图片尺寸）。
Future<Uint8List> _readHead(File file, int maxBytes) async {
  final length = await file.length();
  if (length <= 0) {
    throw ImageUtilException('图片为空：${file.path}');
  }
  final read = math.min(length, maxBytes);
  final bytes = Uint8List(read);
  final handle = await file.open();
  try {
    var offset = 0;
    while (offset < read) {
      final chunk = await handle.read(read - offset);
      if (chunk.isEmpty) break;
      bytes.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    if (offset < read) {
      return Uint8List.sublistView(bytes, 0, offset);
    }
    return bytes;
  } finally {
    await handle.close();
  }
}

int _u16be(Uint8List b, int o) => (b[o] << 8) | b[o + 1];

int _u16le(Uint8List b, int o) => (b[o + 1] << 8) | b[o];

int _u32be(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

int _i32le(Uint8List b, int o) {
  final value = b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
  return value;
}

int _u24le(Uint8List b, int o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);
