/// Keepsake（留声）— 后台导入任务与进度通知。
///
/// 设置页选中 DeepSeek 导出 ZIP 后由 UI 调 [ImportTaskNotifier.start]；
/// 会话列表顶部监听 `importProgressProvider` 显示进度（文案照
/// `ui-strings.txt` §1/§9：「正在准备导入…」「正在导入…」「已新增 N 个对话」…）。
///
/// 两阶段：
/// - **标题**：先按索引把会话标题写进库（列表里标题一条条出现，很快）；
/// - **正文**：自动按顺序补正文，用户点某条标题可调 [ImportTask.priority] 插队。
///
/// 失败会话记录在 [ImportTask.failedSessionIds]，可 [ImportTask.retryFailed] 重试。
/// provider 定义在本文件（foundation 的 `core/providers.dart` 不定义，避免撞名）：
/// - [importTaskProvider]：`Provider<ImportTaskNotifier>`
/// - [importProgressProvider]：`StreamProvider<ImportProgress>`，UI 直接 watch。
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keepsake/core/providers.dart';

import 'importer.dart';
import 'zip_reader.dart';

/// 导入阶段。
enum ImportPhase {
  /// 空闲（还没开始 / 已重置）。
  idle,

  /// 正在打开 ZIP、校验版本、读索引。
  preparing,

  /// 阶段 A：写标题。
  titles,

  /// 阶段 B：补正文。
  bodies,

  /// 完成。
  done,

  /// 用户取消。
  cancelled,

  /// 致命失败（无法识别 / 版本不对 / ZIP 损坏）。
  failed,
}

/// 导入进度（不可变，供 UI 监听）。
class ImportProgress {
  const ImportProgress({
    this.phase = ImportPhase.idle,
    this.totalSessions = 0,
    this.titlesWritten = 0,
    this.bodiesImported = 0,
    this.bodiesSkipped = 0,
    this.bodiesTotal = 0,
    this.bodiesDone = 0,
    this.failed = 0,
    this.addedMessages = 0,
    this.addedAttachments = 0,
    this.currentTitle,
    this.fatalError,
    this.running = false,
  });

  /// 空闲态。
  static const ImportProgress idle = ImportProgress();

  final ImportPhase phase;

  /// 导出包索引里的会话数。
  final int totalSessions;

  /// 本次新写入的标题数。
  final int titlesWritten;

  /// 本次补完正文的会话数（= 新增会话数）。
  final int bodiesImported;

  /// 本地已有正文、跳过的会话数。
  final int bodiesSkipped;

  /// 需要补正文的会话总数。
  final int bodiesTotal;

  /// 正文阶段已处理数（含失败）。
  final int bodiesDone;

  /// 失败会话数。
  final int failed;

  /// 本次写入的消息数。
  final int addedMessages;

  /// 本次写入的附件数。
  final int addedAttachments;

  /// 当前正在导入的会话标题。
  final String? currentTitle;

  /// 致命错误（中文）。
  final String? fatalError;

  final bool running;

  bool get isDone => phase == ImportPhase.done;

  bool get isCancelled => phase == ImportPhase.cancelled;

  bool get isFailed => phase == ImportPhase.failed;

  bool get hasFailures => failed > 0;

  bool get isActive =>
      phase == ImportPhase.preparing ||
      phase == ImportPhase.titles ||
      phase == ImportPhase.bodies;

  /// 正文阶段进度 0..1；标题 / 空闲阶段为 null。
  double? get fraction {
    if (bodiesTotal <= 0) return null;
    final double value = bodiesDone / bodiesTotal;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
  }

  /// 可直接显示的文案（会话列表顶部进度条）。
  String get label {
    switch (phase) {
      case ImportPhase.idle:
        return '';
      case ImportPhase.preparing:
        return '正在准备导入…';
      case ImportPhase.titles:
        return '正在导入…';
      case ImportPhase.bodies:
        if (bodiesTotal <= 0) return '正在导入…';
        return '正在导入 $bodiesDone / $bodiesTotal';
      case ImportPhase.done:
        if (bodiesImported > 0) return '已新增 $bodiesImported 个对话';
        return '文件中的对话本地都已存在，没有新增';
      case ImportPhase.cancelled:
        return '已取消导入';
      case ImportPhase.failed:
        return fatalError ?? '导入失败';
    }
  }

  ImportProgress copyWith({
    ImportPhase? phase,
    int? totalSessions,
    int? titlesWritten,
    int? bodiesImported,
    int? bodiesSkipped,
    int? bodiesTotal,
    int? bodiesDone,
    int? failed,
    int? addedMessages,
    int? addedAttachments,
    String? currentTitle,
    String? fatalError,
    bool? running,
  }) {
    return ImportProgress(
      phase: phase ?? this.phase,
      totalSessions: totalSessions ?? this.totalSessions,
      titlesWritten: titlesWritten ?? this.titlesWritten,
      bodiesImported: bodiesImported ?? this.bodiesImported,
      bodiesSkipped: bodiesSkipped ?? this.bodiesSkipped,
      bodiesTotal: bodiesTotal ?? this.bodiesTotal,
      bodiesDone: bodiesDone ?? this.bodiesDone,
      failed: failed ?? this.failed,
      addedMessages: addedMessages ?? this.addedMessages,
      addedAttachments: addedAttachments ?? this.addedAttachments,
      currentTitle: currentTitle ?? this.currentTitle,
      fatalError: fatalError ?? this.fatalError,
      running: running ?? this.running,
    );
  }
}

/// 导入任务（ChangeNotifier）：持有一个 ZIP 的完整导入生命周期。
class ImportTask extends ChangeNotifier {
  ImportTask(this.db, {this.attachmentsRoot});

  final AppDatabase db;

  /// 附件落盘根目录（默认 `getApplicationSupportDirectory()/chat_sessions`；
  /// 测试可注入临时目录）。
  final Directory? attachmentsRoot;

  ImportProgress _progress = ImportProgress.idle;

  /// 标题阶段刚结束、正文开始前的回调（UI 用它先按标题聚类建角色卡）。
  void Function()? onTitlesDone;
  ImportResult? _result;
  ImportSource? _source;
  File? _file;
  Future<ImportResult>? _running;
  bool _cancelRequested = false;
  bool _disposed = false;

  List<ImportPlanRow> _rows = <ImportPlanRow>[];
  final List<String> _priorityQueue = <String>[];
  final Set<String> _priorityIds = <String>{};
  final Map<String, String> _errors = <String, String>{};

  /// 还没导完的 ZIP 路径（SharedPreferences）。App 重启后据此续跑。
  static const String _kPendingZip = 'import_pending_zip';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> _rememberZip(File file) async {
    try {
      await (await _prefs).setString(_kPendingZip, file.path);
    } catch (_) {
      // 记不住不影响本次导入。
    }
  }

  Future<void> _forgetZip() async {
    try {
      await (await _prefs).remove(_kPendingZip);
    } catch (_) {
      // 同上。
    }
  }

  /// 上次没导完的 ZIP（文件还在才返回）。
  Future<File?> pendingZip() async {
    try {
      final String? path = (await _prefs).getString(_kPendingZip);
      if (path == null || path.isEmpty) return null;
      final File file = File(path);
      return await file.exists() ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// App 启动时调用：上次导入没跑完就自动续跑（已导入的会话会被跳过）。
  Future<void> resumePending() async {
    if (_running != null) return;
    final File? file = await pendingZip();
    if (file == null) return;
    unawaited(start(file));
  }

  /// 打开某个会话时调用：确保它的正文已导入。
  ///
  /// - 已有正文 → 立刻 true；
  /// - 正在导（或从持久化的 ZIP 续跑）→ 把这条插队，等它写完（最多 3 分钟）；
  /// - 没有可续跑的 ZIP / 包里没有这条 → false，调用方按空会话处理。
  Future<bool> ensureSessionImported(String sessionId) async {
    if (sessionId.isEmpty) return false;
    final Importer importer = _newImporter();
    if (await importer.hasBody(sessionId)) return true;
    if (_running == null) {
      final File? file = await pendingZip();
      if (file == null) return false;
      unawaited(start(file));
    }
    final DateTime deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      priority(sessionId);
      if (await importer.hasBody(sessionId)) return true;
      if (_running == null) {
        // 任务已结束：再看一眼（可能刚写完），没有就放弃。
        return await importer.hasBody(sessionId);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return await importer.hasBody(sessionId);
  }

  ImportProgress get progress => _progress;

  ImportResult? get result => _result;

  bool get running => _progress.running;

  /// 可重试的失败会话 id（按失败顺序）。
  List<String> get failedSessionIds => <String>[
        for (final ImportPlanRow row in _rows)
          if (row.status == ImportRowStatus.failed) row.id,
      ];

  /// 失败会话 → 中文错误。
  Map<String, String> get failedErrors => <String, String>{
        for (final ImportPlanRow row in _rows)
          if (row.status == ImportRowStatus.failed) row.id: row.error,
      };

  /// 最近一次导入的全部计划行（调试 / 列表状态点用）。
  List<ImportPlanRow> get rows => List<ImportPlanRow>.unmodifiable(_rows);

  Importer _newImporter() => Importer(db, attachmentsRoot: attachmentsRoot);

  /// 进度流（先发当前值，之后每次变化发一次）。
  Stream<ImportProgress> watchProgress() {
    late final StreamController<ImportProgress> controller;
    void listener() {
      if (!controller.isClosed) controller.add(_progress);
    }

    controller = StreamController<ImportProgress>(
      onListen: () {
        addListener(listener);
        controller.add(_progress);
      },
      onCancel: () {
        removeListener(listener);
      },
    );
    return controller.stream;
  }

  /// 开始导入一个 ZIP；重复调用返回正在跑的那次。
  Future<ImportResult> start(File file) {
    final Future<ImportResult>? running = _running;
    if (running != null) return running;
    final Future<ImportResult> future = _run(file);
    _running = future;
    return future;
  }

  /// 开始导入一个 ZIP 路径。
  Future<ImportResult> startPath(String path) => start(File(path));

  /// 用系统文件选择器选一个 ZIP 并开始导入；用户取消返回 null。
  Future<ImportResult?> pickAndStart() async {
    final PlatformFile? picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['zip'],
    );
    final String? path = picked?.path;
    if (path == null || path.isEmpty) return null;
    return start(File(path));
  }

  /// 用户点了某条标题 → 正文插队优先补。
  ///
  /// 返回 false 表示该会话不存在 / 已导入 / 导出包里没有正文。
  bool priority(String sessionId) {
    if (sessionId.isEmpty || _priorityIds.contains(sessionId)) return false;
    for (final ImportPlanRow row in _rows) {
      if (row.id != sessionId) continue;
      if (row.status != ImportRowStatus.pending &&
          row.status != ImportRowStatus.title) {
        return false;
      }
      _priorityIds.add(sessionId);
      _priorityQueue.add(sessionId);
      return true;
    }
    return false;
  }

  /// 请求取消（当前会话写完后停下；可再用同一 ZIP 续传）。
  void cancel() {
    if (!running) return;
    _cancelRequested = true;
    _notify();
  }

  /// 只重试失败的会话（复用同一个 ZIP）。
  Future<ImportResult?> retryFailed() async {
    if (_running != null) return null;
    final File? file = _file;
    if (file == null) return _result;
    final Set<String> failedIds = failedSessionIds.toSet();
    if (failedIds.isEmpty) return _result;
    final Future<ImportResult> future = _run(file, retryIds: failedIds);
    _running = future;
    return future;
  }

  /// 重置到空闲态（不动数据库）。
  void reset() {
    if (_running != null) return;
    _result = null;
    _rows = <ImportPlanRow>[];
    _errors.clear();
    _priorityQueue.clear();
    _priorityIds.clear();
    _source = null;
    _file = null;
    _progress = ImportProgress.idle;
    unawaited(_forgetZip());
    _notify();
  }

  Future<ImportResult> _run(File file, {Set<String>? retryIds}) async {
    _cancelRequested = false;
    _file = file;
    unawaited(_rememberZip(file));
    _errors.clear();
    _priorityQueue.clear();
    _priorityIds.clear();
    _result = null;
    _progress = const ImportProgress(
      phase: ImportPhase.preparing,
      running: true,
    );
    _notify();

    final Importer importer = _newImporter();
    ImportSource? source;
    int titlesWritten = 0;
    int skipped = 0;
    int failed = 0;
    int bodiesTotal = 0;
    int bodiesDone = 0;
    int bodiesImported = 0;
    int addedMessages = 0;
    int addedAttachments = 0;
    bool cancelled = false;
    String? fatalError;

    try {
      source = await importer.open(file);
      _source = source;
      final List<ImportPlanRow> allRows = source.rows;
      if (retryIds == null) {
        _rows = allRows;
      } else {
        // 重试：保留原行对象里的失败信息，只重跑指定 id。
        final Map<String, ImportPlanRow> existing = <String, ImportPlanRow>{
          for (final ImportPlanRow row in _rows) row.id: row,
        };
        for (final ImportPlanRow row in allRows) {
          final ImportPlanRow? previous = existing[row.id];
          if (previous != null) {
            previous.status = row.status == ImportRowStatus.missing
                ? ImportRowStatus.missing
                : ImportRowStatus.pending;
            previous.error = '';
          }
        }
        _rows = <ImportPlanRow>[
          for (final ImportPlanRow row in allRows) existing[row.id] ?? row,
        ];
      }

      // ---------------- 阶段 A：标题 ----------------
      _progress = ImportProgress(
        phase: ImportPhase.titles,
        totalSessions: _rows.length,
        running: true,
      );
      _notify();

      for (int i = 0; i < _rows.length; i++) {
        if (_cancelRequested) {
          cancelled = true;
          break;
        }
        final ImportPlanRow row = _rows[i];
        if (retryIds != null && !retryIds.contains(row.id)) continue;
        if (row.status == ImportRowStatus.missing) {
          failed++;
          row.error = '导出包里没有这个会话的正文';
          _errors[row.id] = row.error;
          continue;
        }
        if (await importer.hasBody(row.id)) {
          row.status = ImportRowStatus.done;
          skipped++;
          continue;
        }
        final bool wrote = await importer.writeTitle(row);
        if (wrote) titlesWritten++;
        row.status = ImportRowStatus.title;
        // 3457 条标题逐条刷新会打爆 UI，每 8 条发一次进度。
        if (i % 8 == 0 || i == _rows.length - 1) {
          _progress = _progress.copyWith(
            titlesWritten: titlesWritten,
            bodiesSkipped: skipped,
            failed: failed,
          );
          _notify();
        }
      }

      if (!cancelled) {
        // 标题阶段完成：先通知 UI 建角色卡（正文继续在后台导入，互不阻塞）。
        try {
          onTitlesDone?.call();
        } catch (_) {
          // 建卡失败不影响正文导入。
        }
        // ---------------- 阶段 B：正文 ----------------
        final List<ImportPlanRow> pending = <ImportPlanRow>[
          for (final ImportPlanRow row in _rows)
            if ((row.status == ImportRowStatus.pending ||
                    row.status == ImportRowStatus.title) &&
                (retryIds == null || retryIds.contains(row.id)))
              row,
        ];
        bodiesTotal = pending.length;
        _progress = _progress.copyWith(
          phase: ImportPhase.bodies,
          totalSessions: _rows.length,
          titlesWritten: titlesWritten,
          bodiesSkipped: skipped,
          bodiesTotal: bodiesTotal,
          bodiesDone: 0,
          failed: failed,
          running: true,
        );
        _notify();

        final List<ImportPlanRow> queue = <ImportPlanRow>[...pending];
        while (queue.isNotEmpty) {
          if (_cancelRequested) {
            cancelled = true;
            break;
          }
          final ImportPlanRow row = _takeNextBodyRow(queue);
          if (row.status == ImportRowStatus.done ||
              row.status == ImportRowStatus.missing) {
            continue;
          }
          row.status = ImportRowStatus.working;
          _progress = _progress.copyWith(
            currentTitle: row.title,
            bodiesDone: bodiesDone,
            failed: failed,
          );
          _notify();
          try {
            final ({int messages, int files, bool skipped}) written =
                await importer.importBody(source, row);
            if (written.skipped) {
              skipped++;
            } else {
              bodiesImported++;
              addedMessages += written.messages;
              addedAttachments += written.files;
            }
          } catch (error) {
            row.status = ImportRowStatus.failed;
            row.error = importErrorMessage(error);
            failed++;
            _errors[row.id] = row.error;
          }
          bodiesDone++;
          _progress = _progress.copyWith(
            bodiesDone: bodiesDone,
            bodiesImported: bodiesImported,
            failed: failed,
            addedMessages: addedMessages,
            addedAttachments: addedAttachments,
            currentTitle: row.title,
          );
          _notify();
          // 让出事件循环，UI 才能刷新（大包逐会话 import 不会卡死界面）。
          await Future<void>.delayed(Duration.zero);
        }
      }
    } on ExportFormatException catch (error) {
      fatalError = error.message;
    } on ZipFormatException catch (error) {
      fatalError = error.message;
    } on FileSystemException catch (error) {
      fatalError = '导入失败：${error.message}';
    } catch (error) {
      fatalError = '导入失败：$error';
    } finally {
      final ImportSource? opened = source;
      _source = null;
      if (opened != null) {
        await opened.close();
      }
      _running = null;
    }

    final ImportResult result = ImportResult(
      totalSessions: _rows.length,
      addedSessions: bodiesImported,
      addedMessages: addedMessages,
      addedAttachments: addedAttachments,
      skippedSessions: skipped,
      failedSessions: failed,
      titlesWritten: titlesWritten,
      cancelled: cancelled,
      fatalError: fatalError,
      errors: Map<String, String>.unmodifiable(_errors),
    );
    _result = result;

    if (fatalError != null) {
      _progress = _progress.copyWith(
        phase: ImportPhase.failed,
        fatalError: fatalError,
        running: false,
        currentTitle: null,
        failed: failed,
        bodiesTotal: bodiesTotal,
        bodiesDone: bodiesDone,
        bodiesImported: bodiesImported,
      );
    } else if (cancelled) {
      _progress = _progress.copyWith(
        phase: ImportPhase.cancelled,
        running: false,
        currentTitle: null,
        failed: failed,
        bodiesTotal: bodiesTotal,
        bodiesDone: bodiesDone,
        bodiesImported: bodiesImported,
      );
    } else {
      _progress = _progress.copyWith(
        phase: ImportPhase.done,
        running: false,
        currentTitle: null,
        failed: failed,
        bodiesTotal: bodiesTotal,
        bodiesDone: bodiesDone,
        titlesWritten: titlesWritten,
        bodiesSkipped: skipped,
        bodiesImported: bodiesImported,
        addedMessages: addedMessages,
        addedAttachments: addedAttachments,
      );
    }
    if (!cancelled && fatalError == null) {
      // 正常跑完就清掉续跑标记；取消/致命失败保留，下次启动还能接着导。
      unawaited(_forgetZip());
    }
    _notify();
    return result;
  }

  /// 优先队列 → 按索引顺序取一条（队首被点过就插队）。
  ImportPlanRow _takeNextBodyRow(List<ImportPlanRow> queue) {
    while (_priorityQueue.isNotEmpty) {
      final String id = _priorityQueue.removeAt(0);
      _priorityIds.remove(id);
      for (int i = 0; i < queue.length; i++) {
        if (queue[i].id != id) continue;
        final ImportPlanRow row = queue.removeAt(i);
        if (row.status == ImportRowStatus.failed) continue;
        return row;
      }
    }
    return queue.removeAt(0);
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRequested = true;
    final ImportSource? source = _source;
    _source = null;
    if (source != null) {
      unawaited(source.close());
    }
    super.dispose();
  }
}

/// Riverpod 版导入任务（设置页 / 会话列表共用）。
class ImportTaskNotifier extends ImportTask {
  ImportTaskNotifier(super.db, {super.attachmentsRoot});
}

/// 全局导入任务：`importTaskProvider`。
final Provider<ImportTaskNotifier> importTaskProvider =
    Provider<ImportTaskNotifier>((Ref ref) {
  final AppDatabase db = ref.watch(databaseProvider);
  final ImportTaskNotifier notifier = ImportTaskNotifier(db);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// 导入进度流（会话列表顶部监听它即可）。
final StreamProvider<ImportProgress> importProgressProvider =
    StreamProvider<ImportProgress>((Ref ref) {
  final ImportTaskNotifier task = ref.watch(importTaskProvider);
  return task.watchProgress();
});
