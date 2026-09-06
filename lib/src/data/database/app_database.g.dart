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
  static const VerificationMeta _nicknameMeta = const VerificationMeta(
    'nickname',
  );
  @override
  late final GeneratedColumn<String> nickname = GeneratedColumn<String>(
    'nickname',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant<String>(''),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<String> position = GeneratedColumn<String>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant<String>(''),
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant<String>(''),
  );
  static const VerificationMeta _profileImageUpdatedAtMeta =
      const VerificationMeta('profileImageUpdatedAt');
  @override
  late final GeneratedColumn<int> profileImageUpdatedAt = GeneratedColumn<int>(
    'profile_image_updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(0),
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
    nickname,
    position,
    email,
    profileImageUpdatedAt,
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
    if (data.containsKey('nickname')) {
      context.handle(
        _nicknameMeta,
        nickname.isAcceptableOrUnknown(data['nickname']!, _nicknameMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    }
    if (data.containsKey('profile_image_updated_at')) {
      context.handle(
        _profileImageUpdatedAtMeta,
        profileImageUpdatedAt.isAcceptableOrUnknown(
          data['profile_image_updated_at']!,
          _profileImageUpdatedAtMeta,
        ),
      );
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
      nickname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nickname'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}position'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      )!,
      profileImageUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}profile_image_updated_at'],
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
  final String nickname;
  final String position;
  final String email;
  final int profileImageUpdatedAt;
  final DateTime expiresAt;
  const CachedUserProfile({
    required this.accountId,
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.nickname,
    required this.position,
    required this.email,
    required this.profileImageUpdatedAt,
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
    map['nickname'] = Variable<String>(nickname);
    map['position'] = Variable<String>(position);
    map['email'] = Variable<String>(email);
    map['profile_image_updated_at'] = Variable<int>(profileImageUpdatedAt);
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
      nickname: Value(nickname),
      position: Value(position),
      email: Value(email),
      profileImageUpdatedAt: Value(profileImageUpdatedAt),
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
      nickname: serializer.fromJson<String>(json['nickname']),
      position: serializer.fromJson<String>(json['position']),
      email: serializer.fromJson<String>(json['email']),
      profileImageUpdatedAt: serializer.fromJson<int>(
        json['profileImageUpdatedAt'],
      ),
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
      'nickname': serializer.toJson<String>(nickname),
      'position': serializer.toJson<String>(position),
      'email': serializer.toJson<String>(email),
      'profileImageUpdatedAt': serializer.toJson<int>(profileImageUpdatedAt),
      'expiresAt': serializer.toJson<DateTime>(expiresAt),
    };
  }

  CachedUserProfile copyWith({
    String? accountId,
    String? userId,
    String? firstName,
    String? lastName,
    String? username,
    String? nickname,
    String? position,
    String? email,
    int? profileImageUpdatedAt,
    DateTime? expiresAt,
  }) => CachedUserProfile(
    accountId: accountId ?? this.accountId,
    userId: userId ?? this.userId,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    username: username ?? this.username,
    nickname: nickname ?? this.nickname,
    position: position ?? this.position,
    email: email ?? this.email,
    profileImageUpdatedAt: profileImageUpdatedAt ?? this.profileImageUpdatedAt,
    expiresAt: expiresAt ?? this.expiresAt,
  );
  CachedUserProfile copyWithCompanion(CachedUserProfilesCompanion data) {
    return CachedUserProfile(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      userId: data.userId.present ? data.userId.value : this.userId,
      firstName: data.firstName.present ? data.firstName.value : this.firstName,
      lastName: data.lastName.present ? data.lastName.value : this.lastName,
      username: data.username.present ? data.username.value : this.username,
      nickname: data.nickname.present ? data.nickname.value : this.nickname,
      position: data.position.present ? data.position.value : this.position,
      email: data.email.present ? data.email.value : this.email,
      profileImageUpdatedAt: data.profileImageUpdatedAt.present
          ? data.profileImageUpdatedAt.value
          : this.profileImageUpdatedAt,
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
          ..write('nickname: $nickname, ')
          ..write('position: $position, ')
          ..write('email: $email, ')
          ..write('profileImageUpdatedAt: $profileImageUpdatedAt, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    userId,
    firstName,
    lastName,
    username,
    nickname,
    position,
    email,
    profileImageUpdatedAt,
    expiresAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedUserProfile &&
          other.accountId == this.accountId &&
          other.userId == this.userId &&
          other.firstName == this.firstName &&
          other.lastName == this.lastName &&
          other.username == this.username &&
          other.nickname == this.nickname &&
          other.position == this.position &&
          other.email == this.email &&
          other.profileImageUpdatedAt == this.profileImageUpdatedAt &&
          other.expiresAt == this.expiresAt);
}

class CachedUserProfilesCompanion extends UpdateCompanion<CachedUserProfile> {
  final Value<String> accountId;
  final Value<String> userId;
  final Value<String> firstName;
  final Value<String> lastName;
  final Value<String> username;
  final Value<String> nickname;
  final Value<String> position;
  final Value<String> email;
  final Value<int> profileImageUpdatedAt;
  final Value<DateTime> expiresAt;
  final Value<int> rowid;
  const CachedUserProfilesCompanion({
    this.accountId = const Value.absent(),
    this.userId = const Value.absent(),
    this.firstName = const Value.absent(),
    this.lastName = const Value.absent(),
    this.username = const Value.absent(),
    this.nickname = const Value.absent(),
    this.position = const Value.absent(),
    this.email = const Value.absent(),
    this.profileImageUpdatedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedUserProfilesCompanion.insert({
    required String accountId,
    required String userId,
    required String firstName,
    required String lastName,
    required String username,
    this.nickname = const Value.absent(),
    this.position = const Value.absent(),
    this.email = const Value.absent(),
    this.profileImageUpdatedAt = const Value.absent(),
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
    Expression<String>? nickname,
    Expression<String>? position,
    Expression<String>? email,
    Expression<int>? profileImageUpdatedAt,
    Expression<DateTime>? expiresAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (userId != null) 'user_id': userId,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (username != null) 'username': username,
      if (nickname != null) 'nickname': nickname,
      if (position != null) 'position': position,
      if (email != null) 'email': email,
      if (profileImageUpdatedAt != null)
        'profile_image_updated_at': profileImageUpdatedAt,
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
    Value<String>? nickname,
    Value<String>? position,
    Value<String>? email,
    Value<int>? profileImageUpdatedAt,
    Value<DateTime>? expiresAt,
    Value<int>? rowid,
  }) {
    return CachedUserProfilesCompanion(
      accountId: accountId ?? this.accountId,
      userId: userId ?? this.userId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      username: username ?? this.username,
      nickname: nickname ?? this.nickname,
      position: position ?? this.position,
      email: email ?? this.email,
      profileImageUpdatedAt:
          profileImageUpdatedAt ?? this.profileImageUpdatedAt,
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
    if (nickname.present) {
      map['nickname'] = Variable<String>(nickname.value);
    }
    if (position.present) {
      map['position'] = Variable<String>(position.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (profileImageUpdatedAt.present) {
      map['profile_image_updated_at'] = Variable<int>(
        profileImageUpdatedAt.value,
      );
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
          ..write('nickname: $nickname, ')
          ..write('position: $position, ')
          ..write('email: $email, ')
          ..write('profileImageUpdatedAt: $profileImageUpdatedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecentEmojisTable extends RecentEmojis
    with TableInfo<$RecentEmojisTable, RecentEmoji> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecentEmojisTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _emojiNameMeta = const VerificationMeta(
    'emojiName',
  );
  @override
  late final GeneratedColumn<String> emojiName = GeneratedColumn<String>(
    'emoji_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastUsedAtMeta = const VerificationMeta(
    'lastUsedAt',
  );
  @override
  late final GeneratedColumn<int> lastUsedAt = GeneratedColumn<int>(
    'last_used_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [accountId, emojiName, lastUsedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recent_emojis';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecentEmoji> instance, {
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
    if (data.containsKey('emoji_name')) {
      context.handle(
        _emojiNameMeta,
        emojiName.isAcceptableOrUnknown(data['emoji_name']!, _emojiNameMeta),
      );
    } else if (isInserting) {
      context.missing(_emojiNameMeta);
    }
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastUsedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId, emojiName};
  @override
  RecentEmoji map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecentEmoji(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      emojiName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}emoji_name'],
      )!,
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_used_at'],
      )!,
    );
  }

  @override
  $RecentEmojisTable createAlias(String alias) {
    return $RecentEmojisTable(attachedDatabase, alias);
  }
}

class RecentEmoji extends DataClass implements Insertable<RecentEmoji> {
  final String accountId;
  final String emojiName;
  final int lastUsedAt;
  const RecentEmoji({
    required this.accountId,
    required this.emojiName,
    required this.lastUsedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['emoji_name'] = Variable<String>(emojiName);
    map['last_used_at'] = Variable<int>(lastUsedAt);
    return map;
  }

  RecentEmojisCompanion toCompanion(bool nullToAbsent) {
    return RecentEmojisCompanion(
      accountId: Value(accountId),
      emojiName: Value(emojiName),
      lastUsedAt: Value(lastUsedAt),
    );
  }

  factory RecentEmoji.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecentEmoji(
      accountId: serializer.fromJson<String>(json['accountId']),
      emojiName: serializer.fromJson<String>(json['emojiName']),
      lastUsedAt: serializer.fromJson<int>(json['lastUsedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'emojiName': serializer.toJson<String>(emojiName),
      'lastUsedAt': serializer.toJson<int>(lastUsedAt),
    };
  }

  RecentEmoji copyWith({
    String? accountId,
    String? emojiName,
    int? lastUsedAt,
  }) => RecentEmoji(
    accountId: accountId ?? this.accountId,
    emojiName: emojiName ?? this.emojiName,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );
  RecentEmoji copyWithCompanion(RecentEmojisCompanion data) {
    return RecentEmoji(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      emojiName: data.emojiName.present ? data.emojiName.value : this.emojiName,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecentEmoji(')
          ..write('accountId: $accountId, ')
          ..write('emojiName: $emojiName, ')
          ..write('lastUsedAt: $lastUsedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, emojiName, lastUsedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecentEmoji &&
          other.accountId == this.accountId &&
          other.emojiName == this.emojiName &&
          other.lastUsedAt == this.lastUsedAt);
}

class RecentEmojisCompanion extends UpdateCompanion<RecentEmoji> {
  final Value<String> accountId;
  final Value<String> emojiName;
  final Value<int> lastUsedAt;
  final Value<int> rowid;
  const RecentEmojisCompanion({
    this.accountId = const Value.absent(),
    this.emojiName = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecentEmojisCompanion.insert({
    required String accountId,
    required String emojiName,
    required int lastUsedAt,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       emojiName = Value(emojiName),
       lastUsedAt = Value(lastUsedAt);
  static Insertable<RecentEmoji> custom({
    Expression<String>? accountId,
    Expression<String>? emojiName,
    Expression<int>? lastUsedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (emojiName != null) 'emoji_name': emojiName,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecentEmojisCompanion copyWith({
    Value<String>? accountId,
    Value<String>? emojiName,
    Value<int>? lastUsedAt,
    Value<int>? rowid,
  }) {
    return RecentEmojisCompanion(
      accountId: accountId ?? this.accountId,
      emojiName: emojiName ?? this.emojiName,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (emojiName.present) {
      map['emoji_name'] = Variable<String>(emojiName.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<int>(lastUsedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecentEmojisCompanion(')
          ..write('accountId: $accountId, ')
          ..write('emojiName: $emojiName, ')
          ..write('lastUsedAt: $lastUsedAt, ')
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
  late final $RecentEmojisTable recentEmojis = $RecentEmojisTable(this);
  late final Index cachedUserProfilesAccountUsernameIdx = Index(
    'cached_user_profiles_account_username_idx',
    'CREATE INDEX cached_user_profiles_account_username_idx ON cached_user_profiles (account_id, username COLLATE NOCASE)',
  );
  late final Index recentEmojisAccountLastUsedAtIdx = Index(
    'recent_emojis_account_last_used_at_idx',
    'CREATE INDEX recent_emojis_account_last_used_at_idx ON recent_emojis (account_id, last_used_at DESC)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedUserProfiles,
    recentEmojis,
    cachedUserProfilesAccountUsernameIdx,
    recentEmojisAccountLastUsedAtIdx,
  ];
}

typedef $$CachedUserProfilesTableCreateCompanionBuilder =
    CachedUserProfilesCompanion Function({
      required String accountId,
      required String userId,
      required String firstName,
      required String lastName,
      required String username,
      Value<String> nickname,
      Value<String> position,
      Value<String> email,
      Value<int> profileImageUpdatedAt,
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
      Value<String> nickname,
      Value<String> position,
      Value<String> email,
      Value<int> profileImageUpdatedAt,
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

  ColumnFilters<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get profileImageUpdatedAt => $composableBuilder(
    column: $table.profileImageUpdatedAt,
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

  ColumnOrderings<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get profileImageUpdatedAt => $composableBuilder(
    column: $table.profileImageUpdatedAt,
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

  GeneratedColumn<String> get nickname =>
      $composableBuilder(column: $table.nickname, builder: (column) => column);

  GeneratedColumn<String> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<int> get profileImageUpdatedAt => $composableBuilder(
    column: $table.profileImageUpdatedAt,
    builder: (column) => column,
  );

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
                Value<String> nickname = const Value.absent(),
                Value<String> position = const Value.absent(),
                Value<String> email = const Value.absent(),
                Value<int> profileImageUpdatedAt = const Value.absent(),
                Value<DateTime> expiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedUserProfilesCompanion(
                accountId: accountId,
                userId: userId,
                firstName: firstName,
                lastName: lastName,
                username: username,
                nickname: nickname,
                position: position,
                email: email,
                profileImageUpdatedAt: profileImageUpdatedAt,
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
                Value<String> nickname = const Value.absent(),
                Value<String> position = const Value.absent(),
                Value<String> email = const Value.absent(),
                Value<int> profileImageUpdatedAt = const Value.absent(),
                required DateTime expiresAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedUserProfilesCompanion.insert(
                accountId: accountId,
                userId: userId,
                firstName: firstName,
                lastName: lastName,
                username: username,
                nickname: nickname,
                position: position,
                email: email,
                profileImageUpdatedAt: profileImageUpdatedAt,
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
typedef $$RecentEmojisTableCreateCompanionBuilder =
    RecentEmojisCompanion Function({
      required String accountId,
      required String emojiName,
      required int lastUsedAt,
      Value<int> rowid,
    });
typedef $$RecentEmojisTableUpdateCompanionBuilder =
    RecentEmojisCompanion Function({
      Value<String> accountId,
      Value<String> emojiName,
      Value<int> lastUsedAt,
      Value<int> rowid,
    });

class $$RecentEmojisTableFilterComposer
    extends Composer<_$AppDatabase, $RecentEmojisTable> {
  $$RecentEmojisTableFilterComposer({
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

  ColumnFilters<String> get emojiName => $composableBuilder(
    column: $table.emojiName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecentEmojisTableOrderingComposer
    extends Composer<_$AppDatabase, $RecentEmojisTable> {
  $$RecentEmojisTableOrderingComposer({
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

  ColumnOrderings<String> get emojiName => $composableBuilder(
    column: $table.emojiName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecentEmojisTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecentEmojisTable> {
  $$RecentEmojisTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get emojiName =>
      $composableBuilder(column: $table.emojiName, builder: (column) => column);

  GeneratedColumn<int> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );
}

class $$RecentEmojisTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecentEmojisTable,
          RecentEmoji,
          $$RecentEmojisTableFilterComposer,
          $$RecentEmojisTableOrderingComposer,
          $$RecentEmojisTableAnnotationComposer,
          $$RecentEmojisTableCreateCompanionBuilder,
          $$RecentEmojisTableUpdateCompanionBuilder,
          (
            RecentEmoji,
            BaseReferences<_$AppDatabase, $RecentEmojisTable, RecentEmoji>,
          ),
          RecentEmoji,
          PrefetchHooks Function()
        > {
  $$RecentEmojisTableTableManager(_$AppDatabase db, $RecentEmojisTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecentEmojisTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecentEmojisTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecentEmojisTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> emojiName = const Value.absent(),
                Value<int> lastUsedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecentEmojisCompanion(
                accountId: accountId,
                emojiName: emojiName,
                lastUsedAt: lastUsedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String emojiName,
                required int lastUsedAt,
                Value<int> rowid = const Value.absent(),
              }) => RecentEmojisCompanion.insert(
                accountId: accountId,
                emojiName: emojiName,
                lastUsedAt: lastUsedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecentEmojisTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecentEmojisTable,
      RecentEmoji,
      $$RecentEmojisTableFilterComposer,
      $$RecentEmojisTableOrderingComposer,
      $$RecentEmojisTableAnnotationComposer,
      $$RecentEmojisTableCreateCompanionBuilder,
      $$RecentEmojisTableUpdateCompanionBuilder,
      (
        RecentEmoji,
        BaseReferences<_$AppDatabase, $RecentEmojisTable, RecentEmoji>,
      ),
      RecentEmoji,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CachedUserProfilesTableTableManager get cachedUserProfiles =>
      $$CachedUserProfilesTableTableManager(_db, _db.cachedUserProfiles);
  $$RecentEmojisTableTableManager get recentEmojis =>
      $$RecentEmojisTableTableManager(_db, _db.recentEmojis);
}
