// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $SessionsTable extends Sessions with TableInfo<$SessionsTable, Session> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  static const VerificationMeta _messageCountMeta = const VerificationMeta(
    'messageCount',
  );
  @override
  late final GeneratedColumn<int> messageCount = GeneratedColumn<int>(
    'message_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _currentMessageIdMeta = const VerificationMeta(
    'currentMessageId',
  );
  @override
  late final GeneratedColumn<String> currentMessageId = GeneratedColumn<String>(
    'current_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rootMessageIdMeta = const VerificationMeta(
    'rootMessageId',
  );
  @override
  late final GeneratedColumn<String> rootMessageId = GeneratedColumn<String>(
    'root_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _flagsMeta = const VerificationMeta('flags');
  @override
  late final GeneratedColumn<int> flags = GeneratedColumn<int>(
    'flags',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _searchEnabledMeta = const VerificationMeta(
    'searchEnabled',
  );
  @override
  late final GeneratedColumn<bool> searchEnabled = GeneratedColumn<bool>(
    'search_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("search_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _thinkingEnabledMeta = const VerificationMeta(
    'thinkingEnabled',
  );
  @override
  late final GeneratedColumn<bool> thinkingEnabled = GeneratedColumn<bool>(
    'thinking_enabled',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("thinking_enabled" IN (0, 1))',
    ),
  );
  static const VerificationMeta _thinkingLevelMeta = const VerificationMeta(
    'thinkingLevel',
  );
  @override
  late final GeneratedColumn<String> thinkingLevel = GeneratedColumn<String>(
    'thinking_level',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contextKeepRoundsMeta = const VerificationMeta(
    'contextKeepRounds',
  );
  @override
  late final GeneratedColumn<int> contextKeepRounds = GeneratedColumn<int>(
    'context_keep_rounds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<String> characterId = GeneratedColumn<String>(
    'character_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    createdAt,
    updatedAt,
    messageCount,
    currentMessageId,
    rootMessageId,
    flags,
    sort,
    searchEnabled,
    thinkingEnabled,
    thinkingLevel,
    contextKeepRounds,
    characterId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Session> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('message_count')) {
      context.handle(
        _messageCountMeta,
        messageCount.isAcceptableOrUnknown(
          data['message_count']!,
          _messageCountMeta,
        ),
      );
    }
    if (data.containsKey('current_message_id')) {
      context.handle(
        _currentMessageIdMeta,
        currentMessageId.isAcceptableOrUnknown(
          data['current_message_id']!,
          _currentMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('root_message_id')) {
      context.handle(
        _rootMessageIdMeta,
        rootMessageId.isAcceptableOrUnknown(
          data['root_message_id']!,
          _rootMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('flags')) {
      context.handle(
        _flagsMeta,
        flags.isAcceptableOrUnknown(data['flags']!, _flagsMeta),
      );
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    }
    if (data.containsKey('search_enabled')) {
      context.handle(
        _searchEnabledMeta,
        searchEnabled.isAcceptableOrUnknown(
          data['search_enabled']!,
          _searchEnabledMeta,
        ),
      );
    }
    if (data.containsKey('thinking_enabled')) {
      context.handle(
        _thinkingEnabledMeta,
        thinkingEnabled.isAcceptableOrUnknown(
          data['thinking_enabled']!,
          _thinkingEnabledMeta,
        ),
      );
    }
    if (data.containsKey('thinking_level')) {
      context.handle(
        _thinkingLevelMeta,
        thinkingLevel.isAcceptableOrUnknown(
          data['thinking_level']!,
          _thinkingLevelMeta,
        ),
      );
    }
    if (data.containsKey('context_keep_rounds')) {
      context.handle(
        _contextKeepRoundsMeta,
        contextKeepRounds.isAcceptableOrUnknown(
          data['context_keep_rounds']!,
          _contextKeepRoundsMeta,
        ),
      );
    }
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Session map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Session(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      messageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_count'],
      )!,
      currentMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_message_id'],
      ),
      rootMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}root_message_id'],
      ),
      flags: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}flags'],
      )!,
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      ),
      searchEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}search_enabled'],
      )!,
      thinkingEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}thinking_enabled'],
      ),
      thinkingLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thinking_level'],
      ),
      contextKeepRounds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}context_keep_rounds'],
      ),
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}character_id'],
      ),
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }
}

class Session extends DataClass implements Insertable<Session> {
  /// 会话 id；导入的 DeepSeek 会话保留外部 id。
  final String id;

  /// 标题（空串时 UI 显示「未命名会话」）。
  final String title;
  final DateTime createdAt;

  /// 列表按它排序（`touchSession` 更新）。
  final DateTime updatedAt;

  /// 该会话消息数（分支重生成时可能 > 可见链长度）。
  final int messageCount;

  /// 分支：当前消息节点。
  final String? currentMessageId;

  /// 分支：分支根节点。
  final String? rootMessageId;

  /// 位域（[推断] 置顶/归档/已读），见 `setSessionFlag`。
  final int flags;

  /// 手动排序（置顶用，升序，NULL 排最后）。
  final int? sort;

  /// 会话级联网搜索开关。
  final bool searchEnabled;

  /// 会话级「深度思考」覆盖值。
  ///
  /// `NULL` = 未覆盖（用全局设置里的默认值）；**聊天页只写这一列，不写全局设置**。
  final bool? thinkingEnabled;

  /// 会话级「思考强度」覆盖值（`ThinkingLevel.wireName`：`low`/`medium`/`high`）。
  ///
  /// `NULL` = 未覆盖（用全局默认档位）。
  final String? thinkingLevel;

  /// 会话级上下文预算覆盖值（保留最近 N 轮；`<= 0` = 不限制）。
  ///
  /// `NULL` = 未覆盖（用全局默认值）。
  final int? contextKeepRounds;

  /// 所属角色卡（`characters.id`）。
  ///
  /// v3 及更早的老会话为 `NULL`：读取时按需建一张默认角色卡（`ensureCharacterForSession`），
  /// 因此这里**不使用 FK 级联**，避免删角色时误删会话；解绑由应用层显式写 `NULL`。
  final String? characterId;
  const Session({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messageCount,
    this.currentMessageId,
    this.rootMessageId,
    required this.flags,
    this.sort,
    required this.searchEnabled,
    this.thinkingEnabled,
    this.thinkingLevel,
    this.contextKeepRounds,
    this.characterId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['message_count'] = Variable<int>(messageCount);
    if (!nullToAbsent || currentMessageId != null) {
      map['current_message_id'] = Variable<String>(currentMessageId);
    }
    if (!nullToAbsent || rootMessageId != null) {
      map['root_message_id'] = Variable<String>(rootMessageId);
    }
    map['flags'] = Variable<int>(flags);
    if (!nullToAbsent || sort != null) {
      map['sort'] = Variable<int>(sort);
    }
    map['search_enabled'] = Variable<bool>(searchEnabled);
    if (!nullToAbsent || thinkingEnabled != null) {
      map['thinking_enabled'] = Variable<bool>(thinkingEnabled);
    }
    if (!nullToAbsent || thinkingLevel != null) {
      map['thinking_level'] = Variable<String>(thinkingLevel);
    }
    if (!nullToAbsent || contextKeepRounds != null) {
      map['context_keep_rounds'] = Variable<int>(contextKeepRounds);
    }
    if (!nullToAbsent || characterId != null) {
      map['character_id'] = Variable<String>(characterId);
    }
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      id: Value(id),
      title: Value(title),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      messageCount: Value(messageCount),
      currentMessageId: currentMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(currentMessageId),
      rootMessageId: rootMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(rootMessageId),
      flags: Value(flags),
      sort: sort == null && nullToAbsent ? const Value.absent() : Value(sort),
      searchEnabled: Value(searchEnabled),
      thinkingEnabled: thinkingEnabled == null && nullToAbsent
          ? const Value.absent()
          : Value(thinkingEnabled),
      thinkingLevel: thinkingLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(thinkingLevel),
      contextKeepRounds: contextKeepRounds == null && nullToAbsent
          ? const Value.absent()
          : Value(contextKeepRounds),
      characterId: characterId == null && nullToAbsent
          ? const Value.absent()
          : Value(characterId),
    );
  }

  factory Session.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Session(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      messageCount: serializer.fromJson<int>(json['messageCount']),
      currentMessageId: serializer.fromJson<String?>(json['currentMessageId']),
      rootMessageId: serializer.fromJson<String?>(json['rootMessageId']),
      flags: serializer.fromJson<int>(json['flags']),
      sort: serializer.fromJson<int?>(json['sort']),
      searchEnabled: serializer.fromJson<bool>(json['searchEnabled']),
      thinkingEnabled: serializer.fromJson<bool?>(json['thinkingEnabled']),
      thinkingLevel: serializer.fromJson<String?>(json['thinkingLevel']),
      contextKeepRounds: serializer.fromJson<int?>(json['contextKeepRounds']),
      characterId: serializer.fromJson<String?>(json['characterId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'messageCount': serializer.toJson<int>(messageCount),
      'currentMessageId': serializer.toJson<String?>(currentMessageId),
      'rootMessageId': serializer.toJson<String?>(rootMessageId),
      'flags': serializer.toJson<int>(flags),
      'sort': serializer.toJson<int?>(sort),
      'searchEnabled': serializer.toJson<bool>(searchEnabled),
      'thinkingEnabled': serializer.toJson<bool?>(thinkingEnabled),
      'thinkingLevel': serializer.toJson<String?>(thinkingLevel),
      'contextKeepRounds': serializer.toJson<int?>(contextKeepRounds),
      'characterId': serializer.toJson<String?>(characterId),
    };
  }

  Session copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? messageCount,
    Value<String?> currentMessageId = const Value.absent(),
    Value<String?> rootMessageId = const Value.absent(),
    int? flags,
    Value<int?> sort = const Value.absent(),
    bool? searchEnabled,
    Value<bool?> thinkingEnabled = const Value.absent(),
    Value<String?> thinkingLevel = const Value.absent(),
    Value<int?> contextKeepRounds = const Value.absent(),
    Value<String?> characterId = const Value.absent(),
  }) => Session(
    id: id ?? this.id,
    title: title ?? this.title,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    messageCount: messageCount ?? this.messageCount,
    currentMessageId: currentMessageId.present
        ? currentMessageId.value
        : this.currentMessageId,
    rootMessageId: rootMessageId.present
        ? rootMessageId.value
        : this.rootMessageId,
    flags: flags ?? this.flags,
    sort: sort.present ? sort.value : this.sort,
    searchEnabled: searchEnabled ?? this.searchEnabled,
    thinkingEnabled: thinkingEnabled.present
        ? thinkingEnabled.value
        : this.thinkingEnabled,
    thinkingLevel: thinkingLevel.present
        ? thinkingLevel.value
        : this.thinkingLevel,
    contextKeepRounds: contextKeepRounds.present
        ? contextKeepRounds.value
        : this.contextKeepRounds,
    characterId: characterId.present ? characterId.value : this.characterId,
  );
  Session copyWithCompanion(SessionsCompanion data) {
    return Session(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      messageCount: data.messageCount.present
          ? data.messageCount.value
          : this.messageCount,
      currentMessageId: data.currentMessageId.present
          ? data.currentMessageId.value
          : this.currentMessageId,
      rootMessageId: data.rootMessageId.present
          ? data.rootMessageId.value
          : this.rootMessageId,
      flags: data.flags.present ? data.flags.value : this.flags,
      sort: data.sort.present ? data.sort.value : this.sort,
      searchEnabled: data.searchEnabled.present
          ? data.searchEnabled.value
          : this.searchEnabled,
      thinkingEnabled: data.thinkingEnabled.present
          ? data.thinkingEnabled.value
          : this.thinkingEnabled,
      thinkingLevel: data.thinkingLevel.present
          ? data.thinkingLevel.value
          : this.thinkingLevel,
      contextKeepRounds: data.contextKeepRounds.present
          ? data.contextKeepRounds.value
          : this.contextKeepRounds,
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Session(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('messageCount: $messageCount, ')
          ..write('currentMessageId: $currentMessageId, ')
          ..write('rootMessageId: $rootMessageId, ')
          ..write('flags: $flags, ')
          ..write('sort: $sort, ')
          ..write('searchEnabled: $searchEnabled, ')
          ..write('thinkingEnabled: $thinkingEnabled, ')
          ..write('thinkingLevel: $thinkingLevel, ')
          ..write('contextKeepRounds: $contextKeepRounds, ')
          ..write('characterId: $characterId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    createdAt,
    updatedAt,
    messageCount,
    currentMessageId,
    rootMessageId,
    flags,
    sort,
    searchEnabled,
    thinkingEnabled,
    thinkingLevel,
    contextKeepRounds,
    characterId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Session &&
          other.id == this.id &&
          other.title == this.title &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.messageCount == this.messageCount &&
          other.currentMessageId == this.currentMessageId &&
          other.rootMessageId == this.rootMessageId &&
          other.flags == this.flags &&
          other.sort == this.sort &&
          other.searchEnabled == this.searchEnabled &&
          other.thinkingEnabled == this.thinkingEnabled &&
          other.thinkingLevel == this.thinkingLevel &&
          other.contextKeepRounds == this.contextKeepRounds &&
          other.characterId == this.characterId);
}

class SessionsCompanion extends UpdateCompanion<Session> {
  final Value<String> id;
  final Value<String> title;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> messageCount;
  final Value<String?> currentMessageId;
  final Value<String?> rootMessageId;
  final Value<int> flags;
  final Value<int?> sort;
  final Value<bool> searchEnabled;
  final Value<bool?> thinkingEnabled;
  final Value<String?> thinkingLevel;
  final Value<int?> contextKeepRounds;
  final Value<String?> characterId;
  final Value<int> rowid;
  const SessionsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.messageCount = const Value.absent(),
    this.currentMessageId = const Value.absent(),
    this.rootMessageId = const Value.absent(),
    this.flags = const Value.absent(),
    this.sort = const Value.absent(),
    this.searchEnabled = const Value.absent(),
    this.thinkingEnabled = const Value.absent(),
    this.thinkingLevel = const Value.absent(),
    this.contextKeepRounds = const Value.absent(),
    this.characterId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.messageCount = const Value.absent(),
    this.currentMessageId = const Value.absent(),
    this.rootMessageId = const Value.absent(),
    this.flags = const Value.absent(),
    this.sort = const Value.absent(),
    this.searchEnabled = const Value.absent(),
    this.thinkingEnabled = const Value.absent(),
    this.thinkingLevel = const Value.absent(),
    this.contextKeepRounds = const Value.absent(),
    this.characterId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<Session> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? messageCount,
    Expression<String>? currentMessageId,
    Expression<String>? rootMessageId,
    Expression<int>? flags,
    Expression<int>? sort,
    Expression<bool>? searchEnabled,
    Expression<bool>? thinkingEnabled,
    Expression<String>? thinkingLevel,
    Expression<int>? contextKeepRounds,
    Expression<String>? characterId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (messageCount != null) 'message_count': messageCount,
      if (currentMessageId != null) 'current_message_id': currentMessageId,
      if (rootMessageId != null) 'root_message_id': rootMessageId,
      if (flags != null) 'flags': flags,
      if (sort != null) 'sort': sort,
      if (searchEnabled != null) 'search_enabled': searchEnabled,
      if (thinkingEnabled != null) 'thinking_enabled': thinkingEnabled,
      if (thinkingLevel != null) 'thinking_level': thinkingLevel,
      if (contextKeepRounds != null) 'context_keep_rounds': contextKeepRounds,
      if (characterId != null) 'character_id': characterId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? messageCount,
    Value<String?>? currentMessageId,
    Value<String?>? rootMessageId,
    Value<int>? flags,
    Value<int?>? sort,
    Value<bool>? searchEnabled,
    Value<bool?>? thinkingEnabled,
    Value<String?>? thinkingLevel,
    Value<int?>? contextKeepRounds,
    Value<String?>? characterId,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messageCount: messageCount ?? this.messageCount,
      currentMessageId: currentMessageId ?? this.currentMessageId,
      rootMessageId: rootMessageId ?? this.rootMessageId,
      flags: flags ?? this.flags,
      sort: sort ?? this.sort,
      searchEnabled: searchEnabled ?? this.searchEnabled,
      thinkingEnabled: thinkingEnabled ?? this.thinkingEnabled,
      thinkingLevel: thinkingLevel ?? this.thinkingLevel,
      contextKeepRounds: contextKeepRounds ?? this.contextKeepRounds,
      characterId: characterId ?? this.characterId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (messageCount.present) {
      map['message_count'] = Variable<int>(messageCount.value);
    }
    if (currentMessageId.present) {
      map['current_message_id'] = Variable<String>(currentMessageId.value);
    }
    if (rootMessageId.present) {
      map['root_message_id'] = Variable<String>(rootMessageId.value);
    }
    if (flags.present) {
      map['flags'] = Variable<int>(flags.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    if (searchEnabled.present) {
      map['search_enabled'] = Variable<bool>(searchEnabled.value);
    }
    if (thinkingEnabled.present) {
      map['thinking_enabled'] = Variable<bool>(thinkingEnabled.value);
    }
    if (thinkingLevel.present) {
      map['thinking_level'] = Variable<String>(thinkingLevel.value);
    }
    if (contextKeepRounds.present) {
      map['context_keep_rounds'] = Variable<int>(contextKeepRounds.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<String>(characterId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('messageCount: $messageCount, ')
          ..write('currentMessageId: $currentMessageId, ')
          ..write('rootMessageId: $rootMessageId, ')
          ..write('flags: $flags, ')
          ..write('sort: $sort, ')
          ..write('searchEnabled: $searchEnabled, ')
          ..write('thinkingEnabled: $thinkingEnabled, ')
          ..write('thinkingLevel: $thinkingLevel, ')
          ..write('contextKeepRounds: $contextKeepRounds, ')
          ..write('characterId: $characterId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  static const VerificationMeta _rootMessageIdMeta = const VerificationMeta(
    'rootMessageId',
  );
  @override
  late final GeneratedColumn<String> rootMessageId = GeneratedColumn<String>(
    'root_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _currentMessageIdMeta = const VerificationMeta(
    'currentMessageId',
  );
  @override
  late final GeneratedColumn<String> currentMessageId = GeneratedColumn<String>(
    'current_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _indexMeta = const VerificationMeta('index');
  @override
  late final GeneratedColumn<int> index = GeneratedColumn<int>(
    'index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _flagsMeta = const VerificationMeta('flags');
  @override
  late final GeneratedColumn<int> flags = GeneratedColumn<int>(
    'flags',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    role,
    content,
    createdAt,
    rootMessageId,
    currentMessageId,
    index,
    flags,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('root_message_id')) {
      context.handle(
        _rootMessageIdMeta,
        rootMessageId.isAcceptableOrUnknown(
          data['root_message_id']!,
          _rootMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('current_message_id')) {
      context.handle(
        _currentMessageIdMeta,
        currentMessageId.isAcceptableOrUnknown(
          data['current_message_id']!,
          _currentMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('index')) {
      context.handle(
        _indexMeta,
        index.isAcceptableOrUnknown(data['index']!, _indexMeta),
      );
    }
    if (data.containsKey('flags')) {
      context.handle(
        _flagsMeta,
        flags.isAcceptableOrUnknown(data['flags']!, _flagsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      rootMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}root_message_id'],
      ),
      currentMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_message_id'],
      ),
      index: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}index'],
      )!,
      flags: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}flags'],
      )!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  /// 消息 id（`_StoredMessage`）。
  final String id;

  /// 所属会话（FK → sessions.id，级联删除）。
  final String sessionId;

  /// `user` / `assistant` / `system`（展示文案「用户/助手」在 UI 层）。
  final String role;

  /// 正文（可能是 blocks JSON，见 `core/chat/blocks.dart` 的 `encodeBlocks`）。
  final String content;
  final DateTime createdAt;

  /// 分支根。
  final String? rootMessageId;

  /// 当前分支指针。
  final String? currentMessageId;

  /// 同会话内序号（列名就是 `index`，drift 生成时加引号）。
  final int index;

  /// 位域（[推断] 已压缩/已总结/错误）。
  final int flags;
  const Message({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.rootMessageId,
    this.currentMessageId,
    required this.index,
    required this.flags,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['role'] = Variable<String>(role);
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || rootMessageId != null) {
      map['root_message_id'] = Variable<String>(rootMessageId);
    }
    if (!nullToAbsent || currentMessageId != null) {
      map['current_message_id'] = Variable<String>(currentMessageId);
    }
    map['index'] = Variable<int>(index);
    map['flags'] = Variable<int>(flags);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      role: Value(role),
      content: Value(content),
      createdAt: Value(createdAt),
      rootMessageId: rootMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(rootMessageId),
      currentMessageId: currentMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(currentMessageId),
      index: Value(index),
      flags: Value(flags),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      role: serializer.fromJson<String>(json['role']),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      rootMessageId: serializer.fromJson<String?>(json['rootMessageId']),
      currentMessageId: serializer.fromJson<String?>(json['currentMessageId']),
      index: serializer.fromJson<int>(json['index']),
      flags: serializer.fromJson<int>(json['flags']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'role': serializer.toJson<String>(role),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'rootMessageId': serializer.toJson<String?>(rootMessageId),
      'currentMessageId': serializer.toJson<String?>(currentMessageId),
      'index': serializer.toJson<int>(index),
      'flags': serializer.toJson<int>(flags),
    };
  }

  Message copyWith({
    String? id,
    String? sessionId,
    String? role,
    String? content,
    DateTime? createdAt,
    Value<String?> rootMessageId = const Value.absent(),
    Value<String?> currentMessageId = const Value.absent(),
    int? index,
    int? flags,
  }) => Message(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    role: role ?? this.role,
    content: content ?? this.content,
    createdAt: createdAt ?? this.createdAt,
    rootMessageId: rootMessageId.present
        ? rootMessageId.value
        : this.rootMessageId,
    currentMessageId: currentMessageId.present
        ? currentMessageId.value
        : this.currentMessageId,
    index: index ?? this.index,
    flags: flags ?? this.flags,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      rootMessageId: data.rootMessageId.present
          ? data.rootMessageId.value
          : this.rootMessageId,
      currentMessageId: data.currentMessageId.present
          ? data.currentMessageId.value
          : this.currentMessageId,
      index: data.index.present ? data.index.value : this.index,
      flags: data.flags.present ? data.flags.value : this.flags,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('rootMessageId: $rootMessageId, ')
          ..write('currentMessageId: $currentMessageId, ')
          ..write('index: $index, ')
          ..write('flags: $flags')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    role,
    content,
    createdAt,
    rootMessageId,
    currentMessageId,
    index,
    flags,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.role == this.role &&
          other.content == this.content &&
          other.createdAt == this.createdAt &&
          other.rootMessageId == this.rootMessageId &&
          other.currentMessageId == this.currentMessageId &&
          other.index == this.index &&
          other.flags == this.flags);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> role;
  final Value<String> content;
  final Value<DateTime> createdAt;
  final Value<String?> rootMessageId;
  final Value<String?> currentMessageId;
  final Value<int> index;
  final Value<int> flags;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rootMessageId = const Value.absent(),
    this.currentMessageId = const Value.absent(),
    this.index = const Value.absent(),
    this.flags = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String sessionId,
    required String role,
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rootMessageId = const Value.absent(),
    this.currentMessageId = const Value.absent(),
    this.index = const Value.absent(),
    this.flags = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       role = Value(role);
  static Insertable<Message> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? role,
    Expression<String>? content,
    Expression<DateTime>? createdAt,
    Expression<String>? rootMessageId,
    Expression<String>? currentMessageId,
    Expression<int>? index,
    Expression<int>? flags,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
      if (rootMessageId != null) 'root_message_id': rootMessageId,
      if (currentMessageId != null) 'current_message_id': currentMessageId,
      if (index != null) 'index': index,
      if (flags != null) 'flags': flags,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? role,
    Value<String>? content,
    Value<DateTime>? createdAt,
    Value<String?>? rootMessageId,
    Value<String?>? currentMessageId,
    Value<int>? index,
    Value<int>? flags,
    Value<int>? rowid,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      rootMessageId: rootMessageId ?? this.rootMessageId,
      currentMessageId: currentMessageId ?? this.currentMessageId,
      index: index ?? this.index,
      flags: flags ?? this.flags,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rootMessageId.present) {
      map['root_message_id'] = Variable<String>(rootMessageId.value);
    }
    if (currentMessageId.present) {
      map['current_message_id'] = Variable<String>(currentMessageId.value);
    }
    if (index.present) {
      map['index'] = Variable<int>(index.value);
    }
    if (flags.present) {
      map['flags'] = Variable<int>(flags.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('rootMessageId: $rootMessageId, ')
          ..write('currentMessageId: $currentMessageId, ')
          ..write('index: $index, ')
          ..write('flags: $flags, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AttachmentsTable extends Attachments
    with TableInfo<$AttachmentsTable, Attachment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AttachmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _mimeMeta = const VerificationMeta('mime');
  @override
  late final GeneratedColumn<String> mime = GeneratedColumn<String>(
    'mime',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  @override
  late final GeneratedColumn<String> fileId = GeneratedColumn<String>(
    'file_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    messageId,
    fileName,
    fileSize,
    mime,
    path,
    width,
    height,
    fileId,
    url,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attachments';
  @override
  VerificationContext validateIntegrity(
    Insertable<Attachment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    }
    if (data.containsKey('mime')) {
      context.handle(
        _mimeMeta,
        mime.isAcceptableOrUnknown(data['mime']!, _mimeMeta),
      );
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('file_id')) {
      context.handle(
        _fileIdMeta,
        fileId.isAcceptableOrUnknown(data['file_id']!, _fileIdMeta),
      );
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Attachment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Attachment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      ),
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      )!,
      mime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      fileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_id'],
      ),
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      ),
    );
  }

  @override
  $AttachmentsTable createAlias(String alias) {
    return $AttachmentsTable(attachedDatabase, alias);
  }
}

class Attachment extends DataClass implements Insertable<Attachment> {
  /// 本地 id（uuid）。
  final String id;
  final String sessionId;

  /// 所属消息（[推断]，导入时可能先落附件后落消息，故不加 FK）。
  final String? messageId;

  /// 原文件名（导出 ZIP 里保存原件）。
  final String fileName;
  final int fileSize;
  final String mime;

  /// 本地缓存路径。
  final String path;

  /// 图片宽（`image_util.dart` 缩放用）。
  final int? width;

  /// 图片高。
  final int? height;

  /// DeepSeek Files API 返回的服务端 id（`attachmentByServerId`）。
  final String? fileId;

  /// 远程链接。
  final String? url;
  const Attachment({
    required this.id,
    required this.sessionId,
    this.messageId,
    required this.fileName,
    required this.fileSize,
    required this.mime,
    required this.path,
    this.width,
    this.height,
    this.fileId,
    this.url,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    if (!nullToAbsent || messageId != null) {
      map['message_id'] = Variable<String>(messageId);
    }
    map['file_name'] = Variable<String>(fileName);
    map['file_size'] = Variable<int>(fileSize);
    map['mime'] = Variable<String>(mime);
    map['path'] = Variable<String>(path);
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    if (!nullToAbsent || fileId != null) {
      map['file_id'] = Variable<String>(fileId);
    }
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    return map;
  }

  AttachmentsCompanion toCompanion(bool nullToAbsent) {
    return AttachmentsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      messageId: messageId == null && nullToAbsent
          ? const Value.absent()
          : Value(messageId),
      fileName: Value(fileName),
      fileSize: Value(fileSize),
      mime: Value(mime),
      path: Value(path),
      width: width == null && nullToAbsent
          ? const Value.absent()
          : Value(width),
      height: height == null && nullToAbsent
          ? const Value.absent()
          : Value(height),
      fileId: fileId == null && nullToAbsent
          ? const Value.absent()
          : Value(fileId),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
    );
  }

  factory Attachment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Attachment(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      messageId: serializer.fromJson<String?>(json['messageId']),
      fileName: serializer.fromJson<String>(json['fileName']),
      fileSize: serializer.fromJson<int>(json['fileSize']),
      mime: serializer.fromJson<String>(json['mime']),
      path: serializer.fromJson<String>(json['path']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      fileId: serializer.fromJson<String?>(json['fileId']),
      url: serializer.fromJson<String?>(json['url']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'messageId': serializer.toJson<String?>(messageId),
      'fileName': serializer.toJson<String>(fileName),
      'fileSize': serializer.toJson<int>(fileSize),
      'mime': serializer.toJson<String>(mime),
      'path': serializer.toJson<String>(path),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'fileId': serializer.toJson<String?>(fileId),
      'url': serializer.toJson<String?>(url),
    };
  }

  Attachment copyWith({
    String? id,
    String? sessionId,
    Value<String?> messageId = const Value.absent(),
    String? fileName,
    int? fileSize,
    String? mime,
    String? path,
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    Value<String?> fileId = const Value.absent(),
    Value<String?> url = const Value.absent(),
  }) => Attachment(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    messageId: messageId.present ? messageId.value : this.messageId,
    fileName: fileName ?? this.fileName,
    fileSize: fileSize ?? this.fileSize,
    mime: mime ?? this.mime,
    path: path ?? this.path,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    fileId: fileId.present ? fileId.value : this.fileId,
    url: url.present ? url.value : this.url,
  );
  Attachment copyWithCompanion(AttachmentsCompanion data) {
    return Attachment(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      mime: data.mime.present ? data.mime.value : this.mime,
      path: data.path.present ? data.path.value : this.path,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      url: data.url.present ? data.url.value : this.url,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Attachment(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('messageId: $messageId, ')
          ..write('fileName: $fileName, ')
          ..write('fileSize: $fileSize, ')
          ..write('mime: $mime, ')
          ..write('path: $path, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('fileId: $fileId, ')
          ..write('url: $url')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    messageId,
    fileName,
    fileSize,
    mime,
    path,
    width,
    height,
    fileId,
    url,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Attachment &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.messageId == this.messageId &&
          other.fileName == this.fileName &&
          other.fileSize == this.fileSize &&
          other.mime == this.mime &&
          other.path == this.path &&
          other.width == this.width &&
          other.height == this.height &&
          other.fileId == this.fileId &&
          other.url == this.url);
}

class AttachmentsCompanion extends UpdateCompanion<Attachment> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String?> messageId;
  final Value<String> fileName;
  final Value<int> fileSize;
  final Value<String> mime;
  final Value<String> path;
  final Value<int?> width;
  final Value<int?> height;
  final Value<String?> fileId;
  final Value<String?> url;
  final Value<int> rowid;
  const AttachmentsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.fileName = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.mime = const Value.absent(),
    this.path = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.fileId = const Value.absent(),
    this.url = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AttachmentsCompanion.insert({
    required String id,
    required String sessionId,
    this.messageId = const Value.absent(),
    this.fileName = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.mime = const Value.absent(),
    this.path = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.fileId = const Value.absent(),
    this.url = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId);
  static Insertable<Attachment> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? messageId,
    Expression<String>? fileName,
    Expression<int>? fileSize,
    Expression<String>? mime,
    Expression<String>? path,
    Expression<int>? width,
    Expression<int>? height,
    Expression<String>? fileId,
    Expression<String>? url,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (messageId != null) 'message_id': messageId,
      if (fileName != null) 'file_name': fileName,
      if (fileSize != null) 'file_size': fileSize,
      if (mime != null) 'mime': mime,
      if (path != null) 'path': path,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (fileId != null) 'file_id': fileId,
      if (url != null) 'url': url,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AttachmentsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String?>? messageId,
    Value<String>? fileName,
    Value<int>? fileSize,
    Value<String>? mime,
    Value<String>? path,
    Value<int?>? width,
    Value<int?>? height,
    Value<String?>? fileId,
    Value<String?>? url,
    Value<int>? rowid,
  }) {
    return AttachmentsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      messageId: messageId ?? this.messageId,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mime: mime ?? this.mime,
      path: path ?? this.path,
      width: width ?? this.width,
      height: height ?? this.height,
      fileId: fileId ?? this.fileId,
      url: url ?? this.url,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (mime.present) {
      map['mime'] = Variable<String>(mime.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (fileId.present) {
      map['file_id'] = Variable<String>(fileId.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('messageId: $messageId, ')
          ..write('fileName: $fileName, ')
          ..write('fileSize: $fileSize, ')
          ..write('mime: $mime, ')
          ..write('path: $path, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('fileId: $fileId, ')
          ..write('url: $url, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionSummariesTable extends SessionSummaries
    with TableInfo<$SessionSummariesTable, SessionSummary> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionSummariesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _summaryCharsMeta = const VerificationMeta(
    'summaryChars',
  );
  @override
  late final GeneratedColumn<int> summaryChars = GeneratedColumn<int>(
    'summary_chars',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    summary,
    summaryChars,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_summaries';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionSummary> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    }
    if (data.containsKey('summary_chars')) {
      context.handle(
        _summaryCharsMeta,
        summaryChars.isAcceptableOrUnknown(
          data['summary_chars']!,
          _summaryCharsMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  SessionSummary map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionSummary(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      )!,
      summaryChars: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}summary_chars'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SessionSummariesTable createAlias(String alias) {
    return $SessionSummariesTable(attachedDatabase, alias);
  }
}

class SessionSummary extends DataClass implements Insertable<SessionSummary> {
  /// 主键即会话 id（db-schema §1 的列名常量里没有独立 id 列 → [推断]）。
  final String sessionId;

  /// 摘要正文。
  final String summary;

  /// 摘要字符数（计入上下文预算）。
  final int summaryChars;
  final DateTime createdAt;

  /// 缓存失效判断用。
  final DateTime updatedAt;
  const SessionSummary({
    required this.sessionId,
    required this.summary,
    required this.summaryChars,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['summary'] = Variable<String>(summary);
    map['summary_chars'] = Variable<int>(summaryChars);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SessionSummariesCompanion toCompanion(bool nullToAbsent) {
    return SessionSummariesCompanion(
      sessionId: Value(sessionId),
      summary: Value(summary),
      summaryChars: Value(summaryChars),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SessionSummary.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionSummary(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      summary: serializer.fromJson<String>(json['summary']),
      summaryChars: serializer.fromJson<int>(json['summaryChars']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'summary': serializer.toJson<String>(summary),
      'summaryChars': serializer.toJson<int>(summaryChars),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SessionSummary copyWith({
    String? sessionId,
    String? summary,
    int? summaryChars,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SessionSummary(
    sessionId: sessionId ?? this.sessionId,
    summary: summary ?? this.summary,
    summaryChars: summaryChars ?? this.summaryChars,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SessionSummary copyWithCompanion(SessionSummariesCompanion data) {
    return SessionSummary(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      summary: data.summary.present ? data.summary.value : this.summary,
      summaryChars: data.summaryChars.present
          ? data.summaryChars.value
          : this.summaryChars,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionSummary(')
          ..write('sessionId: $sessionId, ')
          ..write('summary: $summary, ')
          ..write('summaryChars: $summaryChars, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sessionId, summary, summaryChars, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionSummary &&
          other.sessionId == this.sessionId &&
          other.summary == this.summary &&
          other.summaryChars == this.summaryChars &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SessionSummariesCompanion extends UpdateCompanion<SessionSummary> {
  final Value<String> sessionId;
  final Value<String> summary;
  final Value<int> summaryChars;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SessionSummariesCompanion({
    this.sessionId = const Value.absent(),
    this.summary = const Value.absent(),
    this.summaryChars = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionSummariesCompanion.insert({
    required String sessionId,
    this.summary = const Value.absent(),
    this.summaryChars = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId);
  static Insertable<SessionSummary> custom({
    Expression<String>? sessionId,
    Expression<String>? summary,
    Expression<int>? summaryChars,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (summary != null) 'summary': summary,
      if (summaryChars != null) 'summary_chars': summaryChars,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionSummariesCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? summary,
    Value<int>? summaryChars,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SessionSummariesCompanion(
      sessionId: sessionId ?? this.sessionId,
      summary: summary ?? this.summary,
      summaryChars: summaryChars ?? this.summaryChars,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (summaryChars.present) {
      map['summary_chars'] = Variable<int>(summaryChars.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionSummariesCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('summary: $summary, ')
          ..write('summaryChars: $summaryChars, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SummaryCachesTable extends SummaryCaches
    with TableInfo<$SummaryCachesTable, SummaryCache> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SummaryCachesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contextSummaryMeta = const VerificationMeta(
    'contextSummary',
  );
  @override
  late final GeneratedColumn<String> contextSummary = GeneratedColumn<String>(
    'context_summary',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _summaryCharsMeta = const VerificationMeta(
    'summaryChars',
  );
  @override
  late final GeneratedColumn<int> summaryChars = GeneratedColumn<int>(
    'summary_chars',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    contextSummary,
    summary,
    summaryChars,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'summary_caches';
  @override
  VerificationContext validateIntegrity(
    Insertable<SummaryCache> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('context_summary')) {
      context.handle(
        _contextSummaryMeta,
        contextSummary.isAcceptableOrUnknown(
          data['context_summary']!,
          _contextSummaryMeta,
        ),
      );
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    }
    if (data.containsKey('summary_chars')) {
      context.handle(
        _summaryCharsMeta,
        summaryChars.isAcceptableOrUnknown(
          data['summary_chars']!,
          _summaryCharsMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  SummaryCache map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SummaryCache(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      contextSummary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}context_summary'],
      )!,
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      )!,
      summaryChars: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}summary_chars'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SummaryCachesTable createAlias(String alias) {
    return $SummaryCachesTable(attachedDatabase, alias);
  }
}

class SummaryCache extends DataClass implements Insertable<SummaryCache> {
  final String sessionId;

  /// 截断上下文用的摘要（注入 system 的「【以下是本会话更早对话的压缩摘要…】」）。
  final String contextSummary;

  /// 与 contextSummary 同义冗余（db-schema §2 原表如此）。
  final String summary;
  final int summaryChars;
  final DateTime updatedAt;
  const SummaryCache({
    required this.sessionId,
    required this.contextSummary,
    required this.summary,
    required this.summaryChars,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['context_summary'] = Variable<String>(contextSummary);
    map['summary'] = Variable<String>(summary);
    map['summary_chars'] = Variable<int>(summaryChars);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SummaryCachesCompanion toCompanion(bool nullToAbsent) {
    return SummaryCachesCompanion(
      sessionId: Value(sessionId),
      contextSummary: Value(contextSummary),
      summary: Value(summary),
      summaryChars: Value(summaryChars),
      updatedAt: Value(updatedAt),
    );
  }

  factory SummaryCache.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SummaryCache(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      contextSummary: serializer.fromJson<String>(json['contextSummary']),
      summary: serializer.fromJson<String>(json['summary']),
      summaryChars: serializer.fromJson<int>(json['summaryChars']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'contextSummary': serializer.toJson<String>(contextSummary),
      'summary': serializer.toJson<String>(summary),
      'summaryChars': serializer.toJson<int>(summaryChars),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SummaryCache copyWith({
    String? sessionId,
    String? contextSummary,
    String? summary,
    int? summaryChars,
    DateTime? updatedAt,
  }) => SummaryCache(
    sessionId: sessionId ?? this.sessionId,
    contextSummary: contextSummary ?? this.contextSummary,
    summary: summary ?? this.summary,
    summaryChars: summaryChars ?? this.summaryChars,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SummaryCache copyWithCompanion(SummaryCachesCompanion data) {
    return SummaryCache(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      contextSummary: data.contextSummary.present
          ? data.contextSummary.value
          : this.contextSummary,
      summary: data.summary.present ? data.summary.value : this.summary,
      summaryChars: data.summaryChars.present
          ? data.summaryChars.value
          : this.summaryChars,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SummaryCache(')
          ..write('sessionId: $sessionId, ')
          ..write('contextSummary: $contextSummary, ')
          ..write('summary: $summary, ')
          ..write('summaryChars: $summaryChars, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sessionId, contextSummary, summary, summaryChars, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SummaryCache &&
          other.sessionId == this.sessionId &&
          other.contextSummary == this.contextSummary &&
          other.summary == this.summary &&
          other.summaryChars == this.summaryChars &&
          other.updatedAt == this.updatedAt);
}

class SummaryCachesCompanion extends UpdateCompanion<SummaryCache> {
  final Value<String> sessionId;
  final Value<String> contextSummary;
  final Value<String> summary;
  final Value<int> summaryChars;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SummaryCachesCompanion({
    this.sessionId = const Value.absent(),
    this.contextSummary = const Value.absent(),
    this.summary = const Value.absent(),
    this.summaryChars = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SummaryCachesCompanion.insert({
    required String sessionId,
    this.contextSummary = const Value.absent(),
    this.summary = const Value.absent(),
    this.summaryChars = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId);
  static Insertable<SummaryCache> custom({
    Expression<String>? sessionId,
    Expression<String>? contextSummary,
    Expression<String>? summary,
    Expression<int>? summaryChars,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (contextSummary != null) 'context_summary': contextSummary,
      if (summary != null) 'summary': summary,
      if (summaryChars != null) 'summary_chars': summaryChars,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SummaryCachesCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? contextSummary,
    Value<String>? summary,
    Value<int>? summaryChars,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SummaryCachesCompanion(
      sessionId: sessionId ?? this.sessionId,
      contextSummary: contextSummary ?? this.contextSummary,
      summary: summary ?? this.summary,
      summaryChars: summaryChars ?? this.summaryChars,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (contextSummary.present) {
      map['context_summary'] = Variable<String>(contextSummary.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (summaryChars.present) {
      map['summary_chars'] = Variable<int>(summaryChars.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SummaryCachesCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('contextSummary: $contextSummary, ')
          ..write('summary: $summary, ')
          ..write('summaryChars: $summaryChars, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CharactersTable extends Characters
    with TableInfo<$CharactersTable, CharacterRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CharactersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _promptMeta = const VerificationMeta('prompt');
  @override
  late final GeneratedColumn<String> prompt = GeneratedColumn<String>(
    'prompt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _emojiMeta = const VerificationMeta('emoji');
  @override
  late final GeneratedColumn<String> emoji = GeneratedColumn<String>(
    'emoji',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('🤖'),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('manual'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    prompt,
    description,
    emoji,
    source,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'characters';
  @override
  VerificationContext validateIntegrity(
    Insertable<CharacterRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('prompt')) {
      context.handle(
        _promptMeta,
        prompt.isAcceptableOrUnknown(data['prompt']!, _promptMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('emoji')) {
      context.handle(
        _emojiMeta,
        emoji.isAcceptableOrUnknown(data['emoji']!, _emojiMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CharacterRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CharacterRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      prompt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prompt'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      emoji: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}emoji'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CharactersTable createAlias(String alias) {
    return $CharactersTable(attachedDatabase, alias);
  }
}

class CharacterRow extends DataClass implements Insertable<CharacterRow> {
  final String id;

  /// 角色名（会话列表 / 聊天页顶部展示）。
  final String name;

  /// 人设 / 系统提示（默认模板见 `defaultCharacterPrompt`）。
  final String prompt;

  /// 简介（导入时取首条 user 消息截断；可编辑，可空）。
  final String? description;

  /// 头像文本（一个 emoji；默认 🤖）。
  final String emoji;

  /// `manual` / `import` / `default`。
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;
  const CharacterRow({
    required this.id,
    required this.name,
    required this.prompt,
    this.description,
    required this.emoji,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['prompt'] = Variable<String>(prompt);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['emoji'] = Variable<String>(emoji);
    map['source'] = Variable<String>(source);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CharactersCompanion toCompanion(bool nullToAbsent) {
    return CharactersCompanion(
      id: Value(id),
      name: Value(name),
      prompt: Value(prompt),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      emoji: Value(emoji),
      source: Value(source),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CharacterRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CharacterRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      prompt: serializer.fromJson<String>(json['prompt']),
      description: serializer.fromJson<String?>(json['description']),
      emoji: serializer.fromJson<String>(json['emoji']),
      source: serializer.fromJson<String>(json['source']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'prompt': serializer.toJson<String>(prompt),
      'description': serializer.toJson<String?>(description),
      'emoji': serializer.toJson<String>(emoji),
      'source': serializer.toJson<String>(source),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CharacterRow copyWith({
    String? id,
    String? name,
    String? prompt,
    Value<String?> description = const Value.absent(),
    String? emoji,
    String? source,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => CharacterRow(
    id: id ?? this.id,
    name: name ?? this.name,
    prompt: prompt ?? this.prompt,
    description: description.present ? description.value : this.description,
    emoji: emoji ?? this.emoji,
    source: source ?? this.source,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CharacterRow copyWithCompanion(CharactersCompanion data) {
    return CharacterRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      prompt: data.prompt.present ? data.prompt.value : this.prompt,
      description: data.description.present
          ? data.description.value
          : this.description,
      emoji: data.emoji.present ? data.emoji.value : this.emoji,
      source: data.source.present ? data.source.value : this.source,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CharacterRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('prompt: $prompt, ')
          ..write('description: $description, ')
          ..write('emoji: $emoji, ')
          ..write('source: $source, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    prompt,
    description,
    emoji,
    source,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CharacterRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.prompt == this.prompt &&
          other.description == this.description &&
          other.emoji == this.emoji &&
          other.source == this.source &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CharactersCompanion extends UpdateCompanion<CharacterRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> prompt;
  final Value<String?> description;
  final Value<String> emoji;
  final Value<String> source;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CharactersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.prompt = const Value.absent(),
    this.description = const Value.absent(),
    this.emoji = const Value.absent(),
    this.source = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CharactersCompanion.insert({
    required String id,
    this.name = const Value.absent(),
    this.prompt = const Value.absent(),
    this.description = const Value.absent(),
    this.emoji = const Value.absent(),
    this.source = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<CharacterRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? prompt,
    Expression<String>? description,
    Expression<String>? emoji,
    Expression<String>? source,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (prompt != null) 'prompt': prompt,
      if (description != null) 'description': description,
      if (emoji != null) 'emoji': emoji,
      if (source != null) 'source': source,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CharactersCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? prompt,
    Value<String?>? description,
    Value<String>? emoji,
    Value<String>? source,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CharactersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      prompt: prompt ?? this.prompt,
      description: description ?? this.description,
      emoji: emoji ?? this.emoji,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (prompt.present) {
      map['prompt'] = Variable<String>(prompt.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (emoji.present) {
      map['emoji'] = Variable<String>(emoji.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CharactersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('prompt: $prompt, ')
          ..write('description: $description, ')
          ..write('emoji: $emoji, ')
          ..write('source: $source, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MemoryFactsTable extends MemoryFacts
    with TableInfo<$MemoryFactsTable, MemoryFactRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MemoryFactsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<String> characterId = GeneratedColumn<String>(
    'character_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sideMeta = const VerificationMeta('side');
  @override
  late final GeneratedColumn<String> side = GeneratedColumn<String>(
    'side',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _factTextMeta = const VerificationMeta(
    'factText',
  );
  @override
  late final GeneratedColumn<String> factText = GeneratedColumn<String>(
    'fact_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _weightMeta = const VerificationMeta('weight');
  @override
  late final GeneratedColumn<double> weight = GeneratedColumn<double>(
    'weight',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.5),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  static const VerificationMeta _lastUsedAtMeta = const VerificationMeta(
    'lastUsedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastUsedAt = GeneratedColumn<DateTime>(
    'last_used_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _useCountMeta = const VerificationMeta(
    'useCount',
  );
  @override
  late final GeneratedColumn<int> useCount = GeneratedColumn<int>(
    'use_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    characterId,
    side,
    factText,
    weight,
    createdAt,
    updatedAt,
    lastUsedAt,
    useCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'memory_facts';
  @override
  VerificationContext validateIntegrity(
    Insertable<MemoryFactRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    }
    if (data.containsKey('side')) {
      context.handle(
        _sideMeta,
        side.isAcceptableOrUnknown(data['side']!, _sideMeta),
      );
    } else if (isInserting) {
      context.missing(_sideMeta);
    }
    if (data.containsKey('fact_text')) {
      context.handle(
        _factTextMeta,
        factText.isAcceptableOrUnknown(data['fact_text']!, _factTextMeta),
      );
    }
    if (data.containsKey('weight')) {
      context.handle(
        _weightMeta,
        weight.isAcceptableOrUnknown(data['weight']!, _weightMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    }
    if (data.containsKey('use_count')) {
      context.handle(
        _useCountMeta,
        useCount.isAcceptableOrUnknown(data['use_count']!, _useCountMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MemoryFactRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MemoryFactRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}character_id'],
      )!,
      side: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}side'],
      )!,
      factText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fact_text'],
      )!,
      weight: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weight'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used_at'],
      ),
      useCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}use_count'],
      )!,
    );
  }

  @override
  $MemoryFactsTable createAlias(String alias) {
    return $MemoryFactsTable(attachedDatabase, alias);
  }
}

class MemoryFactRow extends DataClass implements Insertable<MemoryFactRow> {
  final String id;

  /// 所属角色卡（隔离键；`''` = 未绑定角色的历史数据，只有该角色能读到）。
  final String characterId;

  /// `user`（关于用户）/ `self`（关于助手自己）。
  final String side;

  /// 事实文本（`≤60 字`，已归一化掉引号/多余空白）。
  ///
  /// 列名必须是 `fact_text`：getter 叫 `text` 会和 drift 的 `Table.text()` 撞名，
  /// 生成器会递归解析成 `TextColumn` 不可调用。
  final String factText;

  /// 0..1 权重（类型初值 + 重复看到时微增）。
  final double weight;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 最近一次被召回的时间。
  final DateTime? lastUsedAt;
  final int useCount;
  const MemoryFactRow({
    required this.id,
    required this.characterId,
    required this.side,
    required this.factText,
    required this.weight,
    required this.createdAt,
    required this.updatedAt,
    this.lastUsedAt,
    required this.useCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['character_id'] = Variable<String>(characterId);
    map['side'] = Variable<String>(side);
    map['fact_text'] = Variable<String>(factText);
    map['weight'] = Variable<double>(weight);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || lastUsedAt != null) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    }
    map['use_count'] = Variable<int>(useCount);
    return map;
  }

  MemoryFactsCompanion toCompanion(bool nullToAbsent) {
    return MemoryFactsCompanion(
      id: Value(id),
      characterId: Value(characterId),
      side: Value(side),
      factText: Value(factText),
      weight: Value(weight),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      lastUsedAt: lastUsedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUsedAt),
      useCount: Value(useCount),
    );
  }

  factory MemoryFactRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MemoryFactRow(
      id: serializer.fromJson<String>(json['id']),
      characterId: serializer.fromJson<String>(json['characterId']),
      side: serializer.fromJson<String>(json['side']),
      factText: serializer.fromJson<String>(json['factText']),
      weight: serializer.fromJson<double>(json['weight']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      lastUsedAt: serializer.fromJson<DateTime?>(json['lastUsedAt']),
      useCount: serializer.fromJson<int>(json['useCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'characterId': serializer.toJson<String>(characterId),
      'side': serializer.toJson<String>(side),
      'factText': serializer.toJson<String>(factText),
      'weight': serializer.toJson<double>(weight),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'lastUsedAt': serializer.toJson<DateTime?>(lastUsedAt),
      'useCount': serializer.toJson<int>(useCount),
    };
  }

  MemoryFactRow copyWith({
    String? id,
    String? characterId,
    String? side,
    String? factText,
    double? weight,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> lastUsedAt = const Value.absent(),
    int? useCount,
  }) => MemoryFactRow(
    id: id ?? this.id,
    characterId: characterId ?? this.characterId,
    side: side ?? this.side,
    factText: factText ?? this.factText,
    weight: weight ?? this.weight,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastUsedAt: lastUsedAt.present ? lastUsedAt.value : this.lastUsedAt,
    useCount: useCount ?? this.useCount,
  );
  MemoryFactRow copyWithCompanion(MemoryFactsCompanion data) {
    return MemoryFactRow(
      id: data.id.present ? data.id.value : this.id,
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      side: data.side.present ? data.side.value : this.side,
      factText: data.factText.present ? data.factText.value : this.factText,
      weight: data.weight.present ? data.weight.value : this.weight,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
      useCount: data.useCount.present ? data.useCount.value : this.useCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MemoryFactRow(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('side: $side, ')
          ..write('factText: $factText, ')
          ..write('weight: $weight, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('useCount: $useCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    characterId,
    side,
    factText,
    weight,
    createdAt,
    updatedAt,
    lastUsedAt,
    useCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MemoryFactRow &&
          other.id == this.id &&
          other.characterId == this.characterId &&
          other.side == this.side &&
          other.factText == this.factText &&
          other.weight == this.weight &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.lastUsedAt == this.lastUsedAt &&
          other.useCount == this.useCount);
}

class MemoryFactsCompanion extends UpdateCompanion<MemoryFactRow> {
  final Value<String> id;
  final Value<String> characterId;
  final Value<String> side;
  final Value<String> factText;
  final Value<double> weight;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> lastUsedAt;
  final Value<int> useCount;
  final Value<int> rowid;
  const MemoryFactsCompanion({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.side = const Value.absent(),
    this.factText = const Value.absent(),
    this.weight = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.useCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MemoryFactsCompanion.insert({
    required String id,
    this.characterId = const Value.absent(),
    required String side,
    this.factText = const Value.absent(),
    this.weight = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.useCount = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       side = Value(side);
  static Insertable<MemoryFactRow> custom({
    Expression<String>? id,
    Expression<String>? characterId,
    Expression<String>? side,
    Expression<String>? factText,
    Expression<double>? weight,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? lastUsedAt,
    Expression<int>? useCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (characterId != null) 'character_id': characterId,
      if (side != null) 'side': side,
      if (factText != null) 'fact_text': factText,
      if (weight != null) 'weight': weight,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (useCount != null) 'use_count': useCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MemoryFactsCompanion copyWith({
    Value<String>? id,
    Value<String>? characterId,
    Value<String>? side,
    Value<String>? factText,
    Value<double>? weight,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? lastUsedAt,
    Value<int>? useCount,
    Value<int>? rowid,
  }) {
    return MemoryFactsCompanion(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      side: side ?? this.side,
      factText: factText ?? this.factText,
      weight: weight ?? this.weight,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      useCount: useCount ?? this.useCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<String>(characterId.value);
    }
    if (side.present) {
      map['side'] = Variable<String>(side.value);
    }
    if (factText.present) {
      map['fact_text'] = Variable<String>(factText.value);
    }
    if (weight.present) {
      map['weight'] = Variable<double>(weight.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt.value);
    }
    if (useCount.present) {
      map['use_count'] = Variable<int>(useCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MemoryFactsCompanion(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('side: $side, ')
          ..write('factText: $factText, ')
          ..write('weight: $weight, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('useCount: $useCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MemoryEpisodesTable extends MemoryEpisodes
    with TableInfo<$MemoryEpisodesTable, MemoryEpisodeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MemoryEpisodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<String> characterId = GeneratedColumn<String>(
    'character_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _turnIdsJsonMeta = const VerificationMeta(
    'turnIdsJson',
  );
  @override
  late final GeneratedColumn<String> turnIdsJson = GeneratedColumn<String>(
    'turn_ids_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _moodMeta = const VerificationMeta('mood');
  @override
  late final GeneratedColumn<double> mood = GeneratedColumn<double>(
    'mood',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _salienceMeta = const VerificationMeta(
    'salience',
  );
  @override
  late final GeneratedColumn<double> salience = GeneratedColumn<double>(
    'salience',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.5),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  static const VerificationMeta _lastUsedAtMeta = const VerificationMeta(
    'lastUsedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastUsedAt = GeneratedColumn<DateTime>(
    'last_used_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    characterId,
    sessionId,
    turnIdsJson,
    summary,
    mood,
    salience,
    createdAt,
    lastUsedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'memory_episodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<MemoryEpisodeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('turn_ids_json')) {
      context.handle(
        _turnIdsJsonMeta,
        turnIdsJson.isAcceptableOrUnknown(
          data['turn_ids_json']!,
          _turnIdsJsonMeta,
        ),
      );
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    }
    if (data.containsKey('mood')) {
      context.handle(
        _moodMeta,
        mood.isAcceptableOrUnknown(data['mood']!, _moodMeta),
      );
    }
    if (data.containsKey('salience')) {
      context.handle(
        _salienceMeta,
        salience.isAcceptableOrUnknown(data['salience']!, _salienceMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MemoryEpisodeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MemoryEpisodeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}character_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      turnIdsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}turn_ids_json'],
      )!,
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      )!,
      mood: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}mood'],
      ),
      salience: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}salience'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used_at'],
      ),
    );
  }

  @override
  $MemoryEpisodesTable createAlias(String alias) {
    return $MemoryEpisodesTable(attachedDatabase, alias);
  }
}

class MemoryEpisodeRow extends DataClass
    implements Insertable<MemoryEpisodeRow> {
  final String id;

  /// 所属角色卡（隔离键）。
  final String characterId;
  final String sessionId;

  /// 涉及的原文消息 id（JSON 数组；原文仍在 `messages` 表里）。
  final String turnIdsJson;

  /// `≤160 字`的小摘要（user 主句 + assistant 首句）。
  final String summary;

  /// 当时的用户心情值（0..1，可空）。
  final double? mood;

  /// 0..1 重要度。
  final double salience;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  const MemoryEpisodeRow({
    required this.id,
    required this.characterId,
    required this.sessionId,
    required this.turnIdsJson,
    required this.summary,
    this.mood,
    required this.salience,
    required this.createdAt,
    this.lastUsedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['character_id'] = Variable<String>(characterId);
    map['session_id'] = Variable<String>(sessionId);
    map['turn_ids_json'] = Variable<String>(turnIdsJson);
    map['summary'] = Variable<String>(summary);
    if (!nullToAbsent || mood != null) {
      map['mood'] = Variable<double>(mood);
    }
    map['salience'] = Variable<double>(salience);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastUsedAt != null) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    }
    return map;
  }

  MemoryEpisodesCompanion toCompanion(bool nullToAbsent) {
    return MemoryEpisodesCompanion(
      id: Value(id),
      characterId: Value(characterId),
      sessionId: Value(sessionId),
      turnIdsJson: Value(turnIdsJson),
      summary: Value(summary),
      mood: mood == null && nullToAbsent ? const Value.absent() : Value(mood),
      salience: Value(salience),
      createdAt: Value(createdAt),
      lastUsedAt: lastUsedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUsedAt),
    );
  }

  factory MemoryEpisodeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MemoryEpisodeRow(
      id: serializer.fromJson<String>(json['id']),
      characterId: serializer.fromJson<String>(json['characterId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      turnIdsJson: serializer.fromJson<String>(json['turnIdsJson']),
      summary: serializer.fromJson<String>(json['summary']),
      mood: serializer.fromJson<double?>(json['mood']),
      salience: serializer.fromJson<double>(json['salience']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastUsedAt: serializer.fromJson<DateTime?>(json['lastUsedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'characterId': serializer.toJson<String>(characterId),
      'sessionId': serializer.toJson<String>(sessionId),
      'turnIdsJson': serializer.toJson<String>(turnIdsJson),
      'summary': serializer.toJson<String>(summary),
      'mood': serializer.toJson<double?>(mood),
      'salience': serializer.toJson<double>(salience),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastUsedAt': serializer.toJson<DateTime?>(lastUsedAt),
    };
  }

  MemoryEpisodeRow copyWith({
    String? id,
    String? characterId,
    String? sessionId,
    String? turnIdsJson,
    String? summary,
    Value<double?> mood = const Value.absent(),
    double? salience,
    DateTime? createdAt,
    Value<DateTime?> lastUsedAt = const Value.absent(),
  }) => MemoryEpisodeRow(
    id: id ?? this.id,
    characterId: characterId ?? this.characterId,
    sessionId: sessionId ?? this.sessionId,
    turnIdsJson: turnIdsJson ?? this.turnIdsJson,
    summary: summary ?? this.summary,
    mood: mood.present ? mood.value : this.mood,
    salience: salience ?? this.salience,
    createdAt: createdAt ?? this.createdAt,
    lastUsedAt: lastUsedAt.present ? lastUsedAt.value : this.lastUsedAt,
  );
  MemoryEpisodeRow copyWithCompanion(MemoryEpisodesCompanion data) {
    return MemoryEpisodeRow(
      id: data.id.present ? data.id.value : this.id,
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      turnIdsJson: data.turnIdsJson.present
          ? data.turnIdsJson.value
          : this.turnIdsJson,
      summary: data.summary.present ? data.summary.value : this.summary,
      mood: data.mood.present ? data.mood.value : this.mood,
      salience: data.salience.present ? data.salience.value : this.salience,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MemoryEpisodeRow(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('sessionId: $sessionId, ')
          ..write('turnIdsJson: $turnIdsJson, ')
          ..write('summary: $summary, ')
          ..write('mood: $mood, ')
          ..write('salience: $salience, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastUsedAt: $lastUsedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    characterId,
    sessionId,
    turnIdsJson,
    summary,
    mood,
    salience,
    createdAt,
    lastUsedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MemoryEpisodeRow &&
          other.id == this.id &&
          other.characterId == this.characterId &&
          other.sessionId == this.sessionId &&
          other.turnIdsJson == this.turnIdsJson &&
          other.summary == this.summary &&
          other.mood == this.mood &&
          other.salience == this.salience &&
          other.createdAt == this.createdAt &&
          other.lastUsedAt == this.lastUsedAt);
}

class MemoryEpisodesCompanion extends UpdateCompanion<MemoryEpisodeRow> {
  final Value<String> id;
  final Value<String> characterId;
  final Value<String> sessionId;
  final Value<String> turnIdsJson;
  final Value<String> summary;
  final Value<double?> mood;
  final Value<double> salience;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastUsedAt;
  final Value<int> rowid;
  const MemoryEpisodesCompanion({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.turnIdsJson = const Value.absent(),
    this.summary = const Value.absent(),
    this.mood = const Value.absent(),
    this.salience = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MemoryEpisodesCompanion.insert({
    required String id,
    this.characterId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.turnIdsJson = const Value.absent(),
    this.summary = const Value.absent(),
    this.mood = const Value.absent(),
    this.salience = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<MemoryEpisodeRow> custom({
    Expression<String>? id,
    Expression<String>? characterId,
    Expression<String>? sessionId,
    Expression<String>? turnIdsJson,
    Expression<String>? summary,
    Expression<double>? mood,
    Expression<double>? salience,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastUsedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (characterId != null) 'character_id': characterId,
      if (sessionId != null) 'session_id': sessionId,
      if (turnIdsJson != null) 'turn_ids_json': turnIdsJson,
      if (summary != null) 'summary': summary,
      if (mood != null) 'mood': mood,
      if (salience != null) 'salience': salience,
      if (createdAt != null) 'created_at': createdAt,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MemoryEpisodesCompanion copyWith({
    Value<String>? id,
    Value<String>? characterId,
    Value<String>? sessionId,
    Value<String>? turnIdsJson,
    Value<String>? summary,
    Value<double?>? mood,
    Value<double>? salience,
    Value<DateTime>? createdAt,
    Value<DateTime?>? lastUsedAt,
    Value<int>? rowid,
  }) {
    return MemoryEpisodesCompanion(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      sessionId: sessionId ?? this.sessionId,
      turnIdsJson: turnIdsJson ?? this.turnIdsJson,
      summary: summary ?? this.summary,
      mood: mood ?? this.mood,
      salience: salience ?? this.salience,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<String>(characterId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (turnIdsJson.present) {
      map['turn_ids_json'] = Variable<String>(turnIdsJson.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (mood.present) {
      map['mood'] = Variable<double>(mood.value);
    }
    if (salience.present) {
      map['salience'] = Variable<double>(salience.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MemoryEpisodesCompanion(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('sessionId: $sessionId, ')
          ..write('turnIdsJson: $turnIdsJson, ')
          ..write('summary: $summary, ')
          ..write('mood: $mood, ')
          ..write('salience: $salience, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MemoryRecallStatsTable extends MemoryRecallStats
    with TableInfo<$MemoryRecallStatsTable, MemoryRecallStatRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MemoryRecallStatsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _memoryIdMeta = const VerificationMeta(
    'memoryId',
  );
  @override
  late final GeneratedColumn<String> memoryId = GeneratedColumn<String>(
    'memory_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<String> characterId = GeneratedColumn<String>(
    'character_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _injectedMeta = const VerificationMeta(
    'injected',
  );
  @override
  late final GeneratedColumn<int> injected = GeneratedColumn<int>(
    'injected',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _usedMeta = const VerificationMeta('used');
  @override
  late final GeneratedColumn<int> used = GeneratedColumn<int>(
    'used',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ignoredMeta = const VerificationMeta(
    'ignored',
  );
  @override
  late final GeneratedColumn<int> ignored = GeneratedColumn<int>(
    'ignored',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _usefulnessMeta = const VerificationMeta(
    'usefulness',
  );
  @override
  late final GeneratedColumn<double> usefulness = GeneratedColumn<double>(
    'usefulness',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.5),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  @override
  List<GeneratedColumn> get $columns => [
    kind,
    memoryId,
    characterId,
    injected,
    used,
    ignored,
    usefulness,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'memory_recall_stats';
  @override
  VerificationContext validateIntegrity(
    Insertable<MemoryRecallStatRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('memory_id')) {
      context.handle(
        _memoryIdMeta,
        memoryId.isAcceptableOrUnknown(data['memory_id']!, _memoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_memoryIdMeta);
    }
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    }
    if (data.containsKey('injected')) {
      context.handle(
        _injectedMeta,
        injected.isAcceptableOrUnknown(data['injected']!, _injectedMeta),
      );
    }
    if (data.containsKey('used')) {
      context.handle(
        _usedMeta,
        used.isAcceptableOrUnknown(data['used']!, _usedMeta),
      );
    }
    if (data.containsKey('ignored')) {
      context.handle(
        _ignoredMeta,
        ignored.isAcceptableOrUnknown(data['ignored']!, _ignoredMeta),
      );
    }
    if (data.containsKey('usefulness')) {
      context.handle(
        _usefulnessMeta,
        usefulness.isAcceptableOrUnknown(data['usefulness']!, _usefulnessMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {kind, memoryId};
  @override
  MemoryRecallStatRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MemoryRecallStatRow(
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      memoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}memory_id'],
      )!,
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}character_id'],
      )!,
      injected: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}injected'],
      )!,
      used: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}used'],
      )!,
      ignored: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ignored'],
      )!,
      usefulness: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}usefulness'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MemoryRecallStatsTable createAlias(String alias) {
    return $MemoryRecallStatsTable(attachedDatabase, alias);
  }
}

class MemoryRecallStatRow extends DataClass
    implements Insertable<MemoryRecallStatRow> {
  /// `turn` / `fact` / `episode`。
  final String kind;

  /// 对应记忆 id（消息 id / 事实 id / episode id）。
  final String memoryId;

  /// 所属角色卡（隔离键）。
  final String characterId;
  final int injected;
  final int used;
  final int ignored;

  /// 0..1 有用度（`used / injected` 的平滑值）。
  final double usefulness;
  final DateTime updatedAt;
  const MemoryRecallStatRow({
    required this.kind,
    required this.memoryId,
    required this.characterId,
    required this.injected,
    required this.used,
    required this.ignored,
    required this.usefulness,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['kind'] = Variable<String>(kind);
    map['memory_id'] = Variable<String>(memoryId);
    map['character_id'] = Variable<String>(characterId);
    map['injected'] = Variable<int>(injected);
    map['used'] = Variable<int>(used);
    map['ignored'] = Variable<int>(ignored);
    map['usefulness'] = Variable<double>(usefulness);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  MemoryRecallStatsCompanion toCompanion(bool nullToAbsent) {
    return MemoryRecallStatsCompanion(
      kind: Value(kind),
      memoryId: Value(memoryId),
      characterId: Value(characterId),
      injected: Value(injected),
      used: Value(used),
      ignored: Value(ignored),
      usefulness: Value(usefulness),
      updatedAt: Value(updatedAt),
    );
  }

  factory MemoryRecallStatRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MemoryRecallStatRow(
      kind: serializer.fromJson<String>(json['kind']),
      memoryId: serializer.fromJson<String>(json['memoryId']),
      characterId: serializer.fromJson<String>(json['characterId']),
      injected: serializer.fromJson<int>(json['injected']),
      used: serializer.fromJson<int>(json['used']),
      ignored: serializer.fromJson<int>(json['ignored']),
      usefulness: serializer.fromJson<double>(json['usefulness']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'kind': serializer.toJson<String>(kind),
      'memoryId': serializer.toJson<String>(memoryId),
      'characterId': serializer.toJson<String>(characterId),
      'injected': serializer.toJson<int>(injected),
      'used': serializer.toJson<int>(used),
      'ignored': serializer.toJson<int>(ignored),
      'usefulness': serializer.toJson<double>(usefulness),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  MemoryRecallStatRow copyWith({
    String? kind,
    String? memoryId,
    String? characterId,
    int? injected,
    int? used,
    int? ignored,
    double? usefulness,
    DateTime? updatedAt,
  }) => MemoryRecallStatRow(
    kind: kind ?? this.kind,
    memoryId: memoryId ?? this.memoryId,
    characterId: characterId ?? this.characterId,
    injected: injected ?? this.injected,
    used: used ?? this.used,
    ignored: ignored ?? this.ignored,
    usefulness: usefulness ?? this.usefulness,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  MemoryRecallStatRow copyWithCompanion(MemoryRecallStatsCompanion data) {
    return MemoryRecallStatRow(
      kind: data.kind.present ? data.kind.value : this.kind,
      memoryId: data.memoryId.present ? data.memoryId.value : this.memoryId,
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      injected: data.injected.present ? data.injected.value : this.injected,
      used: data.used.present ? data.used.value : this.used,
      ignored: data.ignored.present ? data.ignored.value : this.ignored,
      usefulness: data.usefulness.present
          ? data.usefulness.value
          : this.usefulness,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MemoryRecallStatRow(')
          ..write('kind: $kind, ')
          ..write('memoryId: $memoryId, ')
          ..write('characterId: $characterId, ')
          ..write('injected: $injected, ')
          ..write('used: $used, ')
          ..write('ignored: $ignored, ')
          ..write('usefulness: $usefulness, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    kind,
    memoryId,
    characterId,
    injected,
    used,
    ignored,
    usefulness,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MemoryRecallStatRow &&
          other.kind == this.kind &&
          other.memoryId == this.memoryId &&
          other.characterId == this.characterId &&
          other.injected == this.injected &&
          other.used == this.used &&
          other.ignored == this.ignored &&
          other.usefulness == this.usefulness &&
          other.updatedAt == this.updatedAt);
}

class MemoryRecallStatsCompanion extends UpdateCompanion<MemoryRecallStatRow> {
  final Value<String> kind;
  final Value<String> memoryId;
  final Value<String> characterId;
  final Value<int> injected;
  final Value<int> used;
  final Value<int> ignored;
  final Value<double> usefulness;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const MemoryRecallStatsCompanion({
    this.kind = const Value.absent(),
    this.memoryId = const Value.absent(),
    this.characterId = const Value.absent(),
    this.injected = const Value.absent(),
    this.used = const Value.absent(),
    this.ignored = const Value.absent(),
    this.usefulness = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MemoryRecallStatsCompanion.insert({
    required String kind,
    required String memoryId,
    this.characterId = const Value.absent(),
    this.injected = const Value.absent(),
    this.used = const Value.absent(),
    this.ignored = const Value.absent(),
    this.usefulness = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : kind = Value(kind),
       memoryId = Value(memoryId);
  static Insertable<MemoryRecallStatRow> custom({
    Expression<String>? kind,
    Expression<String>? memoryId,
    Expression<String>? characterId,
    Expression<int>? injected,
    Expression<int>? used,
    Expression<int>? ignored,
    Expression<double>? usefulness,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (kind != null) 'kind': kind,
      if (memoryId != null) 'memory_id': memoryId,
      if (characterId != null) 'character_id': characterId,
      if (injected != null) 'injected': injected,
      if (used != null) 'used': used,
      if (ignored != null) 'ignored': ignored,
      if (usefulness != null) 'usefulness': usefulness,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MemoryRecallStatsCompanion copyWith({
    Value<String>? kind,
    Value<String>? memoryId,
    Value<String>? characterId,
    Value<int>? injected,
    Value<int>? used,
    Value<int>? ignored,
    Value<double>? usefulness,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return MemoryRecallStatsCompanion(
      kind: kind ?? this.kind,
      memoryId: memoryId ?? this.memoryId,
      characterId: characterId ?? this.characterId,
      injected: injected ?? this.injected,
      used: used ?? this.used,
      ignored: ignored ?? this.ignored,
      usefulness: usefulness ?? this.usefulness,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (memoryId.present) {
      map['memory_id'] = Variable<String>(memoryId.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<String>(characterId.value);
    }
    if (injected.present) {
      map['injected'] = Variable<int>(injected.value);
    }
    if (used.present) {
      map['used'] = Variable<int>(used.value);
    }
    if (ignored.present) {
      map['ignored'] = Variable<int>(ignored.value);
    }
    if (usefulness.present) {
      map['usefulness'] = Variable<double>(usefulness.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MemoryRecallStatsCompanion(')
          ..write('kind: $kind, ')
          ..write('memoryId: $memoryId, ')
          ..write('characterId: $characterId, ')
          ..write('injected: $injected, ')
          ..write('used: $used, ')
          ..write('ignored: $ignored, ')
          ..write('usefulness: $usefulness, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MoodStatesTable extends MoodStates
    with TableInfo<$MoodStatesTable, MoodStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MoodStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<String> characterId = GeneratedColumn<String>(
    'character_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('平静'),
  );
  static const VerificationMeta _valenceMeta = const VerificationMeta(
    'valence',
  );
  @override
  late final GeneratedColumn<double> valence = GeneratedColumn<double>(
    'valence',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.58),
  );
  static const VerificationMeta _affectionMeta = const VerificationMeta(
    'affection',
  );
  @override
  late final GeneratedColumn<double> affection = GeneratedColumn<double>(
    'affection',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.45),
  );
  static const VerificationMeta _energyMeta = const VerificationMeta('energy');
  @override
  late final GeneratedColumn<double> energy = GeneratedColumn<double>(
    'energy',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.6),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  @override
  List<GeneratedColumn> get $columns => [
    characterId,
    name,
    valence,
    affection,
    energy,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mood_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<MoodStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_characterIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('valence')) {
      context.handle(
        _valenceMeta,
        valence.isAcceptableOrUnknown(data['valence']!, _valenceMeta),
      );
    }
    if (data.containsKey('affection')) {
      context.handle(
        _affectionMeta,
        affection.isAcceptableOrUnknown(data['affection']!, _affectionMeta),
      );
    }
    if (data.containsKey('energy')) {
      context.handle(
        _energyMeta,
        energy.isAcceptableOrUnknown(data['energy']!, _energyMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {characterId};
  @override
  MoodStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MoodStateRow(
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}character_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      valence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}valence'],
      )!,
      affection: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}affection'],
      )!,
      energy: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}energy'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MoodStatesTable createAlias(String alias) {
    return $MoodStatesTable(attachedDatabase, alias);
  }
}

class MoodStateRow extends DataClass implements Insertable<MoodStateRow> {
  /// 角色卡 id（一个角色一行，所以它同时是主键）。
  final String characterId;

  /// 一句状态（「平静」「专注」「心疼」…）。
  final String name;
  final double valence;
  final double affection;
  final double energy;
  final DateTime updatedAt;
  const MoodStateRow({
    required this.characterId,
    required this.name,
    required this.valence,
    required this.affection,
    required this.energy,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['character_id'] = Variable<String>(characterId);
    map['name'] = Variable<String>(name);
    map['valence'] = Variable<double>(valence);
    map['affection'] = Variable<double>(affection);
    map['energy'] = Variable<double>(energy);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  MoodStatesCompanion toCompanion(bool nullToAbsent) {
    return MoodStatesCompanion(
      characterId: Value(characterId),
      name: Value(name),
      valence: Value(valence),
      affection: Value(affection),
      energy: Value(energy),
      updatedAt: Value(updatedAt),
    );
  }

  factory MoodStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MoodStateRow(
      characterId: serializer.fromJson<String>(json['characterId']),
      name: serializer.fromJson<String>(json['name']),
      valence: serializer.fromJson<double>(json['valence']),
      affection: serializer.fromJson<double>(json['affection']),
      energy: serializer.fromJson<double>(json['energy']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'characterId': serializer.toJson<String>(characterId),
      'name': serializer.toJson<String>(name),
      'valence': serializer.toJson<double>(valence),
      'affection': serializer.toJson<double>(affection),
      'energy': serializer.toJson<double>(energy),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  MoodStateRow copyWith({
    String? characterId,
    String? name,
    double? valence,
    double? affection,
    double? energy,
    DateTime? updatedAt,
  }) => MoodStateRow(
    characterId: characterId ?? this.characterId,
    name: name ?? this.name,
    valence: valence ?? this.valence,
    affection: affection ?? this.affection,
    energy: energy ?? this.energy,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  MoodStateRow copyWithCompanion(MoodStatesCompanion data) {
    return MoodStateRow(
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      name: data.name.present ? data.name.value : this.name,
      valence: data.valence.present ? data.valence.value : this.valence,
      affection: data.affection.present ? data.affection.value : this.affection,
      energy: data.energy.present ? data.energy.value : this.energy,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MoodStateRow(')
          ..write('characterId: $characterId, ')
          ..write('name: $name, ')
          ..write('valence: $valence, ')
          ..write('affection: $affection, ')
          ..write('energy: $energy, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(characterId, name, valence, affection, energy, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MoodStateRow &&
          other.characterId == this.characterId &&
          other.name == this.name &&
          other.valence == this.valence &&
          other.affection == this.affection &&
          other.energy == this.energy &&
          other.updatedAt == this.updatedAt);
}

class MoodStatesCompanion extends UpdateCompanion<MoodStateRow> {
  final Value<String> characterId;
  final Value<String> name;
  final Value<double> valence;
  final Value<double> affection;
  final Value<double> energy;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const MoodStatesCompanion({
    this.characterId = const Value.absent(),
    this.name = const Value.absent(),
    this.valence = const Value.absent(),
    this.affection = const Value.absent(),
    this.energy = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MoodStatesCompanion.insert({
    required String characterId,
    this.name = const Value.absent(),
    this.valence = const Value.absent(),
    this.affection = const Value.absent(),
    this.energy = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : characterId = Value(characterId);
  static Insertable<MoodStateRow> custom({
    Expression<String>? characterId,
    Expression<String>? name,
    Expression<double>? valence,
    Expression<double>? affection,
    Expression<double>? energy,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (characterId != null) 'character_id': characterId,
      if (name != null) 'name': name,
      if (valence != null) 'valence': valence,
      if (affection != null) 'affection': affection,
      if (energy != null) 'energy': energy,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MoodStatesCompanion copyWith({
    Value<String>? characterId,
    Value<String>? name,
    Value<double>? valence,
    Value<double>? affection,
    Value<double>? energy,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return MoodStatesCompanion(
      characterId: characterId ?? this.characterId,
      name: name ?? this.name,
      valence: valence ?? this.valence,
      affection: affection ?? this.affection,
      energy: energy ?? this.energy,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (characterId.present) {
      map['character_id'] = Variable<String>(characterId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (valence.present) {
      map['valence'] = Variable<double>(valence.value);
    }
    if (affection.present) {
      map['affection'] = Variable<double>(affection.value);
    }
    if (energy.present) {
      map['energy'] = Variable<double>(energy.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MoodStatesCompanion(')
          ..write('characterId: $characterId, ')
          ..write('name: $name, ')
          ..write('valence: $valence, ')
          ..write('affection: $affection, ')
          ..write('energy: $energy, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MoodHistoryTable extends MoodHistory
    with TableInfo<$MoodHistoryTable, MoodHistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MoodHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<String> characterId = GeneratedColumn<String>(
    'character_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('平静'),
  );
  static const VerificationMeta _valenceMeta = const VerificationMeta(
    'valence',
  );
  @override
  late final GeneratedColumn<double> valence = GeneratedColumn<double>(
    'valence',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.58),
  );
  static const VerificationMeta _affectionMeta = const VerificationMeta(
    'affection',
  );
  @override
  late final GeneratedColumn<double> affection = GeneratedColumn<double>(
    'affection',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.45),
  );
  static const VerificationMeta _energyMeta = const VerificationMeta('energy');
  @override
  late final GeneratedColumn<double> energy = GeneratedColumn<double>(
    'energy',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.6),
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    characterId,
    name,
    valence,
    affection,
    energy,
    reason,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mood_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<MoodHistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('valence')) {
      context.handle(
        _valenceMeta,
        valence.isAcceptableOrUnknown(data['valence']!, _valenceMeta),
      );
    }
    if (data.containsKey('affection')) {
      context.handle(
        _affectionMeta,
        affection.isAcceptableOrUnknown(data['affection']!, _affectionMeta),
      );
    }
    if (data.containsKey('energy')) {
      context.handle(
        _energyMeta,
        energy.isAcceptableOrUnknown(data['energy']!, _energyMeta),
      );
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MoodHistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MoodHistoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}character_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      valence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}valence'],
      )!,
      affection: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}affection'],
      )!,
      energy: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}energy'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $MoodHistoryTable createAlias(String alias) {
    return $MoodHistoryTable(attachedDatabase, alias);
  }
}

class MoodHistoryRow extends DataClass implements Insertable<MoodHistoryRow> {
  final int id;

  /// 所属角色卡（隔离键）。
  final String characterId;
  final String name;
  final double valence;
  final double affection;
  final double energy;

  /// 触发原因（`tired+decay` 之类）。
  final String reason;
  final DateTime createdAt;
  const MoodHistoryRow({
    required this.id,
    required this.characterId,
    required this.name,
    required this.valence,
    required this.affection,
    required this.energy,
    required this.reason,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['character_id'] = Variable<String>(characterId);
    map['name'] = Variable<String>(name);
    map['valence'] = Variable<double>(valence);
    map['affection'] = Variable<double>(affection);
    map['energy'] = Variable<double>(energy);
    map['reason'] = Variable<String>(reason);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MoodHistoryCompanion toCompanion(bool nullToAbsent) {
    return MoodHistoryCompanion(
      id: Value(id),
      characterId: Value(characterId),
      name: Value(name),
      valence: Value(valence),
      affection: Value(affection),
      energy: Value(energy),
      reason: Value(reason),
      createdAt: Value(createdAt),
    );
  }

  factory MoodHistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MoodHistoryRow(
      id: serializer.fromJson<int>(json['id']),
      characterId: serializer.fromJson<String>(json['characterId']),
      name: serializer.fromJson<String>(json['name']),
      valence: serializer.fromJson<double>(json['valence']),
      affection: serializer.fromJson<double>(json['affection']),
      energy: serializer.fromJson<double>(json['energy']),
      reason: serializer.fromJson<String>(json['reason']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'characterId': serializer.toJson<String>(characterId),
      'name': serializer.toJson<String>(name),
      'valence': serializer.toJson<double>(valence),
      'affection': serializer.toJson<double>(affection),
      'energy': serializer.toJson<double>(energy),
      'reason': serializer.toJson<String>(reason),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  MoodHistoryRow copyWith({
    int? id,
    String? characterId,
    String? name,
    double? valence,
    double? affection,
    double? energy,
    String? reason,
    DateTime? createdAt,
  }) => MoodHistoryRow(
    id: id ?? this.id,
    characterId: characterId ?? this.characterId,
    name: name ?? this.name,
    valence: valence ?? this.valence,
    affection: affection ?? this.affection,
    energy: energy ?? this.energy,
    reason: reason ?? this.reason,
    createdAt: createdAt ?? this.createdAt,
  );
  MoodHistoryRow copyWithCompanion(MoodHistoryCompanion data) {
    return MoodHistoryRow(
      id: data.id.present ? data.id.value : this.id,
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      name: data.name.present ? data.name.value : this.name,
      valence: data.valence.present ? data.valence.value : this.valence,
      affection: data.affection.present ? data.affection.value : this.affection,
      energy: data.energy.present ? data.energy.value : this.energy,
      reason: data.reason.present ? data.reason.value : this.reason,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MoodHistoryRow(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('name: $name, ')
          ..write('valence: $valence, ')
          ..write('affection: $affection, ')
          ..write('energy: $energy, ')
          ..write('reason: $reason, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    characterId,
    name,
    valence,
    affection,
    energy,
    reason,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MoodHistoryRow &&
          other.id == this.id &&
          other.characterId == this.characterId &&
          other.name == this.name &&
          other.valence == this.valence &&
          other.affection == this.affection &&
          other.energy == this.energy &&
          other.reason == this.reason &&
          other.createdAt == this.createdAt);
}

class MoodHistoryCompanion extends UpdateCompanion<MoodHistoryRow> {
  final Value<int> id;
  final Value<String> characterId;
  final Value<String> name;
  final Value<double> valence;
  final Value<double> affection;
  final Value<double> energy;
  final Value<String> reason;
  final Value<DateTime> createdAt;
  const MoodHistoryCompanion({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.name = const Value.absent(),
    this.valence = const Value.absent(),
    this.affection = const Value.absent(),
    this.energy = const Value.absent(),
    this.reason = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  MoodHistoryCompanion.insert({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.name = const Value.absent(),
    this.valence = const Value.absent(),
    this.affection = const Value.absent(),
    this.energy = const Value.absent(),
    this.reason = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  static Insertable<MoodHistoryRow> custom({
    Expression<int>? id,
    Expression<String>? characterId,
    Expression<String>? name,
    Expression<double>? valence,
    Expression<double>? affection,
    Expression<double>? energy,
    Expression<String>? reason,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (characterId != null) 'character_id': characterId,
      if (name != null) 'name': name,
      if (valence != null) 'valence': valence,
      if (affection != null) 'affection': affection,
      if (energy != null) 'energy': energy,
      if (reason != null) 'reason': reason,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  MoodHistoryCompanion copyWith({
    Value<int>? id,
    Value<String>? characterId,
    Value<String>? name,
    Value<double>? valence,
    Value<double>? affection,
    Value<double>? energy,
    Value<String>? reason,
    Value<DateTime>? createdAt,
  }) {
    return MoodHistoryCompanion(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      name: name ?? this.name,
      valence: valence ?? this.valence,
      affection: affection ?? this.affection,
      energy: energy ?? this.energy,
      reason: reason ?? this.reason,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<String>(characterId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (valence.present) {
      map['valence'] = Variable<double>(valence.value);
    }
    if (affection.present) {
      map['affection'] = Variable<double>(affection.value);
    }
    if (energy.present) {
      map['energy'] = Variable<double>(energy.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MoodHistoryCompanion(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('name: $name, ')
          ..write('valence: $valence, ')
          ..write('affection: $affection, ')
          ..write('energy: $energy, ')
          ..write('reason: $reason, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $PersonaTraitRowsTable extends PersonaTraitRows
    with TableInfo<$PersonaTraitRowsTable, PersonaTraitRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PersonaTraitRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<String> characterId = GeneratedColumn<String>(
    'character_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sideMeta = const VerificationMeta('side');
  @override
  late final GeneratedColumn<String> side = GeneratedColumn<String>(
    'side',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<double> value = GeneratedColumn<double>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.5),
  );
  static const VerificationMeta _baselineMeta = const VerificationMeta(
    'baseline',
  );
  @override
  late final GeneratedColumn<double> baseline = GeneratedColumn<double>(
    'baseline',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.5),
  );
  static const VerificationMeta _hitCountMeta = const VerificationMeta(
    'hitCount',
  );
  @override
  late final GeneratedColumn<int> hitCount = GeneratedColumn<int>(
    'hit_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  @override
  List<GeneratedColumn> get $columns => [
    characterId,
    side,
    key,
    value,
    baseline,
    hitCount,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'persona_traits';
  @override
  VerificationContext validateIntegrity(
    Insertable<PersonaTraitRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    }
    if (data.containsKey('side')) {
      context.handle(
        _sideMeta,
        side.isAcceptableOrUnknown(data['side']!, _sideMeta),
      );
    } else if (isInserting) {
      context.missing(_sideMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    if (data.containsKey('baseline')) {
      context.handle(
        _baselineMeta,
        baseline.isAcceptableOrUnknown(data['baseline']!, _baselineMeta),
      );
    }
    if (data.containsKey('hit_count')) {
      context.handle(
        _hitCountMeta,
        hitCount.isAcceptableOrUnknown(data['hit_count']!, _hitCountMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {characterId, side, key};
  @override
  PersonaTraitRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PersonaTraitRow(
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}character_id'],
      )!,
      side: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}side'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}value'],
      )!,
      baseline: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}baseline'],
      )!,
      hitCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hit_count'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PersonaTraitRowsTable createAlias(String alias) {
    return $PersonaTraitRowsTable(attachedDatabase, alias);
  }
}

class PersonaTraitRow extends DataClass implements Insertable<PersonaTraitRow> {
  /// 所属角色卡（隔离键，进主键）。
  final String characterId;

  /// `user` / `self`。
  final String side;

  /// 倾向键（`directness` / `warmth` …）。
  final String key;

  /// 0..1 当前值。
  final double value;

  /// 0..1 基线（按天回归到这里）。
  final double baseline;
  final int hitCount;
  final DateTime updatedAt;
  const PersonaTraitRow({
    required this.characterId,
    required this.side,
    required this.key,
    required this.value,
    required this.baseline,
    required this.hitCount,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['character_id'] = Variable<String>(characterId);
    map['side'] = Variable<String>(side);
    map['key'] = Variable<String>(key);
    map['value'] = Variable<double>(value);
    map['baseline'] = Variable<double>(baseline);
    map['hit_count'] = Variable<int>(hitCount);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PersonaTraitRowsCompanion toCompanion(bool nullToAbsent) {
    return PersonaTraitRowsCompanion(
      characterId: Value(characterId),
      side: Value(side),
      key: Value(key),
      value: Value(value),
      baseline: Value(baseline),
      hitCount: Value(hitCount),
      updatedAt: Value(updatedAt),
    );
  }

  factory PersonaTraitRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PersonaTraitRow(
      characterId: serializer.fromJson<String>(json['characterId']),
      side: serializer.fromJson<String>(json['side']),
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<double>(json['value']),
      baseline: serializer.fromJson<double>(json['baseline']),
      hitCount: serializer.fromJson<int>(json['hitCount']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'characterId': serializer.toJson<String>(characterId),
      'side': serializer.toJson<String>(side),
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<double>(value),
      'baseline': serializer.toJson<double>(baseline),
      'hitCount': serializer.toJson<int>(hitCount),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PersonaTraitRow copyWith({
    String? characterId,
    String? side,
    String? key,
    double? value,
    double? baseline,
    int? hitCount,
    DateTime? updatedAt,
  }) => PersonaTraitRow(
    characterId: characterId ?? this.characterId,
    side: side ?? this.side,
    key: key ?? this.key,
    value: value ?? this.value,
    baseline: baseline ?? this.baseline,
    hitCount: hitCount ?? this.hitCount,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PersonaTraitRow copyWithCompanion(PersonaTraitRowsCompanion data) {
    return PersonaTraitRow(
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      side: data.side.present ? data.side.value : this.side,
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      baseline: data.baseline.present ? data.baseline.value : this.baseline,
      hitCount: data.hitCount.present ? data.hitCount.value : this.hitCount,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PersonaTraitRow(')
          ..write('characterId: $characterId, ')
          ..write('side: $side, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('baseline: $baseline, ')
          ..write('hitCount: $hitCount, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(characterId, side, key, value, baseline, hitCount, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PersonaTraitRow &&
          other.characterId == this.characterId &&
          other.side == this.side &&
          other.key == this.key &&
          other.value == this.value &&
          other.baseline == this.baseline &&
          other.hitCount == this.hitCount &&
          other.updatedAt == this.updatedAt);
}

class PersonaTraitRowsCompanion extends UpdateCompanion<PersonaTraitRow> {
  final Value<String> characterId;
  final Value<String> side;
  final Value<String> key;
  final Value<double> value;
  final Value<double> baseline;
  final Value<int> hitCount;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PersonaTraitRowsCompanion({
    this.characterId = const Value.absent(),
    this.side = const Value.absent(),
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.baseline = const Value.absent(),
    this.hitCount = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PersonaTraitRowsCompanion.insert({
    this.characterId = const Value.absent(),
    required String side,
    required String key,
    this.value = const Value.absent(),
    this.baseline = const Value.absent(),
    this.hitCount = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : side = Value(side),
       key = Value(key);
  static Insertable<PersonaTraitRow> custom({
    Expression<String>? characterId,
    Expression<String>? side,
    Expression<String>? key,
    Expression<double>? value,
    Expression<double>? baseline,
    Expression<int>? hitCount,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (characterId != null) 'character_id': characterId,
      if (side != null) 'side': side,
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (baseline != null) 'baseline': baseline,
      if (hitCount != null) 'hit_count': hitCount,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PersonaTraitRowsCompanion copyWith({
    Value<String>? characterId,
    Value<String>? side,
    Value<String>? key,
    Value<double>? value,
    Value<double>? baseline,
    Value<int>? hitCount,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return PersonaTraitRowsCompanion(
      characterId: characterId ?? this.characterId,
      side: side ?? this.side,
      key: key ?? this.key,
      value: value ?? this.value,
      baseline: baseline ?? this.baseline,
      hitCount: hitCount ?? this.hitCount,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (characterId.present) {
      map['character_id'] = Variable<String>(characterId.value);
    }
    if (side.present) {
      map['side'] = Variable<String>(side.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<double>(value.value);
    }
    if (baseline.present) {
      map['baseline'] = Variable<double>(baseline.value);
    }
    if (hitCount.present) {
      map['hit_count'] = Variable<int>(hitCount.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PersonaTraitRowsCompanion(')
          ..write('characterId: $characterId, ')
          ..write('side: $side, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('baseline: $baseline, ')
          ..write('hitCount: $hitCount, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $AttachmentsTable attachments = $AttachmentsTable(this);
  late final $SessionSummariesTable sessionSummaries = $SessionSummariesTable(
    this,
  );
  late final $SummaryCachesTable summaryCaches = $SummaryCachesTable(this);
  late final $CharactersTable characters = $CharactersTable(this);
  late final $MemoryFactsTable memoryFacts = $MemoryFactsTable(this);
  late final $MemoryEpisodesTable memoryEpisodes = $MemoryEpisodesTable(this);
  late final $MemoryRecallStatsTable memoryRecallStats =
      $MemoryRecallStatsTable(this);
  late final $MoodStatesTable moodStates = $MoodStatesTable(this);
  late final $MoodHistoryTable moodHistory = $MoodHistoryTable(this);
  late final $PersonaTraitRowsTable personaTraitRows = $PersonaTraitRowsTable(
    this,
  );
  late final Index sessionsUpdated = Index(
    'sessions_updated',
    'CREATE INDEX sessions_updated ON sessions (updated_at)',
  );
  late final Index messagesSession = Index(
    'messages_session',
    'CREATE INDEX messages_session ON messages (session_id, created_at)',
  );
  late final Index attachmentsSession = Index(
    'attachments_session',
    'CREATE INDEX attachments_session ON attachments (session_id)',
  );
  late final Index charactersUpdated = Index(
    'characters_updated',
    'CREATE INDEX characters_updated ON characters (updated_at)',
  );
  late final Index memoryFactsScope = Index(
    'memory_facts_scope',
    'CREATE INDEX memory_facts_scope ON memory_facts (character_id, side)',
  );
  late final Index memoryEpisodesScope = Index(
    'memory_episodes_scope',
    'CREATE INDEX memory_episodes_scope ON memory_episodes (character_id, created_at)',
  );
  late final Index moodHistoryScope = Index(
    'mood_history_scope',
    'CREATE INDEX mood_history_scope ON mood_history (character_id, created_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sessions,
    messages,
    attachments,
    sessionSummaries,
    summaryCaches,
    characters,
    memoryFacts,
    memoryEpisodes,
    memoryRecallStats,
    moodStates,
    moodHistory,
    personaTraitRows,
    sessionsUpdated,
    messagesSession,
    attachmentsSession,
    charactersUpdated,
    memoryFactsScope,
    memoryEpisodesScope,
    moodHistoryScope,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'sessions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('messages', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$SessionsTableCreateCompanionBuilder = SessionsCompanion Function({
  required String id,
  Value<String> title,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> messageCount,
  Value<String?> currentMessageId,
  Value<String?> rootMessageId,
  Value<int> flags,
  Value<int?> sort,
  Value<bool> searchEnabled,
  Value<bool?> thinkingEnabled,
  Value<String?> thinkingLevel,
  Value<int?> contextKeepRounds,
  Value<String?> characterId,
  Value<int> rowid,
});
typedef $$SessionsTableUpdateCompanionBuilder = SessionsCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> messageCount,
  Value<String?> currentMessageId,
  Value<String?> rootMessageId,
  Value<int> flags,
  Value<int?> sort,
  Value<bool> searchEnabled,
  Value<bool?> thinkingEnabled,
  Value<String?> thinkingLevel,
  Value<int?> contextKeepRounds,
  Value<String?> characterId,
  Value<int> rowid,
});

final class $$SessionsTableReferences
    extends BaseReferences<_$AppDatabase, $SessionsTable, Session> {
  $$SessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MessagesTable, List<Message>> _messagesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.messages,
    aliasName: 'sessions__id__messages__session_id',
  );

  $$MessagesTableProcessedTableManager get messagesRefs {
    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_messagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SessionsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentMessageId => $composableBuilder(
    column: $table.currentMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rootMessageId => $composableBuilder(
    column: $table.rootMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get flags => $composableBuilder(
    column: $table.flags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get searchEnabled => $composableBuilder(
    column: $table.searchEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get thinkingEnabled => $composableBuilder(
    column: $table.thinkingEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thinkingLevel => $composableBuilder(
    column: $table.thinkingLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get contextKeepRounds => $composableBuilder(
    column: $table.contextKeepRounds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> messagesRefs(
    Expression<bool> Function($$MessagesTableFilterComposer f) f,
  ) {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentMessageId => $composableBuilder(
    column: $table.currentMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rootMessageId => $composableBuilder(
    column: $table.rootMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get flags => $composableBuilder(
    column: $table.flags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get searchEnabled => $composableBuilder(
    column: $table.searchEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get thinkingEnabled => $composableBuilder(
    column: $table.thinkingEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thinkingLevel => $composableBuilder(
    column: $table.thinkingLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get contextKeepRounds => $composableBuilder(
    column: $table.contextKeepRounds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currentMessageId => $composableBuilder(
    column: $table.currentMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rootMessageId => $composableBuilder(
    column: $table.rootMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get flags =>
      $composableBuilder(column: $table.flags, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);

  GeneratedColumn<bool> get searchEnabled => $composableBuilder(
    column: $table.searchEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get thinkingEnabled => $composableBuilder(
    column: $table.thinkingEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thinkingLevel => $composableBuilder(
    column: $table.thinkingLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get contextKeepRounds => $composableBuilder(
    column: $table.contextKeepRounds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => column,
  );

  Expression<T> messagesRefs<T extends Object>(
    Expression<T> Function($$MessagesTableAnnotationComposer a) f,
  ) {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionsTable,
          Session,
          $$SessionsTableFilterComposer,
          $$SessionsTableOrderingComposer,
          $$SessionsTableAnnotationComposer,
          $$SessionsTableCreateCompanionBuilder,
          $$SessionsTableUpdateCompanionBuilder,
          (Session, $$SessionsTableReferences),
          Session,
          PrefetchHooks Function({bool messagesRefs})
        > {
  $$SessionsTableTableManager(_$AppDatabase db, $SessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> messageCount = const Value.absent(),
                Value<String?> currentMessageId = const Value.absent(),
                Value<String?> rootMessageId = const Value.absent(),
                Value<int> flags = const Value.absent(),
                Value<int?> sort = const Value.absent(),
                Value<bool> searchEnabled = const Value.absent(),
                Value<bool?> thinkingEnabled = const Value.absent(),
                Value<String?> thinkingLevel = const Value.absent(),
                Value<int?> contextKeepRounds = const Value.absent(),
                Value<String?> characterId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(
                id: id,
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt,
                messageCount: messageCount,
                currentMessageId: currentMessageId,
                rootMessageId: rootMessageId,
                flags: flags,
                sort: sort,
                searchEnabled: searchEnabled,
                thinkingEnabled: thinkingEnabled,
                thinkingLevel: thinkingLevel,
                contextKeepRounds: contextKeepRounds,
                characterId: characterId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> title = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> messageCount = const Value.absent(),
                Value<String?> currentMessageId = const Value.absent(),
                Value<String?> rootMessageId = const Value.absent(),
                Value<int> flags = const Value.absent(),
                Value<int?> sort = const Value.absent(),
                Value<bool> searchEnabled = const Value.absent(),
                Value<bool?> thinkingEnabled = const Value.absent(),
                Value<String?> thinkingLevel = const Value.absent(),
                Value<int?> contextKeepRounds = const Value.absent(),
                Value<String?> characterId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                id: id,
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt,
                messageCount: messageCount,
                currentMessageId: currentMessageId,
                rootMessageId: rootMessageId,
                flags: flags,
                sort: sort,
                searchEnabled: searchEnabled,
                thinkingEnabled: thinkingEnabled,
                thinkingLevel: thinkingLevel,
                contextKeepRounds: contextKeepRounds,
                characterId: characterId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SessionsTable, Session>(table),
                  $$SessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({messagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (messagesRefs) db.messages],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (messagesRefs)
                    await $_getPrefetchedDataByColumns<
                      Session,
                      $SessionsTable,
                      Message,
                      $MessagesTable
                    >(
                      currentTable: table,
                      referencedTable: $$SessionsTableReferences
                          ._messagesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$SessionsTableReferences(db, table, p0).messagesRefs,
                      currentColumn: 'id',
                      referencedColumn: 'session_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$SessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionsTable,
      Session,
      $$SessionsTableFilterComposer,
      $$SessionsTableOrderingComposer,
      $$SessionsTableAnnotationComposer,
      $$SessionsTableCreateCompanionBuilder,
      $$SessionsTableUpdateCompanionBuilder,
      (Session, $$SessionsTableReferences),
      Session,
      PrefetchHooks Function({bool messagesRefs})
    >;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  required String id,
  required String sessionId,
  required String role,
  Value<String> content,
  Value<DateTime> createdAt,
  Value<String?> rootMessageId,
  Value<String?> currentMessageId,
  Value<int> index,
  Value<int> flags,
  Value<int> rowid,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<String> id,
  Value<String> sessionId,
  Value<String> role,
  Value<String> content,
  Value<DateTime> createdAt,
  Value<String?> rootMessageId,
  Value<String?> currentMessageId,
  Value<int> index,
  Value<int> flags,
  Value<int> rowid,
});

final class $$MessagesTableReferences
    extends BaseReferences<_$AppDatabase, $MessagesTable, Message> {
  $$MessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias('messages__session_id__sessions__id');

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rootMessageId => $composableBuilder(
    column: $table.rootMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentMessageId => $composableBuilder(
    column: $table.currentMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get index => $composableBuilder(
    column: $table.index,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get flags => $composableBuilder(
    column: $table.flags,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rootMessageId => $composableBuilder(
    column: $table.rootMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentMessageId => $composableBuilder(
    column: $table.currentMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get index => $composableBuilder(
    column: $table.index,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get flags => $composableBuilder(
    column: $table.flags,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get rootMessageId => $composableBuilder(
    column: $table.rootMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currentMessageId => $composableBuilder(
    column: $table.currentMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get index =>
      $composableBuilder(column: $table.index, builder: (column) => column);

  GeneratedColumn<int> get flags =>
      $composableBuilder(column: $table.flags, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, $$MessagesTableReferences),
          Message,
          PrefetchHooks Function({bool sessionId})
        > {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> rootMessageId = const Value.absent(),
                Value<String?> currentMessageId = const Value.absent(),
                Value<int> index = const Value.absent(),
                Value<int> flags = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion(
                id: id,
                sessionId: sessionId,
                role: role,
                content: content,
                createdAt: createdAt,
                rootMessageId: rootMessageId,
                currentMessageId: currentMessageId,
                index: index,
                flags: flags,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required String role,
                Value<String> content = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> rootMessageId = const Value.absent(),
                Value<String?> currentMessageId = const Value.absent(),
                Value<int> index = const Value.absent(),
                Value<int> flags = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion.insert(
                id: id,
                sessionId: sessionId,
                role: role,
                content: content,
                createdAt: createdAt,
                rootMessageId: rootMessageId,
                currentMessageId: currentMessageId,
                index: index,
                flags: flags,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MessagesTable, Message>(table),
                  $$MessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.sessionId,
                        referencedTable: $$MessagesTableReferences
                            ._sessionIdTable(db),
                        referencedColumn: $$MessagesTableReferences
                            ._sessionIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, $$MessagesTableReferences),
      Message,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$AttachmentsTableCreateCompanionBuilder =
    AttachmentsCompanion Function({
      required String id,
      required String sessionId,
      Value<String?> messageId,
      Value<String> fileName,
      Value<int> fileSize,
      Value<String> mime,
      Value<String> path,
      Value<int?> width,
      Value<int?> height,
      Value<String?> fileId,
      Value<String?> url,
      Value<int> rowid,
    });
typedef $$AttachmentsTableUpdateCompanionBuilder =
    AttachmentsCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String?> messageId,
      Value<String> fileName,
      Value<int> fileSize,
      Value<String> mime,
      Value<String> path,
      Value<int?> width,
      Value<int?> height,
      Value<String?> fileId,
      Value<String?> url,
      Value<int> rowid,
    });

class $$AttachmentsTableFilterComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AttachmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AttachmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<String> get mime =>
      $composableBuilder(column: $table.mime, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<String> get fileId =>
      $composableBuilder(column: $table.fileId, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);
}

class $$AttachmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AttachmentsTable,
          Attachment,
          $$AttachmentsTableFilterComposer,
          $$AttachmentsTableOrderingComposer,
          $$AttachmentsTableAnnotationComposer,
          $$AttachmentsTableCreateCompanionBuilder,
          $$AttachmentsTableUpdateCompanionBuilder,
          (
            Attachment,
            BaseReferences<_$AppDatabase, $AttachmentsTable, Attachment>,
          ),
          Attachment,
          PrefetchHooks Function()
        > {
  $$AttachmentsTableTableManager(_$AppDatabase db, $AttachmentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AttachmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AttachmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AttachmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String?> messageId = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                Value<String> mime = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<String?> fileId = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentsCompanion(
                id: id,
                sessionId: sessionId,
                messageId: messageId,
                fileName: fileName,
                fileSize: fileSize,
                mime: mime,
                path: path,
                width: width,
                height: height,
                fileId: fileId,
                url: url,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                Value<String?> messageId = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                Value<String> mime = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<String?> fileId = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentsCompanion.insert(
                id: id,
                sessionId: sessionId,
                messageId: messageId,
                fileName: fileName,
                fileSize: fileSize,
                mime: mime,
                path: path,
                width: width,
                height: height,
                fileId: fileId,
                url: url,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AttachmentsTable, Attachment>(table),
                  BaseReferences<_$AppDatabase, $AttachmentsTable, Attachment>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AttachmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AttachmentsTable,
      Attachment,
      $$AttachmentsTableFilterComposer,
      $$AttachmentsTableOrderingComposer,
      $$AttachmentsTableAnnotationComposer,
      $$AttachmentsTableCreateCompanionBuilder,
      $$AttachmentsTableUpdateCompanionBuilder,
      (
        Attachment,
        BaseReferences<_$AppDatabase, $AttachmentsTable, Attachment>,
      ),
      Attachment,
      PrefetchHooks Function()
    >;
typedef $$SessionSummariesTableCreateCompanionBuilder =
    SessionSummariesCompanion Function({
      required String sessionId,
      Value<String> summary,
      Value<int> summaryChars,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$SessionSummariesTableUpdateCompanionBuilder =
    SessionSummariesCompanion Function({
      Value<String> sessionId,
      Value<String> summary,
      Value<int> summaryChars,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SessionSummariesTableFilterComposer
    extends Composer<_$AppDatabase, $SessionSummariesTable> {
  $$SessionSummariesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get summaryChars => $composableBuilder(
    column: $table.summaryChars,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SessionSummariesTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionSummariesTable> {
  $$SessionSummariesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get summaryChars => $composableBuilder(
    column: $table.summaryChars,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionSummariesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionSummariesTable> {
  $$SessionSummariesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<int> get summaryChars => $composableBuilder(
    column: $table.summaryChars,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SessionSummariesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionSummariesTable,
          SessionSummary,
          $$SessionSummariesTableFilterComposer,
          $$SessionSummariesTableOrderingComposer,
          $$SessionSummariesTableAnnotationComposer,
          $$SessionSummariesTableCreateCompanionBuilder,
          $$SessionSummariesTableUpdateCompanionBuilder,
          (
            SessionSummary,
            BaseReferences<
              _$AppDatabase,
              $SessionSummariesTable,
              SessionSummary
            >,
          ),
          SessionSummary,
          PrefetchHooks Function()
        > {
  $$SessionSummariesTableTableManager(
    _$AppDatabase db,
    $SessionSummariesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionSummariesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionSummariesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionSummariesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> summary = const Value.absent(),
                Value<int> summaryChars = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionSummariesCompanion(
                sessionId: sessionId,
                summary: summary,
                summaryChars: summaryChars,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                Value<String> summary = const Value.absent(),
                Value<int> summaryChars = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionSummariesCompanion.insert(
                sessionId: sessionId,
                summary: summary,
                summaryChars: summaryChars,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SessionSummariesTable, SessionSummary>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SessionSummariesTable,
                    SessionSummary
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SessionSummariesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionSummariesTable,
      SessionSummary,
      $$SessionSummariesTableFilterComposer,
      $$SessionSummariesTableOrderingComposer,
      $$SessionSummariesTableAnnotationComposer,
      $$SessionSummariesTableCreateCompanionBuilder,
      $$SessionSummariesTableUpdateCompanionBuilder,
      (
        SessionSummary,
        BaseReferences<_$AppDatabase, $SessionSummariesTable, SessionSummary>,
      ),
      SessionSummary,
      PrefetchHooks Function()
    >;
typedef $$SummaryCachesTableCreateCompanionBuilder =
    SummaryCachesCompanion Function({
      required String sessionId,
      Value<String> contextSummary,
      Value<String> summary,
      Value<int> summaryChars,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$SummaryCachesTableUpdateCompanionBuilder =
    SummaryCachesCompanion Function({
      Value<String> sessionId,
      Value<String> contextSummary,
      Value<String> summary,
      Value<int> summaryChars,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SummaryCachesTableFilterComposer
    extends Composer<_$AppDatabase, $SummaryCachesTable> {
  $$SummaryCachesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contextSummary => $composableBuilder(
    column: $table.contextSummary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get summaryChars => $composableBuilder(
    column: $table.summaryChars,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SummaryCachesTableOrderingComposer
    extends Composer<_$AppDatabase, $SummaryCachesTable> {
  $$SummaryCachesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contextSummary => $composableBuilder(
    column: $table.contextSummary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get summaryChars => $composableBuilder(
    column: $table.summaryChars,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SummaryCachesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SummaryCachesTable> {
  $$SummaryCachesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get contextSummary => $composableBuilder(
    column: $table.contextSummary,
    builder: (column) => column,
  );

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<int> get summaryChars => $composableBuilder(
    column: $table.summaryChars,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SummaryCachesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SummaryCachesTable,
          SummaryCache,
          $$SummaryCachesTableFilterComposer,
          $$SummaryCachesTableOrderingComposer,
          $$SummaryCachesTableAnnotationComposer,
          $$SummaryCachesTableCreateCompanionBuilder,
          $$SummaryCachesTableUpdateCompanionBuilder,
          (
            SummaryCache,
            BaseReferences<_$AppDatabase, $SummaryCachesTable, SummaryCache>,
          ),
          SummaryCache,
          PrefetchHooks Function()
        > {
  $$SummaryCachesTableTableManager(_$AppDatabase db, $SummaryCachesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SummaryCachesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SummaryCachesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SummaryCachesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> contextSummary = const Value.absent(),
                Value<String> summary = const Value.absent(),
                Value<int> summaryChars = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SummaryCachesCompanion(
                sessionId: sessionId,
                contextSummary: contextSummary,
                summary: summary,
                summaryChars: summaryChars,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                Value<String> contextSummary = const Value.absent(),
                Value<String> summary = const Value.absent(),
                Value<int> summaryChars = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SummaryCachesCompanion.insert(
                sessionId: sessionId,
                contextSummary: contextSummary,
                summary: summary,
                summaryChars: summaryChars,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SummaryCachesTable, SummaryCache>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SummaryCachesTable,
                    SummaryCache
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SummaryCachesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SummaryCachesTable,
      SummaryCache,
      $$SummaryCachesTableFilterComposer,
      $$SummaryCachesTableOrderingComposer,
      $$SummaryCachesTableAnnotationComposer,
      $$SummaryCachesTableCreateCompanionBuilder,
      $$SummaryCachesTableUpdateCompanionBuilder,
      (
        SummaryCache,
        BaseReferences<_$AppDatabase, $SummaryCachesTable, SummaryCache>,
      ),
      SummaryCache,
      PrefetchHooks Function()
    >;
typedef $$CharactersTableCreateCompanionBuilder = CharactersCompanion Function({
  required String id,
  Value<String> name,
  Value<String> prompt,
  Value<String?> description,
  Value<String> emoji,
  Value<String> source,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$CharactersTableUpdateCompanionBuilder = CharactersCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> prompt,
  Value<String?> description,
  Value<String> emoji,
  Value<String> source,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$CharactersTableFilterComposer
    extends Composer<_$AppDatabase, $CharactersTable> {
  $$CharactersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get prompt => $composableBuilder(
    column: $table.prompt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CharactersTableOrderingComposer
    extends Composer<_$AppDatabase, $CharactersTable> {
  $$CharactersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get prompt => $composableBuilder(
    column: $table.prompt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CharactersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CharactersTable> {
  $$CharactersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get prompt =>
      $composableBuilder(column: $table.prompt, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get emoji =>
      $composableBuilder(column: $table.emoji, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CharactersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CharactersTable,
          CharacterRow,
          $$CharactersTableFilterComposer,
          $$CharactersTableOrderingComposer,
          $$CharactersTableAnnotationComposer,
          $$CharactersTableCreateCompanionBuilder,
          $$CharactersTableUpdateCompanionBuilder,
          (
            CharacterRow,
            BaseReferences<_$AppDatabase, $CharactersTable, CharacterRow>,
          ),
          CharacterRow,
          PrefetchHooks Function()
        > {
  $$CharactersTableTableManager(_$AppDatabase db, $CharactersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CharactersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CharactersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CharactersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> prompt = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> emoji = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CharactersCompanion(
                id: id,
                name: name,
                prompt: prompt,
                description: description,
                emoji: emoji,
                source: source,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> name = const Value.absent(),
                Value<String> prompt = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> emoji = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CharactersCompanion.insert(
                id: id,
                name: name,
                prompt: prompt,
                description: description,
                emoji: emoji,
                source: source,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CharactersTable, CharacterRow>(table),
                  BaseReferences<_$AppDatabase, $CharactersTable, CharacterRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CharactersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CharactersTable,
      CharacterRow,
      $$CharactersTableFilterComposer,
      $$CharactersTableOrderingComposer,
      $$CharactersTableAnnotationComposer,
      $$CharactersTableCreateCompanionBuilder,
      $$CharactersTableUpdateCompanionBuilder,
      (
        CharacterRow,
        BaseReferences<_$AppDatabase, $CharactersTable, CharacterRow>,
      ),
      CharacterRow,
      PrefetchHooks Function()
    >;
typedef $$MemoryFactsTableCreateCompanionBuilder =
    MemoryFactsCompanion Function({
      required String id,
      Value<String> characterId,
      required String side,
      Value<String> factText,
      Value<double> weight,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> lastUsedAt,
      Value<int> useCount,
      Value<int> rowid,
    });
typedef $$MemoryFactsTableUpdateCompanionBuilder =
    MemoryFactsCompanion Function({
      Value<String> id,
      Value<String> characterId,
      Value<String> side,
      Value<String> factText,
      Value<double> weight,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> lastUsedAt,
      Value<int> useCount,
      Value<int> rowid,
    });

class $$MemoryFactsTableFilterComposer
    extends Composer<_$AppDatabase, $MemoryFactsTable> {
  $$MemoryFactsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get side => $composableBuilder(
    column: $table.side,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get factText => $composableBuilder(
    column: $table.factText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get useCount => $composableBuilder(
    column: $table.useCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MemoryFactsTableOrderingComposer
    extends Composer<_$AppDatabase, $MemoryFactsTable> {
  $$MemoryFactsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get side => $composableBuilder(
    column: $table.side,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get factText => $composableBuilder(
    column: $table.factText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weight => $composableBuilder(
    column: $table.weight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get useCount => $composableBuilder(
    column: $table.useCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MemoryFactsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MemoryFactsTable> {
  $$MemoryFactsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get side =>
      $composableBuilder(column: $table.side, builder: (column) => column);

  GeneratedColumn<String> get factText =>
      $composableBuilder(column: $table.factText, builder: (column) => column);

  GeneratedColumn<double> get weight =>
      $composableBuilder(column: $table.weight, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get useCount =>
      $composableBuilder(column: $table.useCount, builder: (column) => column);
}

class $$MemoryFactsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MemoryFactsTable,
          MemoryFactRow,
          $$MemoryFactsTableFilterComposer,
          $$MemoryFactsTableOrderingComposer,
          $$MemoryFactsTableAnnotationComposer,
          $$MemoryFactsTableCreateCompanionBuilder,
          $$MemoryFactsTableUpdateCompanionBuilder,
          (
            MemoryFactRow,
            BaseReferences<_$AppDatabase, $MemoryFactsTable, MemoryFactRow>,
          ),
          MemoryFactRow,
          PrefetchHooks Function()
        > {
  $$MemoryFactsTableTableManager(_$AppDatabase db, $MemoryFactsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MemoryFactsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MemoryFactsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MemoryFactsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> characterId = const Value.absent(),
                Value<String> side = const Value.absent(),
                Value<String> factText = const Value.absent(),
                Value<double> weight = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> lastUsedAt = const Value.absent(),
                Value<int> useCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MemoryFactsCompanion(
                id: id,
                characterId: characterId,
                side: side,
                factText: factText,
                weight: weight,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastUsedAt: lastUsedAt,
                useCount: useCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> characterId = const Value.absent(),
                required String side,
                Value<String> factText = const Value.absent(),
                Value<double> weight = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> lastUsedAt = const Value.absent(),
                Value<int> useCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MemoryFactsCompanion.insert(
                id: id,
                characterId: characterId,
                side: side,
                factText: factText,
                weight: weight,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastUsedAt: lastUsedAt,
                useCount: useCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MemoryFactsTable, MemoryFactRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $MemoryFactsTable,
                    MemoryFactRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MemoryFactsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MemoryFactsTable,
      MemoryFactRow,
      $$MemoryFactsTableFilterComposer,
      $$MemoryFactsTableOrderingComposer,
      $$MemoryFactsTableAnnotationComposer,
      $$MemoryFactsTableCreateCompanionBuilder,
      $$MemoryFactsTableUpdateCompanionBuilder,
      (
        MemoryFactRow,
        BaseReferences<_$AppDatabase, $MemoryFactsTable, MemoryFactRow>,
      ),
      MemoryFactRow,
      PrefetchHooks Function()
    >;
typedef $$MemoryEpisodesTableCreateCompanionBuilder =
    MemoryEpisodesCompanion Function({
      required String id,
      Value<String> characterId,
      Value<String> sessionId,
      Value<String> turnIdsJson,
      Value<String> summary,
      Value<double?> mood,
      Value<double> salience,
      Value<DateTime> createdAt,
      Value<DateTime?> lastUsedAt,
      Value<int> rowid,
    });
typedef $$MemoryEpisodesTableUpdateCompanionBuilder =
    MemoryEpisodesCompanion Function({
      Value<String> id,
      Value<String> characterId,
      Value<String> sessionId,
      Value<String> turnIdsJson,
      Value<String> summary,
      Value<double?> mood,
      Value<double> salience,
      Value<DateTime> createdAt,
      Value<DateTime?> lastUsedAt,
      Value<int> rowid,
    });

class $$MemoryEpisodesTableFilterComposer
    extends Composer<_$AppDatabase, $MemoryEpisodesTable> {
  $$MemoryEpisodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get turnIdsJson => $composableBuilder(
    column: $table.turnIdsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get salience => $composableBuilder(
    column: $table.salience,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MemoryEpisodesTableOrderingComposer
    extends Composer<_$AppDatabase, $MemoryEpisodesTable> {
  $$MemoryEpisodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get turnIdsJson => $composableBuilder(
    column: $table.turnIdsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get salience => $composableBuilder(
    column: $table.salience,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MemoryEpisodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MemoryEpisodesTable> {
  $$MemoryEpisodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get turnIdsJson => $composableBuilder(
    column: $table.turnIdsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<double> get mood =>
      $composableBuilder(column: $table.mood, builder: (column) => column);

  GeneratedColumn<double> get salience =>
      $composableBuilder(column: $table.salience, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );
}

class $$MemoryEpisodesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MemoryEpisodesTable,
          MemoryEpisodeRow,
          $$MemoryEpisodesTableFilterComposer,
          $$MemoryEpisodesTableOrderingComposer,
          $$MemoryEpisodesTableAnnotationComposer,
          $$MemoryEpisodesTableCreateCompanionBuilder,
          $$MemoryEpisodesTableUpdateCompanionBuilder,
          (
            MemoryEpisodeRow,
            BaseReferences<
              _$AppDatabase,
              $MemoryEpisodesTable,
              MemoryEpisodeRow
            >,
          ),
          MemoryEpisodeRow,
          PrefetchHooks Function()
        > {
  $$MemoryEpisodesTableTableManager(
    _$AppDatabase db,
    $MemoryEpisodesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MemoryEpisodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MemoryEpisodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MemoryEpisodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> characterId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> turnIdsJson = const Value.absent(),
                Value<String> summary = const Value.absent(),
                Value<double?> mood = const Value.absent(),
                Value<double> salience = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastUsedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MemoryEpisodesCompanion(
                id: id,
                characterId: characterId,
                sessionId: sessionId,
                turnIdsJson: turnIdsJson,
                summary: summary,
                mood: mood,
                salience: salience,
                createdAt: createdAt,
                lastUsedAt: lastUsedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> characterId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> turnIdsJson = const Value.absent(),
                Value<String> summary = const Value.absent(),
                Value<double?> mood = const Value.absent(),
                Value<double> salience = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastUsedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MemoryEpisodesCompanion.insert(
                id: id,
                characterId: characterId,
                sessionId: sessionId,
                turnIdsJson: turnIdsJson,
                summary: summary,
                mood: mood,
                salience: salience,
                createdAt: createdAt,
                lastUsedAt: lastUsedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MemoryEpisodesTable, MemoryEpisodeRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $MemoryEpisodesTable,
                    MemoryEpisodeRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MemoryEpisodesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MemoryEpisodesTable,
      MemoryEpisodeRow,
      $$MemoryEpisodesTableFilterComposer,
      $$MemoryEpisodesTableOrderingComposer,
      $$MemoryEpisodesTableAnnotationComposer,
      $$MemoryEpisodesTableCreateCompanionBuilder,
      $$MemoryEpisodesTableUpdateCompanionBuilder,
      (
        MemoryEpisodeRow,
        BaseReferences<_$AppDatabase, $MemoryEpisodesTable, MemoryEpisodeRow>,
      ),
      MemoryEpisodeRow,
      PrefetchHooks Function()
    >;
typedef $$MemoryRecallStatsTableCreateCompanionBuilder =
    MemoryRecallStatsCompanion Function({
      required String kind,
      required String memoryId,
      Value<String> characterId,
      Value<int> injected,
      Value<int> used,
      Value<int> ignored,
      Value<double> usefulness,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$MemoryRecallStatsTableUpdateCompanionBuilder =
    MemoryRecallStatsCompanion Function({
      Value<String> kind,
      Value<String> memoryId,
      Value<String> characterId,
      Value<int> injected,
      Value<int> used,
      Value<int> ignored,
      Value<double> usefulness,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$MemoryRecallStatsTableFilterComposer
    extends Composer<_$AppDatabase, $MemoryRecallStatsTable> {
  $$MemoryRecallStatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get memoryId => $composableBuilder(
    column: $table.memoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get injected => $composableBuilder(
    column: $table.injected,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get used => $composableBuilder(
    column: $table.used,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ignored => $composableBuilder(
    column: $table.ignored,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get usefulness => $composableBuilder(
    column: $table.usefulness,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MemoryRecallStatsTableOrderingComposer
    extends Composer<_$AppDatabase, $MemoryRecallStatsTable> {
  $$MemoryRecallStatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get memoryId => $composableBuilder(
    column: $table.memoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get injected => $composableBuilder(
    column: $table.injected,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get used => $composableBuilder(
    column: $table.used,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ignored => $composableBuilder(
    column: $table.ignored,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get usefulness => $composableBuilder(
    column: $table.usefulness,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MemoryRecallStatsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MemoryRecallStatsTable> {
  $$MemoryRecallStatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get memoryId =>
      $composableBuilder(column: $table.memoryId, builder: (column) => column);

  GeneratedColumn<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get injected =>
      $composableBuilder(column: $table.injected, builder: (column) => column);

  GeneratedColumn<int> get used =>
      $composableBuilder(column: $table.used, builder: (column) => column);

  GeneratedColumn<int> get ignored =>
      $composableBuilder(column: $table.ignored, builder: (column) => column);

  GeneratedColumn<double> get usefulness => $composableBuilder(
    column: $table.usefulness,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$MemoryRecallStatsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MemoryRecallStatsTable,
          MemoryRecallStatRow,
          $$MemoryRecallStatsTableFilterComposer,
          $$MemoryRecallStatsTableOrderingComposer,
          $$MemoryRecallStatsTableAnnotationComposer,
          $$MemoryRecallStatsTableCreateCompanionBuilder,
          $$MemoryRecallStatsTableUpdateCompanionBuilder,
          (
            MemoryRecallStatRow,
            BaseReferences<
              _$AppDatabase,
              $MemoryRecallStatsTable,
              MemoryRecallStatRow
            >,
          ),
          MemoryRecallStatRow,
          PrefetchHooks Function()
        > {
  $$MemoryRecallStatsTableTableManager(
    _$AppDatabase db,
    $MemoryRecallStatsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MemoryRecallStatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MemoryRecallStatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MemoryRecallStatsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> kind = const Value.absent(),
                Value<String> memoryId = const Value.absent(),
                Value<String> characterId = const Value.absent(),
                Value<int> injected = const Value.absent(),
                Value<int> used = const Value.absent(),
                Value<int> ignored = const Value.absent(),
                Value<double> usefulness = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MemoryRecallStatsCompanion(
                kind: kind,
                memoryId: memoryId,
                characterId: characterId,
                injected: injected,
                used: used,
                ignored: ignored,
                usefulness: usefulness,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String kind,
                required String memoryId,
                Value<String> characterId = const Value.absent(),
                Value<int> injected = const Value.absent(),
                Value<int> used = const Value.absent(),
                Value<int> ignored = const Value.absent(),
                Value<double> usefulness = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MemoryRecallStatsCompanion.insert(
                kind: kind,
                memoryId: memoryId,
                characterId: characterId,
                injected: injected,
                used: used,
                ignored: ignored,
                usefulness: usefulness,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MemoryRecallStatsTable, MemoryRecallStatRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $MemoryRecallStatsTable,
                    MemoryRecallStatRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MemoryRecallStatsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MemoryRecallStatsTable,
      MemoryRecallStatRow,
      $$MemoryRecallStatsTableFilterComposer,
      $$MemoryRecallStatsTableOrderingComposer,
      $$MemoryRecallStatsTableAnnotationComposer,
      $$MemoryRecallStatsTableCreateCompanionBuilder,
      $$MemoryRecallStatsTableUpdateCompanionBuilder,
      (
        MemoryRecallStatRow,
        BaseReferences<
          _$AppDatabase,
          $MemoryRecallStatsTable,
          MemoryRecallStatRow
        >,
      ),
      MemoryRecallStatRow,
      PrefetchHooks Function()
    >;
typedef $$MoodStatesTableCreateCompanionBuilder = MoodStatesCompanion Function({
  required String characterId,
  Value<String> name,
  Value<double> valence,
  Value<double> affection,
  Value<double> energy,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$MoodStatesTableUpdateCompanionBuilder = MoodStatesCompanion Function({
  Value<String> characterId,
  Value<String> name,
  Value<double> valence,
  Value<double> affection,
  Value<double> energy,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$MoodStatesTableFilterComposer
    extends Composer<_$AppDatabase, $MoodStatesTable> {
  $$MoodStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get valence => $composableBuilder(
    column: $table.valence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get affection => $composableBuilder(
    column: $table.affection,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get energy => $composableBuilder(
    column: $table.energy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MoodStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $MoodStatesTable> {
  $$MoodStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get valence => $composableBuilder(
    column: $table.valence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get affection => $composableBuilder(
    column: $table.affection,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get energy => $composableBuilder(
    column: $table.energy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MoodStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MoodStatesTable> {
  $$MoodStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get valence =>
      $composableBuilder(column: $table.valence, builder: (column) => column);

  GeneratedColumn<double> get affection =>
      $composableBuilder(column: $table.affection, builder: (column) => column);

  GeneratedColumn<double> get energy =>
      $composableBuilder(column: $table.energy, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$MoodStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MoodStatesTable,
          MoodStateRow,
          $$MoodStatesTableFilterComposer,
          $$MoodStatesTableOrderingComposer,
          $$MoodStatesTableAnnotationComposer,
          $$MoodStatesTableCreateCompanionBuilder,
          $$MoodStatesTableUpdateCompanionBuilder,
          (
            MoodStateRow,
            BaseReferences<_$AppDatabase, $MoodStatesTable, MoodStateRow>,
          ),
          MoodStateRow,
          PrefetchHooks Function()
        > {
  $$MoodStatesTableTableManager(_$AppDatabase db, $MoodStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MoodStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MoodStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MoodStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> characterId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> valence = const Value.absent(),
                Value<double> affection = const Value.absent(),
                Value<double> energy = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MoodStatesCompanion(
                characterId: characterId,
                name: name,
                valence: valence,
                affection: affection,
                energy: energy,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String characterId,
                Value<String> name = const Value.absent(),
                Value<double> valence = const Value.absent(),
                Value<double> affection = const Value.absent(),
                Value<double> energy = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MoodStatesCompanion.insert(
                characterId: characterId,
                name: name,
                valence: valence,
                affection: affection,
                energy: energy,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MoodStatesTable, MoodStateRow>(table),
                  BaseReferences<_$AppDatabase, $MoodStatesTable, MoodStateRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MoodStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MoodStatesTable,
      MoodStateRow,
      $$MoodStatesTableFilterComposer,
      $$MoodStatesTableOrderingComposer,
      $$MoodStatesTableAnnotationComposer,
      $$MoodStatesTableCreateCompanionBuilder,
      $$MoodStatesTableUpdateCompanionBuilder,
      (
        MoodStateRow,
        BaseReferences<_$AppDatabase, $MoodStatesTable, MoodStateRow>,
      ),
      MoodStateRow,
      PrefetchHooks Function()
    >;
typedef $$MoodHistoryTableCreateCompanionBuilder =
    MoodHistoryCompanion Function({
      Value<int> id,
      Value<String> characterId,
      Value<String> name,
      Value<double> valence,
      Value<double> affection,
      Value<double> energy,
      Value<String> reason,
      Value<DateTime> createdAt,
    });
typedef $$MoodHistoryTableUpdateCompanionBuilder =
    MoodHistoryCompanion Function({
      Value<int> id,
      Value<String> characterId,
      Value<String> name,
      Value<double> valence,
      Value<double> affection,
      Value<double> energy,
      Value<String> reason,
      Value<DateTime> createdAt,
    });

class $$MoodHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $MoodHistoryTable> {
  $$MoodHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get valence => $composableBuilder(
    column: $table.valence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get affection => $composableBuilder(
    column: $table.affection,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get energy => $composableBuilder(
    column: $table.energy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MoodHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $MoodHistoryTable> {
  $$MoodHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get valence => $composableBuilder(
    column: $table.valence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get affection => $composableBuilder(
    column: $table.affection,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get energy => $composableBuilder(
    column: $table.energy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MoodHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $MoodHistoryTable> {
  $$MoodHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get valence =>
      $composableBuilder(column: $table.valence, builder: (column) => column);

  GeneratedColumn<double> get affection =>
      $composableBuilder(column: $table.affection, builder: (column) => column);

  GeneratedColumn<double> get energy =>
      $composableBuilder(column: $table.energy, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$MoodHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MoodHistoryTable,
          MoodHistoryRow,
          $$MoodHistoryTableFilterComposer,
          $$MoodHistoryTableOrderingComposer,
          $$MoodHistoryTableAnnotationComposer,
          $$MoodHistoryTableCreateCompanionBuilder,
          $$MoodHistoryTableUpdateCompanionBuilder,
          (
            MoodHistoryRow,
            BaseReferences<_$AppDatabase, $MoodHistoryTable, MoodHistoryRow>,
          ),
          MoodHistoryRow,
          PrefetchHooks Function()
        > {
  $$MoodHistoryTableTableManager(_$AppDatabase db, $MoodHistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MoodHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MoodHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MoodHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> characterId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> valence = const Value.absent(),
                Value<double> affection = const Value.absent(),
                Value<double> energy = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => MoodHistoryCompanion(
                id: id,
                characterId: characterId,
                name: name,
                valence: valence,
                affection: affection,
                energy: energy,
                reason: reason,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> characterId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> valence = const Value.absent(),
                Value<double> affection = const Value.absent(),
                Value<double> energy = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => MoodHistoryCompanion.insert(
                id: id,
                characterId: characterId,
                name: name,
                valence: valence,
                affection: affection,
                energy: energy,
                reason: reason,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MoodHistoryTable, MoodHistoryRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $MoodHistoryTable,
                    MoodHistoryRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MoodHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MoodHistoryTable,
      MoodHistoryRow,
      $$MoodHistoryTableFilterComposer,
      $$MoodHistoryTableOrderingComposer,
      $$MoodHistoryTableAnnotationComposer,
      $$MoodHistoryTableCreateCompanionBuilder,
      $$MoodHistoryTableUpdateCompanionBuilder,
      (
        MoodHistoryRow,
        BaseReferences<_$AppDatabase, $MoodHistoryTable, MoodHistoryRow>,
      ),
      MoodHistoryRow,
      PrefetchHooks Function()
    >;
typedef $$PersonaTraitRowsTableCreateCompanionBuilder =
    PersonaTraitRowsCompanion Function({
      Value<String> characterId,
      required String side,
      required String key,
      Value<double> value,
      Value<double> baseline,
      Value<int> hitCount,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$PersonaTraitRowsTableUpdateCompanionBuilder =
    PersonaTraitRowsCompanion Function({
      Value<String> characterId,
      Value<String> side,
      Value<String> key,
      Value<double> value,
      Value<double> baseline,
      Value<int> hitCount,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$PersonaTraitRowsTableFilterComposer
    extends Composer<_$AppDatabase, $PersonaTraitRowsTable> {
  $$PersonaTraitRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get side => $composableBuilder(
    column: $table.side,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get baseline => $composableBuilder(
    column: $table.baseline,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hitCount => $composableBuilder(
    column: $table.hitCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PersonaTraitRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $PersonaTraitRowsTable> {
  $$PersonaTraitRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get side => $composableBuilder(
    column: $table.side,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get baseline => $composableBuilder(
    column: $table.baseline,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hitCount => $composableBuilder(
    column: $table.hitCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PersonaTraitRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PersonaTraitRowsTable> {
  $$PersonaTraitRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get characterId => $composableBuilder(
    column: $table.characterId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get side =>
      $composableBuilder(column: $table.side, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<double> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<double> get baseline =>
      $composableBuilder(column: $table.baseline, builder: (column) => column);

  GeneratedColumn<int> get hitCount =>
      $composableBuilder(column: $table.hitCount, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PersonaTraitRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PersonaTraitRowsTable,
          PersonaTraitRow,
          $$PersonaTraitRowsTableFilterComposer,
          $$PersonaTraitRowsTableOrderingComposer,
          $$PersonaTraitRowsTableAnnotationComposer,
          $$PersonaTraitRowsTableCreateCompanionBuilder,
          $$PersonaTraitRowsTableUpdateCompanionBuilder,
          (
            PersonaTraitRow,
            BaseReferences<
              _$AppDatabase,
              $PersonaTraitRowsTable,
              PersonaTraitRow
            >,
          ),
          PersonaTraitRow,
          PrefetchHooks Function()
        > {
  $$PersonaTraitRowsTableTableManager(
    _$AppDatabase db,
    $PersonaTraitRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PersonaTraitRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PersonaTraitRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PersonaTraitRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> characterId = const Value.absent(),
                Value<String> side = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<double> value = const Value.absent(),
                Value<double> baseline = const Value.absent(),
                Value<int> hitCount = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PersonaTraitRowsCompanion(
                characterId: characterId,
                side: side,
                key: key,
                value: value,
                baseline: baseline,
                hitCount: hitCount,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> characterId = const Value.absent(),
                required String side,
                required String key,
                Value<double> value = const Value.absent(),
                Value<double> baseline = const Value.absent(),
                Value<int> hitCount = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PersonaTraitRowsCompanion.insert(
                characterId: characterId,
                side: side,
                key: key,
                value: value,
                baseline: baseline,
                hitCount: hitCount,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PersonaTraitRowsTable, PersonaTraitRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PersonaTraitRowsTable,
                    PersonaTraitRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PersonaTraitRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PersonaTraitRowsTable,
      PersonaTraitRow,
      $$PersonaTraitRowsTableFilterComposer,
      $$PersonaTraitRowsTableOrderingComposer,
      $$PersonaTraitRowsTableAnnotationComposer,
      $$PersonaTraitRowsTableCreateCompanionBuilder,
      $$PersonaTraitRowsTableUpdateCompanionBuilder,
      (
        PersonaTraitRow,
        BaseReferences<_$AppDatabase, $PersonaTraitRowsTable, PersonaTraitRow>,
      ),
      PersonaTraitRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$AttachmentsTableTableManager get attachments =>
      $$AttachmentsTableTableManager(_db, _db.attachments);
  $$SessionSummariesTableTableManager get sessionSummaries =>
      $$SessionSummariesTableTableManager(_db, _db.sessionSummaries);
  $$SummaryCachesTableTableManager get summaryCaches =>
      $$SummaryCachesTableTableManager(_db, _db.summaryCaches);
  $$CharactersTableTableManager get characters =>
      $$CharactersTableTableManager(_db, _db.characters);
  $$MemoryFactsTableTableManager get memoryFacts =>
      $$MemoryFactsTableTableManager(_db, _db.memoryFacts);
  $$MemoryEpisodesTableTableManager get memoryEpisodes =>
      $$MemoryEpisodesTableTableManager(_db, _db.memoryEpisodes);
  $$MemoryRecallStatsTableTableManager get memoryRecallStats =>
      $$MemoryRecallStatsTableTableManager(_db, _db.memoryRecallStats);
  $$MoodStatesTableTableManager get moodStates =>
      $$MoodStatesTableTableManager(_db, _db.moodStates);
  $$MoodHistoryTableTableManager get moodHistory =>
      $$MoodHistoryTableTableManager(_db, _db.moodHistory);
  $$PersonaTraitRowsTableTableManager get personaTraitRows =>
      $$PersonaTraitRowsTableTableManager(_db, _db.personaTraitRows);
}
