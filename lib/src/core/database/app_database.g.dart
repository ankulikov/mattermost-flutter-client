// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CachedUserProfilesTable extends CachedUserProfiles
    with TableInfo<$CachedUserProfilesTable, CachedUserProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedUserProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstNameMeta = const VerificationMeta(
    'firstName',
  );
  @override
  late final GeneratedColumn<String> firstName = GeneratedColumn<String>(
    'first_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastNameMeta = const VerificationMeta(
    'lastName',
  );
  @override
  late final GeneratedColumn<String> lastName = GeneratedColumn<String>(
    'last_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    userId,
    firstName,
    lastName,
    username,
    expiresAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_user_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedUserProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('first_name')) {
      context.handle(
        _firstNameMeta,
        firstName.isAcceptableOrUnknown(data['first_name']!, _firstNameMeta),
      );
    } else if (isInserting) {
      context.missing(_firstNameMeta);
    }
    if (data.containsKey('last_name')) {
      context.handle(
        _lastNameMeta,
        lastName.isAcceptableOrUnknown(data['last_name']!, _lastNameMeta),
      );
    } else if (isInserting) {
      context.missing(_lastNameMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, userId};
  @override
  CachedUserProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedUserProfile(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      firstName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_name'],
      )!,
      lastName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_name'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      )!,
    );
  }

  @override
  $CachedUserProfilesTable createAlias(String alias) {
    return $CachedUserProfilesTable(attachedDatabase, alias);
  }
}

class CachedUserProfile extends DataClass
    implements Insertable<CachedUserProfile> {
  final String accountId;
  final String userId;
  final String firstName;
  final String lastName;
  final String username;
  final DateTime expiresAt;
  const CachedUserProfile({
    required this.accountId,
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.expiresAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['user_id'] = Variable<String>(userId);
    map['first_name'] = Variable<String>(firstName);
    map['last_name'] = Variable<String>(lastName);
    map['username'] = Variable<String>(username);
    map['expires_at'] = Variable<DateTime>(expiresAt);
    return map;
  }

  CachedUserProfilesCompanion toCompanion(bool nullToAbsent) {
    return CachedUserProfilesCompanion(
      accountId: Value(accountId),
      userId: Value(userId),
      firstName: Value(firstName),
      lastName: Value(lastName),
      username: Value(username),
      expiresAt: Value(expiresAt),
    );
  }

  factory CachedUserProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedUserProfile(
      accountId: serializer.fromJson<String>(json['accountId']),
      userId: serializer.fromJson<String>(json['userId']),
      firstName: serializer.fromJson<String>(json['firstName']),
      lastName: serializer.fromJson<String>(json['lastName']),
      username: serializer.fromJson<String>(json['username']),
      expiresAt: serializer.fromJson<DateTime>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'userId': serializer.toJson<String>(userId),
      'firstName': serializer.toJson<String>(firstName),
      'lastName': serializer.toJson<String>(lastName),
      'username': serializer.toJson<String>(username),
      'expiresAt': serializer.toJson<DateTime>(expiresAt),
    };
  }

  CachedUserProfile copyWith({
    String? accountId,
    String? userId,
    String? firstName,
    String? lastName,
    String? username,
    DateTime? expiresAt,
  }) => CachedUserProfile(
    accountId: accountId ?? this.accountId,
    userId: userId ?? this.userId,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    username: username ?? this.username,
    expiresAt: expiresAt ?? this.expiresAt,
  );
  CachedUserProfile copyWithCompanion(CachedUserProfilesCompanion data) {
    return CachedUserProfile(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      userId: data.userId.present ? data.userId.value : this.userId,
      firstName: data.firstName.present ? data.firstName.value : this.firstName,
      lastName: data.lastName.present ? data.lastName.value : this.lastName,
      username: data.username.present ? data.username.value : this.username,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedUserProfile(')
          ..write('accountId: $accountId, ')
          ..write('userId: $userId, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('username: $username, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(accountId, userId, firstName, lastName, username, expiresAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedUserProfile &&
          other.accountId == this.accountId &&
          other.userId == this.userId &&
          other.firstName == this.firstName &&
          other.lastName == this.lastName &&
          other.username == this.username &&
          other.expiresAt == this.expiresAt);
}

class CachedUserProfilesCompanion extends UpdateCompanion<CachedUserProfile> {
  final Value<String> accountId;
  final Value<String> userId;
  final Value<String> firstName;
  final Value<String> lastName;
  final Value<String> username;
  final Value<DateTime> expiresAt;
  final Value<int> rowid;
  const CachedUserProfilesCompanion({
    this.accountId = const Value.absent(),
    this.userId = const Value.absent(),
    this.firstName = const Value.absent(),
    this.lastName = const Value.absent(),
    this.username = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedUserProfilesCompanion.insert({
    required String accountId,
    required String userId,
    required String firstName,
    required String lastName,
    required String username,
    required DateTime expiresAt,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       userId = Value(userId),
       firstName = Value(firstName),
       lastName = Value(lastName),
       username = Value(username),
       expiresAt = Value(expiresAt);
  static Insertable<CachedUserProfile> custom({
    Expression<String>? accountId,
    Expression<String>? userId,
    Expression<String>? firstName,
    Expression<String>? lastName,
    Expression<String>? username,
    Expression<DateTime>? expiresAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (userId != null) 'user_id': userId,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (username != null) 'username': username,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedUserProfilesCompanion copyWith({
    Value<String>? accountId,
    Value<String>? userId,
    Value<String>? firstName,
    Value<String>? lastName,
    Value<String>? username,
    Value<DateTime>? expiresAt,
    Value<int>? rowid,
  }) {
    return CachedUserProfilesCompanion(
      accountId: accountId ?? this.accountId,
      userId: userId ?? this.userId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      username: username ?? this.username,
      expiresAt: expiresAt ?? this.expiresAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (firstName.present) {
      map['first_name'] = Variable<String>(firstName.value);
    }
    if (lastName.present) {
      map['last_name'] = Variable<String>(lastName.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedUserProfilesCompanion(')
          ..write('accountId: $accountId, ')
          ..write('userId: $userId, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('username: $username, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CachedUserProfilesTable cachedUserProfiles =
      $CachedUserProfilesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [cachedUserProfiles];
}

typedef $$CachedUserProfilesTableCreateCompanionBuilder =
    CachedUserProfilesCompanion Function({
      required String accountId,
      required String userId,
      required String firstName,
      required String lastName,
      required String username,
      required DateTime expiresAt,
      Value<int> rowid,
    });
typedef $$CachedUserProfilesTableUpdateCompanionBuilder =
    CachedUserProfilesCompanion Function({
      Value<String> accountId,
      Value<String> userId,
      Value<String> firstName,
      Value<String> lastName,
      Value<String> username,
      Value<DateTime> expiresAt,
      Value<int> rowid,
    });

class $$CachedUserProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $CachedUserProfilesTable> {
  $$CachedUserProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedUserProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedUserProfilesTable> {
  $$CachedUserProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedUserProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedUserProfilesTable> {
  $$CachedUserProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get firstName =>
      $composableBuilder(column: $table.firstName, builder: (column) => column);

  GeneratedColumn<String> get lastName =>
      $composableBuilder(column: $table.lastName, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);
}

class $$CachedUserProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedUserProfilesTable,
          CachedUserProfile,
          $$CachedUserProfilesTableFilterComposer,
          $$CachedUserProfilesTableOrderingComposer,
          $$CachedUserProfilesTableAnnotationComposer,
          $$CachedUserProfilesTableCreateCompanionBuilder,
          $$CachedUserProfilesTableUpdateCompanionBuilder,
          (
            CachedUserProfile,
            BaseReferences<
              _$AppDatabase,
              $CachedUserProfilesTable,
              CachedUserProfile
            >,
          ),
          CachedUserProfile,
          PrefetchHooks Function()
        > {
  $$CachedUserProfilesTableTableManager(
    _$AppDatabase db,
    $CachedUserProfilesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedUserProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedUserProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedUserProfilesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> firstName = const Value.absent(),
                Value<String> lastName = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<DateTime> expiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedUserProfilesCompanion(
                accountId: accountId,
                userId: userId,
                firstName: firstName,
                lastName: lastName,
                username: username,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String userId,
                required String firstName,
                required String lastName,
                required String username,
                required DateTime expiresAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedUserProfilesCompanion.insert(
                accountId: accountId,
                userId: userId,
                firstName: firstName,
                lastName: lastName,
                username: username,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedUserProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedUserProfilesTable,
      CachedUserProfile,
      $$CachedUserProfilesTableFilterComposer,
      $$CachedUserProfilesTableOrderingComposer,
      $$CachedUserProfilesTableAnnotationComposer,
      $$CachedUserProfilesTableCreateCompanionBuilder,
      $$CachedUserProfilesTableUpdateCompanionBuilder,
      (
        CachedUserProfile,
        BaseReferences<
          _$AppDatabase,
          $CachedUserProfilesTable,
          CachedUserProfile
        >,
      ),
      CachedUserProfile,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CachedUserProfilesTableTableManager get cachedUserProfiles =>
      $$CachedUserProfilesTableTableManager(_db, _db.cachedUserProfiles);
}
