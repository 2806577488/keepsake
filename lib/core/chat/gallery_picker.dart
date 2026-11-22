import 'package:flutter/services.dart';

/// 直接用系统图库选图（原生通道 `keepsake/gallery`）。
///
/// 为什么不用 `image_picker`：华为等没有 AOSP Photo Picker 的设备上，
/// `image_picker` 检测不到系统选择器就会回退到文件管理器（DocumentsUI 的
/// 「最近」界面）。原生侧先发 `ACTION_PICK_IMAGES`（Android 13+ 系统图库、
/// 可多选），解析不到再退 `ACTION_PICK`（老式相册选择，直接打开厂商图库），
/// 两条路径都能打开「图库」而不是文件列表。
///
/// 返回的是原生复制到 `cacheDir/picked/` 的本地路径，可直接交给
/// `XFile` / 附件流程；用户取消时返回空列表。
class GalleryPicker {
  const GalleryPicker._();

  static const MethodChannel _channel = MethodChannel('keepsake/gallery');

  /// 打开系统图库选图，返回本地缓存路径列表。
  ///
  /// 失败时抛 [PlatformException]，错误码见 `MainActivity.pickImages`
  /// （`NO_GALLERY` / `BUSY`）。
  static Future<List<String>> pickImages() async {
    final List<Object?>? result =
        await _channel.invokeMethod<List<Object?>>('pickImages');
    if (result == null) return const <String>[];
    return result.whereType<String>().toList(growable: false);
  }
}
