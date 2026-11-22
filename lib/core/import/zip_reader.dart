/// Keepsake（留声）— 自研流式 ZIP 读取器。
///
/// 用途：导入 DeepSeek 官方导出包（实测 188 MB / 3457 会话 / 98036 消息 /
/// 422 张图片）。**不能**把整包 `readAsBytes` 进内存，因此这里直接基于
/// `dart:io` 的 [RandomAccessFile] 随机读：
///
/// 1. 从文件尾部找 EOCD（`_findEocd`），解析中央目录（只读目录，不读数据）；
/// 2. 条目按需读取：小文件（`chat_session_index.json` / 每会话 JSON）整段解压，
///    大文件（图片）走 [openRead] 流式解压 + CRC 校验，可边解压边写盘；
/// 3. 支持 STORE(0) / DEFLATE(8)；**不支持 ZIP64 / 分卷 / 加密 ZIP**。
///    错误文案照 `reports/apk/ui-strings.txt` §9（如「找不到 ZIP 结尾目录（EOCD）」
///    「暂不支持 ZIP64 条目：」「不支持的压缩方式 」），可直接展示给用户。
///
/// 私有成员命名照逆向符号：`StreamingZipReader` / `_findEocd` / `_inflate` /
/// `_u16` / `_u32`（library `@1148090126`，`core/import/zip_reader.dart`）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// ZIP 解析失败（可展示的中文文案）。
class ZipFormatException implements Exception {
  ZipFormatException(this.message, {this.entryPath});

  /// 可直接展示给用户的中文错误文案。
  final String message;

  /// 出问题的条目（可空）。
  final String? entryPath;

  @override
  String toString() => entryPath == null ? message : '$message（$entryPath）';
}

/// 中央目录里的一个条目（不持有数据，按需读取）。
class ZipEntry {
  const ZipEntry({
    required this.path,
    required this.flags,
    required this.method,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
  });

  /// 包内路径（已把 `\` 归一化成 `/`）。
  final String path;

  /// 通用位标记（bit 0 加密、bit 3 data descriptor、bit 11 UTF-8 文件名）。
  final int flags;

  /// 压缩方式：0 = STORE，8 = DEFLATE。
  final int method;

  /// 未压缩数据的 CRC32。
  final int crc32;

  /// 压缩后大小。
  final int compressedSize;

  /// 原始大小。
  final int uncompressedSize;

  /// 本地头在文件中的偏移（尚未加前置数据 delta）。
  final int localHeaderOffset;

  /// 目录条目（路径以 `/` 结尾）。
  bool get isDirectory => path.endsWith('/');

  /// 是否 STORE。
  bool get isStored => method == 0;

  /// 是否 DEFLATE。
  bool get isDeflated => method == 8;

  /// 是否加密（不支持）。
  bool get isEncrypted => (flags & 0x1) != 0;

  /// 路径最后一段文件名。
  String get name {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  @override
  String toString() => 'ZipEntry($path, method=$method, $uncompressedSize bytes)';
}

/// 流式 ZIP 读取器。用 [StreamingZipReader.open] / [openFile] 打开，用完 [close]。
class StreamingZipReader {
  StreamingZipReader._(
    this._file,
    this._size,
    this._entries,
    this._byPath,
    this._prefixDelta,
  );

  final RandomAccessFile _file;
  final int _size;
  final List<ZipEntry> _entries;
  final Map<String, ZipEntry> _byPath;

  /// 前置数据长度（自解压头等非常规 ZIP 中央目录偏移修正；正常包为 0）。
  final int _prefixDelta;

  bool _closed = false;
  Future<void> _ioLock = Future<void>.value();

  int _cacheStart = 0;
  Uint8List? _cache;

  /// 读小块时的预读大小（顺序访问中央目录/本地头很快）。
  static const int _cacheSize = 1024 * 1024;

  /// 流式解压每次从文件读的压缩块大小。
  static const int _chunkSize = 256 * 1024;

  /// 单个条目允许的最大未压缩大小（防 zip 炸弹 / 误读 188MB 单文件）。
  static const int defaultMaxEntryBytes = 512 * 1024 * 1024;

  /// 中央目录最大解析大小。
  static const int _maxCentralDirectory = 256 * 1024 * 1024;

  /// 全部条目（含目录条目）。
  List<ZipEntry> get entries => List<ZipEntry>.unmodifiable(_entries);

  /// 非目录文件条目数。
  int get fileCount => _entries.where((ZipEntry e) => !e.isDirectory).length;

  /// ZIP 文件总大小（字节）。
  int get size => _size;

  /// 按包内路径查条目（路径用 `/` 分隔；不存在返回 null）。
  ZipEntry? entry(String path) => _byPath[path];

  /// 路径是否存在。
  bool contains(String path) => _byPath.containsKey(path);

  /// 打开一个 ZIP 文件。
  static Future<StreamingZipReader> open(String path) =>
      openFile(File(path));

  /// 打开一个 ZIP 文件。
  static Future<StreamingZipReader> openFile(File file) async {
    final raf = await file.open();
    try {
      final size = await raf.length();
      final reader = StreamingZipReader._(raf, size, const <ZipEntry>[],
          const <String, ZipEntry>{}, 0);
      final parsed = await _parse(reader);
      return parsed;
    } catch (_) {
      await raf.close();
      rethrow;
    }
  }

  /// 解析 EOCD + 中央目录，构造读取器。
  static Future<StreamingZipReader> _parse(StreamingZipReader probe) async {
    final size = probe._size;
    if (size < 22) {
      throw ZipFormatException('找不到 ZIP 结尾目录（EOCD）');
    }

    final int eocdOffset = await _findEocd(probe);
    final Uint8List eocd = await probe._readAt(eocdOffset, 22);

    final int disk = _u16(eocd, 4);
    final int cdDisk = _u16(eocd, 6);
    final int countDisk = _u16(eocd, 8);
    final int count = _u16(eocd, 10);
    final int cdSize = _u32(eocd, 12);
    final int cdOffset = _u32(eocd, 16);
    final int commentLen = _u16(eocd, 20);

    if (disk != 0 || cdDisk != 0 || countDisk != count) {
      throw ZipFormatException('不支持分卷 ZIP');
    }
    // ZIP64：EOCD 里用哨兵值 0xFFFF / 0xFFFFFFFF 表示「看 ZIP64 记录」。
    if (count == 0xFFFF ||
        cdSize == 0xFFFFFFFF ||
        cdOffset == 0xFFFFFFFF ||
        eocdOffset + 22 + commentLen > size) {
      if (count == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF) {
        throw ZipFormatException('暂不支持 ZIP64 条目：ZIP64 结尾目录');
      }
      throw ZipFormatException('中央目录越界');
    }
    if (count == 0) {
      // 空 ZIP：合法，直接返回空读取器。
      return StreamingZipReader._(
          probe._file, size, const <ZipEntry>[], const <String, ZipEntry>{}, 0);
    }
    if (cdSize < 0 || cdSize > _maxCentralDirectory) {
      throw ZipFormatException('中央目录越界');
    }

    // 正常 ZIP：cdOffset + cdSize == EOCD 偏移；前置数据时修正 delta。
    final int cdEnd = eocdOffset;
    final int delta = cdEnd - (cdOffset + cdSize);
    if (delta < 0) {
      throw ZipFormatException('中央目录越界');
    }
    final int cdStart = cdOffset + delta;

    final List<ZipEntry> entries = <ZipEntry>[];
    final Map<String, ZipEntry> byPath = <String, ZipEntry>{};

    int cursor = 0;
    while (cursor < cdSize) {
      if (cursor + 46 > cdSize) {
        throw ZipFormatException('中央目录越界');
      }
      final Uint8List header = await probe._read(cdStart + cursor, 46);
      if (_u32(header, 0) != _centralSignature) {
        throw ZipFormatException('中央目录签名错误 @${cdStart + cursor}');
      }
      final int flags = _u16(header, 8);
      final int method = _u16(header, 10);
      final int crc = _u32(header, 16);
      final int compressedSize = _u32(header, 20);
      final int uncompressedSize = _u32(header, 24);
      final int nameLen = _u16(header, 28);
      final int extraLen = _u16(header, 30);
      final int cmtLen = _u16(header, 32);
      final int localOffset = _u32(header, 42);

      final int recordLen = 46 + nameLen + extraLen + cmtLen;
      if (cursor + recordLen > cdSize) {
        throw ZipFormatException('文件名越界');
      }
      final Uint8List tail =
          await probe._read(cdStart + cursor + 46, nameLen + extraLen + cmtLen);
      final Uint8List nameBytes = Uint8List.sublistView(tail, 0, nameLen);
      final Uint8List extra =
          Uint8List.sublistView(tail, nameLen, nameLen + extraLen);
      final String rawName = _decodeName(nameBytes, (flags & 0x800) != 0);
      final String path = rawName.replaceAll('\\', '/');

      // ZIP64 条目：extra 字段 0x0001，或大小/偏移用 0xFFFFFFFF 哨兵。
      if (compressedSize == 0xFFFFFFFF ||
          uncompressedSize == 0xFFFFFFFF ||
          localOffset == 0xFFFFFFFF ||
          _hasZip64Extra(extra)) {
        throw ZipFormatException('暂不支持 ZIP64 条目：$path');
      }
      if ((flags & 0x1) != 0) {
        throw ZipFormatException('不支持加密的 ZIP 条目：$path');
      }
      if (method != 0 && method != 8) {
        throw ZipFormatException('不支持的压缩方式 $method', entryPath: path);
      }

      final ZipEntry entry = ZipEntry(
        path: path,
        flags: flags,
        method: method,
        crc32: crc,
        compressedSize: compressedSize,
        uncompressedSize: uncompressedSize,
        localHeaderOffset: localOffset,
      );

      cursor += recordLen;
      if (path.isEmpty) continue;
      entries.add(entry);
      if (!entry.isDirectory && !byPath.containsKey(path)) {
        byPath[path] = entry;
      }
    }

    return StreamingZipReader._(
        probe._file, size, entries, byPath, delta);
  }

  /// 找到一个条目的数据在文件中的绝对起始偏移（解析本地头）。
  Future<int> _dataStartOf(ZipEntry entry) async {
    final int localOffset = entry.localHeaderOffset + _prefixDelta;
    if (localOffset < 0 || localOffset + 30 > _size) {
      throw ZipFormatException('本地头签名错误：${entry.path}');
    }
    final Uint8List local = await _readAt(localOffset, 30);
    if (_u32(local, 0) != _localSignature) {
      throw ZipFormatException('本地头签名错误：${entry.path}');
    }
    final int nameLen = _u16(local, 26);
    final int extraLen = _u16(local, 28);
    final int dataStart = localOffset + 30 + nameLen + extraLen;
    if (dataStart + entry.compressedSize > _size) {
      throw ZipFormatException('文件太大：${entry.path}');
    }
    return dataStart;
  }

  /// 流式读取一个条目的**未压缩**数据（DEFLATE 边读边解），并校验 CRC/长度。
  ///
  /// 大文件（图片）请用这个，配 `IOSink` 或 `File.openWrite()` 直接落盘，
  /// 不会把整条数据留在内存里。
  Stream<List<int>> openRead(ZipEntry entry, {bool verifyChecksum = true}) async* {
    _ensureOpen();
    final int dataStart = await _dataStartOf(entry);
    final _Crc32 crc = _Crc32();
    int produced = 0;

    if (entry.method == 0) {
      int offset = 0;
      while (offset < entry.compressedSize) {
        final int n = math.min(_chunkSize, entry.compressedSize - offset);
        final Uint8List chunk = await _readAt(dataStart + offset, n);
        offset += n;
        produced += chunk.length;
        crc.add(chunk);
        yield chunk;
      }
    } else if (entry.method == 8) {
      await for (final List<int> chunk in _inflate(entry, dataStart)) {
        produced += chunk.length;
        crc.add(chunk);
        yield chunk;
      }
    } else {
      throw ZipFormatException('不支持的压缩方式 ${entry.method}',
          entryPath: entry.path);
    }

    if (verifyChecksum) {
      if (entry.uncompressedSize >= 0 &&
          produced != entry.uncompressedSize) {
        throw ZipFormatException('解压长度不符：${entry.path}');
      }
      if (crc.value != entry.crc32) {
        throw ZipFormatException('CRC 校验失败：${entry.path}');
      }
    }
  }

  /// 整段读取一个条目（小文件：JSON / 索引）。默认上限 [defaultMaxEntryBytes]。
  Future<Uint8List> readBytes(ZipEntry entry, {int? maxBytes}) async {
    final int limit = maxBytes ?? defaultMaxEntryBytes;
    if (entry.uncompressedSize > limit) {
      throw ZipFormatException('文件太大：${entry.path}',
          entryPath: entry.path);
    }
    final BytesBuilder builder = BytesBuilder(copy: false);
    await for (final List<int> chunk in openRead(entry)) {
      builder.add(chunk);
      if (builder.length > limit) {
        throw ZipFormatException('文件太大：${entry.path}',
            entryPath: entry.path);
      }
    }
    return builder.takeBytes();
  }

  /// 整段读成 UTF-8 文本。
  Future<String> readString(ZipEntry entry, {int? maxBytes}) async {
    final Uint8List bytes = await readBytes(entry, maxBytes: maxBytes);
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 整段读取并 JSON 解析（对象/数组，视包内文件而定）。
  Future<Object?> readJson(ZipEntry entry, {int? maxBytes}) async {
    final String text = await readString(entry, maxBytes: maxBytes);
    try {
      return jsonDecode(text);
    } on FormatException catch (error) {
      throw ZipFormatException('JSON 解析失败：${entry.path}（${error.message}）',
          entryPath: entry.path);
    }
  }

  /// 流式解压到文件（大图片用），返回写入字节数。
  Future<int> extractTo(ZipEntry entry, File target) async {
    final Directory parent = target.parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }
    final IOSink sink = target.openWrite();
    int written = 0;
    try {
      await for (final List<int> chunk in openRead(entry)) {
        sink.add(chunk);
        written += chunk.length;
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return written;
  }

  /// 流式解压到指定路径（大图片用），返回写入字节数。
  Future<int> extractToPath(ZipEntry entry, String path) =>
      extractTo(entry, File(path));

  /// 关闭底层文件。可重复调用。
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _ioLock;
    await _file.close();
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('ZIP 已关闭');
    }
  }

  /// 串行化底层文件读写（RandomAccessFile 位置是共享状态）。
  Future<T> _locked<T>(Future<T> Function() action) {
    final Completer<T> completer = Completer<T>();
    _ioLock = _ioLock.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// 从文件绝对偏移精确读取 [length] 字节（不缓存）。
  Future<Uint8List> _readAt(int offset, int length) {
    _ensureOpen();
    if (offset < 0 || length < 0 || offset + length > _size) {
      throw ZipFormatException('读取越界');
    }
    return _locked<Uint8List>(() async {
      await _file.setPosition(offset);
      final Uint8List buffer = Uint8List(length);
      int read = 0;
      while (read < length) {
        final int n = await _file.readInto(buffer, read, length);
        if (n <= 0) {
          throw ZipFormatException('读取不完整');
        }
        read += n;
      }
      return buffer;
    });
  }

  /// 带 1MB 预读缓存的读取（中央目录 / 本地头这类小读）。
  Future<Uint8List> _read(int offset, int length) async {
    if (length <= 0) return Uint8List(0);
    final Uint8List? cache = _cache;
    if (cache != null &&
        offset >= _cacheStart &&
        offset + length <= _cacheStart + cache.length) {
      return Uint8List.sublistView(
          cache, offset - _cacheStart, offset - _cacheStart + length);
    }
    final int end = math.min(_size, offset + math.max(length, _cacheSize));
    final Uint8List data = await _readAt(offset, end - offset);
    if (data.length >= length) {
      _cache = data;
      _cacheStart = offset;
      return Uint8List.sublistView(data, 0, length);
    }
    return data;
  }

  /// DEFLATE 流式解压（ZIP method 8 = 无 zlib 头的 raw deflate）。
  Stream<List<int>> _inflate(ZipEntry entry, int dataStart) {
    final StreamController<List<int>> controller = StreamController<List<int>>();
    Future<void> feed() async {
      try {
        final ByteConversionSink inflater =
            ZLibDecoder(raw: true).startChunkedConversion(_ForwardSink(
          controller.add,
          () {
            if (!controller.isClosed) {
              unawaited(controller.close());
            }
          },
        ));
        int offset = 0;
        while (offset < entry.compressedSize) {
          final int n = math.min(_chunkSize, entry.compressedSize - offset);
          final Uint8List chunk = await _readAt(dataStart + offset, n);
          offset += n;
          inflater.add(chunk);
        }
        inflater.close();
      } catch (error, stack) {
        if (!controller.isClosed) {
          controller.addError(error, stack);
          await controller.close();
        }
      }
    }

    unawaited(feed());
    return controller.stream;
  }
}

// ---------------------------------------------------------------------------
// 私有工具（符号命名照逆向：_findEocd / _u16 / _u32）
// ---------------------------------------------------------------------------

const int _centralSignature = 0x02014b50;
const int _localSignature = 0x04034b50;
const int _eocdSignature = 0x06054b50;
const int _zip64ExtraId = 0x0001;

/// 从文件尾部（最多 22 + 65535 字节）倒着找 EOCD 签名。
///
/// 找到返回 EOCD 的绝对偏移；找不到抛「找不到 ZIP 结尾目录（EOCD）」。
Future<int> _findEocd(StreamingZipReader reader) async {
  final int size = reader._size;
  final int tailLen = math.min(size, 22 + 0xFFFF);
  final int tailStart = size - tailLen;
  final Uint8List tail = await reader._readAt(tailStart, tailLen);

  int fallback = -1;
  for (int i = tail.length - 22; i >= 0; i--) {
    if (_u32(tail, i) != _eocdSignature) continue;
    final int commentLen = _u16(tail, i + 20);
    if (i + 22 + commentLen == tail.length) {
      return tailStart + i;
    }
    if (commentLen <= tail.length - i - 22) {
      // 允许文件尾部有额外填充，记下来作兜底。
      if (fallback < 0) fallback = tailStart + i;
    }
  }
  if (fallback >= 0) return fallback;
  throw ZipFormatException('找不到 ZIP 结尾目录（EOCD）');
}

bool _hasZip64Extra(Uint8List extra) {
  int offset = 0;
  while (offset + 4 <= extra.length) {
    final int id = _u16(extra, offset);
    final int size = _u16(extra, offset + 2);
    if (id == _zip64ExtraId) return true;
    offset += 4 + size;
  }
  return false;
}

String _decodeName(Uint8List bytes, bool utf8Flag) {
  if (utf8Flag) {
    return utf8.decode(bytes, allowMalformed: true);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // 非 UTF-8 文件名的 ZIP（CP437）；DeepSeek 导出包都是 UTF-8，兜底即可。
    return latin1.decode(bytes);
  }
}

int _u16(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _u32(Uint8List bytes, int offset) =>
    (bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24)) &
    0xFFFFFFFF;

/// 增量 CRC32（ZIP 用的 IEEE 802.3 多项式）。
class _Crc32 {
  static final Uint32List _table = _makeTable();

  int _value = 0xFFFFFFFF;

  static Uint32List _makeTable() {
    final Uint32List table = Uint32List(256);
    for (int i = 0; i < 256; i++) {
      int c = i;
      for (int k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
      }
      table[i] = c;
    }
    return table;
  }

  void add(List<int> data) {
    int value = _value;
    for (int i = 0; i < data.length; i++) {
      value = _table[(value ^ data[i]) & 0xFF] ^ (value >>> 8);
    }
    _value = value;
  }

  int get value => (_value ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// 把解压输出转发给 [StreamController]（`Sink<List<int>>` 适配）。
class _ForwardSink implements Sink<List<int>> {
  _ForwardSink(this._onData, this._onDone);

  final void Function(List<int> data) _onData;
  final void Function() _onDone;

  @override
  void add(List<int> data) => _onData(data);

  @override
  void close() => _onDone();
}
