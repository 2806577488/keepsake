/// Keepsake（留声）— 消息内容块（content blocks）。
///
/// 消息正文在 DB 的 `messages.content` 列里存的是 blocks JSON：
/// `[{"type":"text","text":"..."},{"type":"thinking","thinking":"..."}, ...]`。
/// 老数据可能是纯文本，[decodeBlocks] 会回退成单个 text 块。
///
/// 符号证据（`reports/apk/dart-symbols.md` §2、§4）：
/// `ChatBlock`、`ContentBlock`、`encodeBlocks`、`decodeBlocks`、`blocksToApi`、
/// `allBlocks`、`turnBlocks`、`_messageOf`；
/// block 类型字符串：`text` / `thinking` / `reasoning` / `web_search_result` /
/// `web_search_tool_result` / `web_fetch_result` / `web_fetch_tool_result` /
/// `image` / `file` / `mermaid`；工具名 `deepseek_web_search` / `deepseek_read_url`。
///
/// UI 文案（ui-strings.txt §2）：`思考过程`、`正在联网搜索`、`正在读取链接`、
/// `图片`、`附件`、`链接内容`。
library;

import 'dart:convert';

import 'attachments.dart';

export 'attachments.dart' show Attachment, AttachmentRules;

/// 内容块类型。`wire` 是写进 JSON 的原文类型字符串。
enum BlockType {
  text('text'),
  thinking('thinking'),
  webSearchResult('web_search_result'),
  webSearchToolResult('web_search_tool_result'),
  image('image'),
  file('file'),
  mermaid('mermaid'),
  code('code'),
  unknown('unknown');

  const BlockType(this.wire);

  /// JSON 里的 `type` 值。
  final String wire;

  /// 从 JSON 字符串解析（兼容旧类型名 `reasoning` 与 fetch 变体）。
  static BlockType parse(Object? raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    switch (value) {
      case 'text':
      case 'plaintext':
      case 'markdown':
        return BlockType.text;
      case 'thinking':
      case 'reasoning':
      case 'reasoning_content':
        return BlockType.thinking;
      case 'web_search_result':
      case 'web_fetch_result':
        return BlockType.webSearchResult;
      case 'web_search_tool_result':
      case 'web_fetch_tool_result':
        return BlockType.webSearchToolResult;
      case 'image':
      case 'image_url':
        return BlockType.image;
      case 'file':
      case 'attachment':
        return BlockType.file;
      case 'mermaid':
        return BlockType.mermaid;
      case 'code':
        return BlockType.code;
      default:
        return BlockType.unknown;
    }
  }

  /// UI 标签（ui-strings.txt 原文；text/unknown 无标签）。
  String get label {
    switch (this) {
      case BlockType.text:
      case BlockType.unknown:
        return '';
      case BlockType.thinking:
        return '思考过程';
      case BlockType.webSearchResult:
      case BlockType.webSearchToolResult:
        return '正在联网搜索';
      case BlockType.image:
        return '图片';
      case BlockType.file:
        return '附件';
      case BlockType.mermaid:
        return 'Mermaid';
      case BlockType.code:
        return '代码';
    }
  }

  bool get isSearch =>
      this == BlockType.webSearchResult || this == BlockType.webSearchToolResult;

  bool get isMedia => this == BlockType.image || this == BlockType.file;
}

/// 一个内容块。
///
/// 用扁平可选字段承载所有类型（JSON 也扁平存储），未知 key 收进 [extra]，
/// 这样导入/导出能无损往返。
class ContentBlock {
  const ContentBlock({
    required this.type,
    this.text,
    this.thinking,
    this.elapsedSeconds,
    this.url,
    this.title,
    this.snippet,
    this.siteName,
    this.publishedAt,
    this.path,
    this.fileName,
    this.mime,
    this.fileId,
    this.width,
    this.height,
    this.language,
    this.toolName,
    this.extra = const <String, Object?>{},
  });

  final BlockType type;

  /// 正文（text / code / mermaid 的内容；thinking 与 text 双写以兼容旧数据）。
  final String? text;

  /// 思考内容（thinking 块）。
  final String? thinking;

  /// 思考耗时（秒，UI「思考过程（1.2s）」）。
  final double? elapsedSeconds;

  /// 联网搜索结果 / 链接内容。
  final String? url;
  final String? title;
  final String? snippet;
  final String? siteName;
  final String? publishedAt;

  /// image / file 的本地路径。
  final String? path;

  /// image / file 的文件名。
  final String? fileName;

  /// MIME。
  final String? mime;

  /// Files API 服务端 id。
  final String? fileId;

  /// 图片宽度/高度。
  final int? width;
  final int? height;

  /// code 块语言（高亮用）。
  final String? language;

  /// 工具名（`deepseek_web_search` / `deepseek_read_url`）。
  final String? toolName;

  /// 未识别的 JSON 字段（导入导出无损保留）。
  final Map<String, Object?> extra;

  // ---------------------------------------------------------------------
  // 便捷构造
  // ---------------------------------------------------------------------

  factory ContentBlock.text(String text) =>
      ContentBlock(type: BlockType.text, text: text);

  factory ContentBlock.thinking(String thinking, {double? elapsedSeconds}) =>
      ContentBlock(
        type: BlockType.thinking,
        text: thinking,
        thinking: thinking,
        elapsedSeconds: elapsedSeconds,
      );

  /// 联网搜索结果；DeepSeek 原生 `web_search_tool_result` 用 `tool: true`。
  factory ContentBlock.searchResult({
    required String url,
    String? title,
    String? snippet,
    String? siteName,
    String? publishedAt,
    bool tool = false,
    String? toolName,
  }) =>
      ContentBlock(
        type: tool ? BlockType.webSearchToolResult : BlockType.webSearchResult,
        url: url,
        title: title,
        snippet: snippet,
        siteName: siteName,
        publishedAt: publishedAt,
        toolName: toolName ?? 'deepseek_web_search',
      );

  factory ContentBlock.image({
    required String path,
    String? fileName,
    String? mime,
    int? width,
    int? height,
    String? fileId,
  }) =>
      ContentBlock(
        type: BlockType.image,
        path: path,
        fileName: fileName,
        mime: mime,
        width: width,
        height: height,
        fileId: fileId,
      );

  factory ContentBlock.file({
    required String path,
    String? fileName,
    String? mime,
    String? fileId,
  }) =>
      ContentBlock(
        type: BlockType.file,
        path: path,
        fileName: fileName,
        mime: mime,
        fileId: fileId,
      );

  factory ContentBlock.mermaid(String code) =>
      ContentBlock(type: BlockType.mermaid, text: code);

  factory ContentBlock.code(String code, {String? language}) =>
      ContentBlock(type: BlockType.code, text: code, language: language);

  /// 由 [Attachment] 生成 image/file 块。
  factory ContentBlock.fromAttachment(Attachment attachment) {
    if (attachment.isImage) {
      return ContentBlock.image(
        path: attachment.path,
        fileName: attachment.fileName,
        mime: attachment.mime,
        width: attachment.width,
        height: attachment.height,
        fileId: attachment.fileId,
      );
    }
    return ContentBlock.file(
      path: attachment.path,
      fileName: attachment.fileName,
      mime: attachment.mime,
      fileId: attachment.fileId,
    );
  }

  factory ContentBlock.fromJson(Map<String, Object?> json) {
    final extra = <String, Object?>{};
    for (final entry in json.entries) {
      if (!_knownKeys.contains(entry.key)) extra[entry.key] = entry.value;
    }
    final type = BlockType.parse(json['type']);
    final text = _strOf(json['text']) ??
        _strOf(json['content']) ??
        _strOf(json['plaintext']) ??
        _strOf(json['markdown']);
    final thinking = _strOf(json['thinking']) ??
        _strOf(json['reasoning']) ??
        _strOf(json['reasoning_content']);
    return ContentBlock(
      type: type,
      text: text,
      thinking: thinking,
      elapsedSeconds: _doubleOf(json['elapsedSeconds'] ?? json['elapsed_seconds']),
      url: _strOf(json['url']),
      title: _strOf(json['title']),
      snippet: _strOf(json['snippet']),
      siteName:
          _strOf(json['siteName']) ?? _strOf(json['site_name']) ?? _strOf(json['site']),
      publishedAt: _strOf(json['publishedAt']) ??
          _strOf(json['published_at']) ??
          _strOf(json['date']),
      path: _strOf(json['path']) ?? _strOf(json['local_path']),
      fileName: _strOf(json['fileName']) ?? _strOf(json['file_name']),
      mime: _strOf(json['mime']) ?? _strOf(json['content_type']),
      fileId: _strOf(json['fileId']) ?? _strOf(json['file_id']),
      width: _intOf(json['width']),
      height: _intOf(json['height']),
      language: _strOf(json['language']) ?? _strOf(json['lang']),
      toolName: _strOf(json['toolName']) ??
          _strOf(json['tool_name']) ??
          _strOf(json['tool']),
      extra: extra,
    );
  }

  static const Set<String> _knownKeys = <String>{
    'type',
    'text',
    'content',
    'plaintext',
    'markdown',
    'thinking',
    'reasoning',
    'reasoning_content',
    'elapsedSeconds',
    'elapsed_seconds',
    'url',
    'title',
    'snippet',
    'siteName',
    'site_name',
    'site',
    'publishedAt',
    'published_at',
    'date',
    'path',
    'local_path',
    'fileName',
    'file_name',
    'mime',
    'content_type',
    'fileId',
    'file_id',
    'width',
    'height',
    'language',
    'lang',
    'toolName',
    'tool_name',
    'tool',
  };

  /// JSON 形状（stored in `messages.content`）。
  Map<String, Object?> toJson() {
    final map = <String, Object?>{'type': type.wire};
    final body = text ?? thinking;
    if (body != null && body.isNotEmpty) map['text'] = body;
    if (thinking != null && thinking!.isNotEmpty) {
      map['thinking'] = thinking;
      if (body == null || body.isEmpty) map['text'] = thinking;
    }
    if (elapsedSeconds != null && elapsedSeconds! > 0) {
      map['elapsedSeconds'] = elapsedSeconds;
    }
    if (url != null && url!.isNotEmpty) map['url'] = url;
    if (title != null && title!.isNotEmpty) map['title'] = title;
    if (snippet != null && snippet!.isNotEmpty) map['snippet'] = snippet;
    if (siteName != null && siteName!.isNotEmpty) map['siteName'] = siteName;
    if (publishedAt != null && publishedAt!.isNotEmpty) {
      map['publishedAt'] = publishedAt;
    }
    if (path != null && path!.isNotEmpty) map['path'] = path;
    if (fileName != null && fileName!.isNotEmpty) map['fileName'] = fileName;
    if (mime != null && mime!.isNotEmpty) map['mime'] = mime;
    if (fileId != null && fileId!.isNotEmpty) map['fileId'] = fileId;
    if (width != null && width! > 0) map['width'] = width;
    if (height != null && height! > 0) map['height'] = height;
    if (language != null && language!.isNotEmpty) map['language'] = language;
    if (toolName != null && toolName!.isNotEmpty) map['toolName'] = toolName;
    if (extra.isNotEmpty) map.addAll(extra);
    return map;
  }

  /// 纯文本正文（text / thinking / code / mermaid）。
  String get plainText => (text ?? thinking ?? '').trim();

  bool get isEmpty => plainText.isEmpty && (url ?? '').isEmpty && (path ?? '').isEmpty;

  bool get isNotEmpty => !isEmpty;

  bool get isSearch => type.isSearch;

  bool get isMedia => type.isMedia;

  /// 展示用标题：文件名 > 搜索标题 > 域名 > 类型标签。
  String get displayName {
    if ((fileName ?? '').isNotEmpty) return fileName!;
    if ((title ?? '').isNotEmpty) return title!;
    final link = url ?? '';
    if (link.isNotEmpty) {
      final host = Uri.tryParse(link)?.host ?? '';
      if (host.isNotEmpty) return host;
      return link;
    }
    return type.label;
  }

  /// 区块标签：联网搜索/读取链接会按工具名细分（ui-strings 原文）。
  String get label {
    if (type.isSearch) {
      if (toolName == 'deepseek_read_url') return '正在读取链接';
      return '正在联网搜索';
    }
    return type.label;
  }

  ContentBlock copyWith({
    BlockType? type,
    String? text,
    String? thinking,
    double? elapsedSeconds,
    String? url,
    String? title,
    String? snippet,
    String? siteName,
    String? publishedAt,
    String? path,
    String? fileName,
    String? mime,
    String? fileId,
    int? width,
    int? height,
    String? language,
    String? toolName,
    Map<String, Object?>? extra,
  }) =>
      ContentBlock(
        type: type ?? this.type,
        text: text ?? this.text,
        thinking: thinking ?? this.thinking,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        url: url ?? this.url,
        title: title ?? this.title,
        snippet: snippet ?? this.snippet,
        siteName: siteName ?? this.siteName,
        publishedAt: publishedAt ?? this.publishedAt,
        path: path ?? this.path,
        fileName: fileName ?? this.fileName,
        mime: mime ?? this.mime,
        fileId: fileId ?? this.fileId,
        width: width ?? this.width,
        height: height ?? this.height,
        language: language ?? this.language,
        toolName: toolName ?? this.toolName,
        extra: extra ?? this.extra,
      );

  @override
  String toString() => 'ContentBlock(${type.wire}, ${plainText.length} chars)';
}

/// `ChatBlock` 与 `ContentBlock` 是同一个类（符号表两个名字都存在）。
typedef ChatBlock = ContentBlock;

/// 把消息 blocks 编码成 DB 里存的 JSON 字符串。
String encodeBlocks(Iterable<ContentBlock> blocks) {
  final list = <Map<String, Object?>>[];
  for (final block in blocks) {
    if (block.type == BlockType.text && block.plainText.isEmpty) continue;
    if (block.isEmpty && block.type != BlockType.unknown) continue;
    list.add(block.toJson());
  }
  return jsonEncode(list);
}

/// 解码 `messages.content`。
///
/// 兼容：
/// - `null` / 空串 → `[]`
/// - 纯文本（旧数据）→ 单个 text 块
/// - `{"text": "..."}` 旧对象 → text 块
/// - `{"blocks": [...]}` / `{"content": [...]}` 包裹 → 块列表
/// - 块数组（含未知类型）→ 尽量保留内容
List<ContentBlock> decodeBlocks(String? content) {
  if (content == null) return const <ContentBlock>[];
  final trimmed = content.trim();
  if (trimmed.isEmpty) return const <ContentBlock>[];

  if (trimmed.startsWith('[')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        final blocks = <ContentBlock>[];
        for (final item in decoded) {
          if (item is Map) {
            blocks.add(ContentBlock.fromJson(Map<String, Object?>.from(item)));
          } else if (item is String && item.isNotEmpty) {
            blocks.add(ContentBlock.text(item));
          }
        }
        // 空数组表示「没有内容块」（不要把 '[]' 当正文）。
        return blocks;
      }
    } catch (_) {
      // 不是合法 JSON：按纯文本处理。
    }
    return <ContentBlock>[ContentBlock.text(content)];
  }

  if (trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final map = Map<String, Object?>.from(decoded);
        final wrapped = map['blocks'] ?? map['content'];
        if (wrapped is List) {
          return decodeBlocks(jsonEncode(wrapped));
        }
        return <ContentBlock>[ContentBlock.fromJson(map)];
      }
    } catch (_) {
      // 不是合法 JSON：按纯文本处理。
    }
    return <ContentBlock>[ContentBlock.text(content)];
  }

  return <ContentBlock>[ContentBlock.text(content)];
}

/// 历史消息正文 → 发往 API 的纯文本（thinking 默认不发送）。
String blocksToApi(
  Iterable<ContentBlock> blocks, {
  bool includeThinking = false,
  String separator = '\n\n',
}) {
  final parts = <String>[];
  for (final block in blocks) {
    switch (block.type) {
      case BlockType.text:
      case BlockType.code:
        if (block.plainText.isNotEmpty) parts.add(block.plainText);
      case BlockType.thinking:
        if (includeThinking && block.plainText.isNotEmpty) {
          parts.add(block.plainText);
        }
      case BlockType.mermaid:
        if (block.plainText.isNotEmpty) {
          parts.add('```mermaid\n${block.plainText}\n```');
        }
      case BlockType.webSearchResult:
      case BlockType.webSearchToolResult:
      case BlockType.image:
      case BlockType.file:
      case BlockType.unknown:
        break;
    }
  }
  return parts.join(separator);
}

/// 历史消息里的思考内容（assistant 轮的 `reasoning_content`）。
///
/// 官方「Thinking Mode › Tool Calls」要求：请求带 `tools` 时，历史轮次的
/// `reasoning_content` 必须完整回传，否则返回 400
/// （https://api-docs.deepseek.com/guides/thinking_mode#tool-calls）。
/// 这里直接复用落库的 `thinking` block，不新增存储字段。
String thinkingTextOf(Iterable<ContentBlock> blocks) {
  final parts = <String>[];
  for (final block in blocks) {
    if (block.type != BlockType.thinking) continue;
    if (block.plainText.isNotEmpty) parts.add(block.plainText);
  }
  return parts.join('\n\n').trim();
}

/// 消息正文的全部 blocks（= [decodeBlocks]，符号对齐用）。
List<ContentBlock> allBlocks(String? content) => _messageOf(content);

/// 渲染/导出用的「一轮」blocks：合并相邻 text、丢弃空块。
List<ContentBlock> turnBlocks(Iterable<ContentBlock> blocks) {
  final result = <ContentBlock>[];
  final buffer = StringBuffer();

  void flush() {
    final text = buffer.toString().trim();
    buffer.clear();
    if (text.isNotEmpty) result.add(ContentBlock.text(text));
  }

  for (final block in blocks) {
    if (block.type == BlockType.text) {
      buffer.write(block.plainText);
    } else {
      flush();
      if (block.isNotEmpty || block.type == BlockType.unknown) result.add(block);
    }
  }
  flush();
  return result;
}

/// 私有：把 DB 里的 content 变成 blocks（符号表 `_messageOf`）。
List<ContentBlock> _messageOf(String? content) => decodeBlocks(content);

String? _strOf(Object? value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  if (value is num || value is bool) return value.toString();
  return null;
}

int? _intOf(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed) ?? double.tryParse(trimmed)?.round();
  }
  return null;
}

double? _doubleOf(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}
