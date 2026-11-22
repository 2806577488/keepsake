// WAV（RIFF/WAVE）封装与解析工具。
//
// 语音链路只处理 PCM16 单声道 16kHz（record 插件用 AudioEncoder.wav 直接落盘，
// DeepSeek ASR 上传同一份 WAV），但解析器兼容更多 fmt 变体（8/24/32bit、立体声、
// WAVE_FORMAT_EXTENSIBLE、流式写入时 data size 为 0 / 0xFFFFFFFF 的文件）。
//
// 本文件不依赖 Flutter / 插件，纯 Dart，方便单测。错误统一抛 [WavFormatException]，
// 由上层（recorder / asr_client）转换成 VoiceError。

import 'dart:math' as math;
import 'dart:typed_data';

/// 推荐采样率：16kHz（ASR 常用）。
const int wavSampleRate16k = 16000;

/// 推荐声道数：单声道。
const int wavChannelsMono = 1;

/// 推荐位深：16bit。
const int wavBitsPerSample16 = 16;

/// 标准 PCM WAV 头长度（44 字节）。
const int wavPcmHeaderBytes = 44;

/// WAVE_FORMAT_PCM。
const int wavFormatPcm = 1;

/// WAVE_FORMAT_EXTENSIBLE。
const int wavFormatExtensible = 0xFFFE;

/// WAV 解析失败（数据截断、缺少 fmt/data 块等）。
class WavFormatException implements Exception {
  const WavFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 解析出来的 WAV 头信息。
class WavHeader {
  const WavHeader({
    required this.audioFormat,
    required this.numChannels,
    required this.sampleRate,
    required this.byteRate,
    required this.blockAlign,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataSize,
    required this.riffSize,
  });

  /// fmt 块里的 audio format tag（0xFFFE 已归一化为子格式 PCM=1）。
  final int audioFormat;

  /// 声道数（1=单声道）。
  final int numChannels;

  /// 采样率（Hz）。
  final int sampleRate;

  /// 每秒字节数。
  final int byteRate;

  /// 每帧字节数（channels * bitsPerSample / 8）。
  final int blockAlign;

  /// 位深。
  final int bitsPerSample;

  /// data 块负载在文件中的起始偏移。
  final int dataOffset;

  /// data 块负载长度（已按文件实际长度截断）。
  final int dataSize;

  /// RIFF 头里声明的文件长度（可能不可靠，仅保留）。
  final int riffSize;

  bool get isPcm => audioFormat == wavFormatPcm || audioFormat == wavFormatExtensible;

  bool get isPcm16 => isPcm && bitsPerSample == 16;

  bool get isMono => numChannels == 1;

  bool get is16k => sampleRate == 16000;

  /// ASR 期望的「PCM16 单声道 16kHz」。
  bool get isPcm16Mono16k => isPcm16 && isMono && is16k;

  /// 音频时长；byteRate 非法时为 [Duration.zero]。
  Duration get duration {
    if (byteRate <= 0 || dataSize <= 0) return Duration.zero;
    return Duration(
      microseconds: dataSize * Duration.microsecondsPerSecond ~/ byteRate,
    );
  }

  /// PCM 帧数。
  int get frameCount => blockAlign <= 0 ? 0 : dataSize ~/ blockAlign;

  /// data 块结束位置（不含尾部填充）。
  int get totalSize => dataOffset + dataSize;

  @override
  String toString() => 'WavHeader(format=$audioFormat, channels=$numChannels, '
      'rate=$sampleRate, bits=$bitsPerSample, data=$dataOffset+$dataSize)';
}

/// 判断字节流是否以 RIFF/WAVE 开头（不做完整校验）。
bool isWav(Uint8List bytes) {
  if (bytes.length < 12) return false;
  return _hasTag(bytes, 0, 'RIFF') && _hasTag(bytes, 8, 'WAVE');
}

/// 把 PCM 数据封装成 WAV。
///
/// [pcm] 为裸 PCM 采样字节（小端）。默认参数即「PCM16 单声道 16kHz」。
/// 数据长度为奇数时会补一个 0 填充字节（RIFF 要求 chunk 2 字节对齐）。
Uint8List encodeWav(
  Uint8List pcm, {
  int sampleRate = wavSampleRate16k,
  int numChannels = wavChannelsMono,
  int bitsPerSample = wavBitsPerSample16,
  int audioFormat = wavFormatPcm,
}) {
  if (sampleRate <= 0 || numChannels <= 0 || bitsPerSample <= 0) {
    throw ArgumentError('WAV 参数无效');
  }
  if (bitsPerSample % 8 != 0) {
    throw ArgumentError('WAV 位深必须是 8 的倍数');
  }
  final bytesPerSample = bitsPerSample ~/ 8;
  final blockAlign = numChannels * bytesPerSample;
  final byteRate = sampleRate * blockAlign;
  final dataSize = pcm.length;
  final padding = dataSize.isOdd ? 1 : 0;
  final fileSize = wavPcmHeaderBytes + dataSize + padding;
  final out = Uint8List(fileSize);
  final view = ByteData.sublistView(out);

  _writeTag(out, 0, 'RIFF');
  view.setUint32(4, fileSize - 8, Endian.little);
  _writeTag(out, 8, 'WAVE');

  _writeTag(out, 12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, audioFormat, Endian.little);
  view.setUint16(22, numChannels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, byteRate, Endian.little);
  view.setUint16(32, blockAlign, Endian.little);
  view.setUint16(34, bitsPerSample, Endian.little);

  _writeTag(out, 36, 'data');
  view.setUint32(40, dataSize, Endian.little);
  out.setRange(wavPcmHeaderBytes, wavPcmHeaderBytes + dataSize, pcm);
  return out;
}

/// [encodeWav] 的别名（APK 符号表里同时存在 `encodeWav` / `pcmToWav`）。
Uint8List pcmToWav(
  Uint8List pcm, {
  int sampleRate = wavSampleRate16k,
  int numChannels = wavChannelsMono,
  int bitsPerSample = wavBitsPerSample16,
}) {
  return encodeWav(
    pcm,
    sampleRate: sampleRate,
    numChannels: numChannels,
    bitsPerSample: bitsPerSample,
  );
}

/// 解析 WAV 头；失败抛 [WavFormatException]。
///
/// 兼容：
/// * fmt 块带扩展字节（cbSize）；
/// * fmt 之前有 LIST/JUNK 等附加 chunk；
/// * WAVE_FORMAT_EXTENSIBLE（取子格式，PCM 时归一化为 1）；
/// * data size 为 0 或 0xFFFFFFFF（流式写入尚未回填）→ 用文件剩余长度兜底。
WavHeader parseWavHeader(Uint8List bytes) {
  if (bytes.length < 12) {
    throw const WavFormatException('WAV 数据太短');
  }
  if (!isWav(bytes)) {
    throw const WavFormatException('不是有效的 WAV 文件');
  }
  final view = ByteData.sublistView(bytes);
  final riffSize = view.getUint32(4, Endian.little);

  var audioFormat = 0;
  var numChannels = 0;
  var sampleRate = 0;
  var byteRate = 0;
  var blockAlign = 0;
  var bitsPerSample = 0;
  var hasFormat = false;
  int? dataOffset;
  int? dataSize;

  final limit = bytes.length;
  var offset = 12;
  while (offset + 8 <= limit) {
    final id = String.fromCharCodes(bytes, offset, offset + 4);
    final size = view.getUint32(offset + 4, Endian.little);
    final payload = offset + 8;
    if (id == 'fmt ') {
      if (payload + 16 > limit) {
        throw const WavFormatException('WAV 的 fmt 块不完整');
      }
      final formatTag = view.getUint16(payload, Endian.little);
      numChannels = view.getUint16(payload + 2, Endian.little);
      sampleRate = view.getUint32(payload + 4, Endian.little);
      byteRate = view.getUint32(payload + 8, Endian.little);
      blockAlign = view.getUint16(payload + 12, Endian.little);
      bitsPerSample = view.getUint16(payload + 14, Endian.little);
      if (formatTag == wavFormatExtensible &&
          size >= 40 &&
          payload + 26 <= limit) {
        audioFormat = view.getUint16(payload + 24, Endian.little);
      } else {
        audioFormat = formatTag;
      }
      hasFormat = true;
    } else if (id == 'data') {
      final available = limit - payload;
      var declared = size;
      if (declared == 0 ||
          declared > available ||
          declared > 0x7FFFFFFF ||
          declared == 0xFFFFFFFF) {
        declared = available > 0 ? available : 0;
      }
      dataOffset = payload;
      dataSize = declared;
    }
    if (hasFormat && dataOffset != null) break;
    if (size > 0x7FFFFFFF) {
      throw const WavFormatException('WAV 块长度异常');
    }
    // chunk 2 字节对齐；size 为奇数时补 1 字节。
    offset = payload + size + (size.isOdd ? 1 : 0);
  }

  if (!hasFormat) {
    throw const WavFormatException('WAV 缺少 fmt 块');
  }
  if (dataOffset == null || dataSize == null) {
    throw const WavFormatException('WAV 缺少 data 块');
  }
  if (numChannels <= 0 || sampleRate <= 0 || bitsPerSample <= 0) {
    throw const WavFormatException('WAV 参数无效');
  }
  if (blockAlign <= 0) {
    blockAlign = numChannels * (bitsPerSample ~/ 8);
  }
  if (byteRate <= 0) {
    byteRate = sampleRate * blockAlign;
  }
  return WavHeader(
    audioFormat: audioFormat,
    numChannels: numChannels,
    sampleRate: sampleRate,
    byteRate: byteRate,
    blockAlign: blockAlign,
    bitsPerSample: bitsPerSample,
    dataOffset: dataOffset,
    dataSize: dataSize,
    riffSize: riffSize,
  );
}

/// 解析失败时返回 null，不抛异常。
WavHeader? tryParseWavHeader(Uint8List bytes) {
  try {
    return parseWavHeader(bytes);
  } on WavFormatException {
    return null;
  } on RangeError {
    return null;
  } on ArgumentError {
    return null;
  }
}

/// 取出 WAV 里的裸 PCM 数据（零拷贝视图）。
Uint8List wavPcmData(Uint8List bytes) {
  final header = parseWavHeader(bytes);
  return Uint8List.sublistView(
    bytes,
    header.dataOffset,
    header.dataOffset + header.dataSize,
  );
}

/// WAV 时长；解析失败时抛 [WavFormatException]。
Duration wavDurationOf(Uint8List bytes) => parseWavHeader(bytes).duration;

/// WAV 时长；解析失败时返回 [Duration.zero]。
Duration tryWavDurationOf(Uint8List bytes) {
  final header = tryParseWavHeader(bytes);
  return header?.duration ?? Duration.zero;
}

/// 把多段 WAV 拼成一段（取第一段头的参数；各段参数应一致）。
Uint8List concatWav(Iterable<Uint8List> parts) {
  final list = parts.toList(growable: false);
  if (list.isEmpty) return encodeWav(Uint8List(0));

  WavHeader? first;
  final payloads = <Uint8List>[];
  var total = 0;
  for (final part in list) {
    final header = parseWavHeader(part);
    first ??= header;
    final pcm = Uint8List.sublistView(
      part,
      header.dataOffset,
      header.dataOffset + header.dataSize,
    );
    payloads.add(pcm);
    total += pcm.length;
  }
  final merged = Uint8List(total);
  var offset = 0;
  for (final payload in payloads) {
    merged.setRange(offset, offset + payload.length, payload);
    offset += payload.length;
  }
  final header = first!;
  return encodeWav(
    merged,
    sampleRate: header.sampleRate,
    numChannels: header.numChannels,
    bitsPerSample: header.bitsPerSample,
    audioFormat: header.audioFormat,
  );
}

/// 裁剪 WAV（按帧对齐；[start] 默认 0，[end] 默认到结尾）。
Uint8List trimWav(
  Uint8List bytes, {
  Duration start = Duration.zero,
  Duration? end,
}) {
  final header = parseWavHeader(bytes);
  final frameSize = header.blockAlign > 0
      ? header.blockAlign
      : header.numChannels * (header.bitsPerSample ~/ 8);
  if (frameSize <= 0) {
    throw const WavFormatException('WAV 参数无效');
  }
  final totalFrames = header.dataSize ~/ frameSize;
  final startFrame = _clampInt(
    start.inMicroseconds * header.sampleRate ~/
        Duration.microsecondsPerSecond,
    0,
    totalFrames,
  );
  final rawEndFrame = end == null
      ? totalFrames
      : end.inMicroseconds * header.sampleRate ~/
          Duration.microsecondsPerSecond;
  final endFrame = _clampInt(rawEndFrame, startFrame, totalFrames);
  final offset = header.dataOffset + startFrame * frameSize;
  final length = (endFrame - startFrame) * frameSize;
  final pcm = Uint8List.sublistView(bytes, offset, offset + length);
  return encodeWav(
    pcm,
    sampleRate: header.sampleRate,
    numChannels: header.numChannels,
    bitsPerSample: header.bitsPerSample,
    audioFormat: header.audioFormat,
  );
}

/// PCM16 峰值振幅（0..1，满幅=1）。
double pcm16Peak(Uint8List pcm) {
  if (pcm.length < 2) return 0;
  final view = ByteData.sublistView(pcm);
  var peak = 0;
  for (var i = 0; i + 1 < pcm.length; i += 2) {
    final sample = view.getInt16(i, Endian.little);
    final magnitude = sample < 0 ? -sample : sample;
    if (magnitude > peak) peak = magnitude;
  }
  return peak / 32768.0;
}

/// PCM16 均方根振幅（0..1）。
double pcm16Rms(Uint8List pcm) {
  if (pcm.length < 2) return 0;
  final view = ByteData.sublistView(pcm);
  var sum = 0.0;
  var count = 0;
  for (var i = 0; i + 1 < pcm.length; i += 2) {
    final sample = view.getInt16(i, Endian.little) / 32768.0;
    sum += sample * sample;
    count++;
  }
  if (count == 0) return 0;
  return math.sqrt(sum / count);
}

/// WAV 峰值振幅（解析 data 块后计算）。
double wavPeak(Uint8List wav) => pcm16Peak(wavPcmData(wav));

/// WAV 里是否有声音（峰值 ≥ [threshold]，默认 0.01 ≈ -40dBFS）。
bool wavHasSound(Uint8List wav, {double threshold = 0.01}) {
  return wavPeak(wav) >= threshold;
}

int _clampInt(int value, int low, int high) {
  if (value < low) return low;
  if (value > high) return high;
  return value;
}

bool _hasTag(Uint8List bytes, int offset, String tag) {
  if (offset + tag.length > bytes.length) return false;
  for (var i = 0; i < tag.length; i++) {
    if (bytes[offset + i] != tag.codeUnitAt(i)) return false;
  }
  return true;
}

void _writeTag(Uint8List bytes, int offset, String tag) {
  for (var i = 0; i < tag.length; i++) {
    bytes[offset + i] = tag.codeUnitAt(i);
  }
}
