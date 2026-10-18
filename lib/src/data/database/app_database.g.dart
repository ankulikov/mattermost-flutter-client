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

class $CachedUserGroupsTable extends CachedUserGroups
    with TableInfo<$CachedUserGroupsTable, CachedUserGroup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedUserGroupsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _allowReferenceMeta = const VerificationMeta(
    'allowReference',
  );
  @override
  late final GeneratedColumn<bool> allowReference = GeneratedColumn<bool>(
    'allow_reference',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("allow_reference" IN (0, 1))',
    ),
  );
  static const VerificationMeta _deleteAtMeta = const VerificationMeta(
    'deleteAt',
  );
  @override
  late final GeneratedColumn<int> deleteAt = GeneratedColumn<int>(
    'delete_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
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
    groupId,
    name,
    displayName,
    allowReference,
    deleteAt,
    expiresAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_user_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedUserGroup> instance, {
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
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('allow_reference')) {
      context.handle(
        _allowReferenceMeta,
        allowReference.isAcceptableOrUnknown(
          data['allow_reference']!,
          _allowReferenceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_allowReferenceMeta);
    }
    if (data.containsKey('delete_at')) {
      context.handle(
        _deleteAtMeta,
        deleteAt.isAcceptableOrUnknown(data['delete_at']!, _deleteAtMeta),
      );
    } else if (isInserting) {
      context.missing(_deleteAtMeta);
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
  Set<GeneratedColumn> get $primaryKey => {accountId, groupId};
  @override
  CachedUserGroup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedUserGroup(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      allowReference: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}allow_reference'],
      )!,
      deleteAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}delete_at'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      )!,
    );
  }

  @override
  $CachedUserGroupsTable createAlias(String alias) {
    return $CachedUserGroupsTable(attachedDatabase, alias);
  }
}

class CachedUserGroup extends DataClass implements Insertable<CachedUserGroup> {
  final String accountId;
  final String groupId;
  final String name;
  final String displayName;
  final bool allowReference;
  final int deleteAt;
  final DateTime expiresAt;
  const CachedUserGroup({
    required this.accountId,
    required this.groupId,
    required this.name,
    required this.displayName,
    required this.allowReference,
    required this.deleteAt,
    required this.expiresAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['group_id'] = Variable<String>(groupId);
    map['name'] = Variable<String>(name);
    map['display_name'] = Variable<String>(displayName);
    map['allow_reference'] = Variable<bool>(allowReference);
    map['delete_at'] = Variable<int>(deleteAt);
    map['expires_at'] = Variable<DateTime>(expiresAt);
    return map;
  }

  CachedUserGroupsCompanion toCompanion(bool nullToAbsent) {
    return CachedUserGroupsCompanion(
      accountId: Value(accountId),
      groupId: Value(groupId),
      name: Value(name),
      displayName: Value(displayName),
      allowReference: Value(allowReference),
      deleteAt: Value(deleteAt),
      expiresAt: Value(expiresAt),
    );
  }

  factory CachedUserGroup.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedUserGroup(
      accountId: serializer.fromJson<String>(json['accountId']),
      groupId: serializer.fromJson<String>(json['groupId']),
      name: serializer.fromJson<String>(json['name']),
      displayName: serializer.fromJson<String>(json['displayName']),
      allowReference: serializer.fromJson<bool>(json['allowReference']),
      deleteAt: serializer.fromJson<int>(json['deleteAt']),
      expiresAt: serializer.fromJson<DateTime>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'groupId': serializer.toJson<String>(groupId),
      'name': serializer.toJson<String>(name),
      'displayName': serializer.toJson<String>(displayName),
      'allowReference': serializer.toJson<bool>(allowReference),
      'deleteAt': serializer.toJson<int>(deleteAt),
      'expiresAt': serializer.toJson<DateTime>(expiresAt),
    };
  }

  CachedUserGroup copyWith({
    String? accountId,
    String? groupId,
    String? name,
    String? displayName,
    bool? allowReference,
    int? deleteAt,
    DateTime? expiresAt,
  }) => CachedUserGroup(
    accountId: accountId ?? this.accountId,
    groupId: groupId ?? this.groupId,
    name: name ?? this.name,
    displayName: displayName ?? this.displayName,
    allowReference: allowReference ?? this.allowReference,
    deleteAt: deleteAt ?? this.deleteAt,
    expiresAt: expiresAt ?? this.expiresAt,
  );
  CachedUserGroup copyWithCompanion(CachedUserGroupsCompanion data) {
    return CachedUserGroup(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      name: data.name.present ? data.name.value : this.name,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      allowReference: data.allowReference.present
          ? data.allowReference.value
          : this.allowReference,
      deleteAt: data.deleteAt.present ? data.deleteAt.value : this.deleteAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedUserGroup(')
          ..write('accountId: $accountId, ')
          ..write('groupId: $groupId, ')
          ..write('name: $name, ')
          ..write('displayName: $displayName, ')
          ..write('allowReference: $allowReference, ')
          ..write('deleteAt: $deleteAt, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountId,
    groupId,
    name,
    displayName,
    allowReference,
    deleteAt,
    expiresAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedUserGroup &&
          other.accountId == this.accountId &&
          other.groupId == this.groupId &&
          other.name == this.name &&
          other.displayName == this.displayName &&
          other.allowReference == this.allowReference &&
          other.deleteAt == this.deleteAt &&
          other.expiresAt == this.expiresAt);
}

class CachedUserGroupsCompanion extends UpdateCompanion<CachedUserGroup> {
  final Value<String> accountId;
  final Value<String> groupId;
  final Value<String> name;
  final Value<String> displayName;
  final Value<bool> allowReference;
  final Value<int> deleteAt;
  final Value<DateTime> expiresAt;
  final Value<int> rowid;
  const CachedUserGroupsCompanion({
    this.accountId = const Value.absent(),
    this.groupId = const Value.absent(),
    this.name = const Value.absent(),
    this.displayName = const Value.absent(),
    this.allowReference = const Value.absent(),
    this.deleteAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedUserGroupsCompanion.insert({
    required String accountId,
    required String groupId,
    required String name,
    required String displayName,
    required bool allowReference,
    required int deleteAt,
    required DateTime expiresAt,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       groupId = Value(groupId),
       name = Value(name),
       displayName = Value(displayName),
       allowReference = Value(allowReference),
       deleteAt = Value(deleteAt),
       expiresAt = Value(expiresAt);
  static Insertable<CachedUserGroup> custom({
    Expression<String>? accountId,
    Expression<String>? groupId,
    Expression<String>? name,
    Expression<String>? displayName,
    Expression<bool>? allowReference,
    Expression<int>? deleteAt,
    Expression<DateTime>? expiresAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (groupId != null) 'group_id': groupId,
      if (name != null) 'name': name,
      if (displayName != null) 'display_name': displayName,
      if (allowReference != null) 'allow_reference': allowReference,
      if (deleteAt != null) 'delete_at': deleteAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedUserGroupsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? groupId,
    Value<String>? name,
    Value<String>? displayName,
    Value<bool>? allowReference,
    Value<int>? deleteAt,
    Value<DateTime>? expiresAt,
    Value<int>? rowid,
  }) {
    return CachedUserGroupsCompanion(
      accountId: accountId ?? this.accountId,
      groupId: groupId ?? this.groupId,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      allowReference: allowReference ?? this.allowReference,
      deleteAt: deleteAt ?? this.deleteAt,
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
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (allowReference.present) {
      map['allow_reference'] = Variable<bool>(allowReference.value);
    }
    if (deleteAt.present) {
      map['delete_at'] = Variable<int>(deleteAt.value);
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
    return (StringBuffer('CachedUserGroupsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('groupId: $groupId, ')
          ..write('name: $name, ')
          ..write('displayName: $displayName, ')
          ..write('allowReference: $allowReference, ')
          ..write('deleteAt: $deleteAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InboxCountersTable extends InboxCounters
    with TableInfo<$InboxCountersTable, InboxCounter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InboxCountersTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _newMessageCountMeta = const VerificationMeta(
    'newMessageCount',
  );
  @override
  late final GeneratedColumn<int> newMessageCount = GeneratedColumn<int>(
    'new_message_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _postponedMessageCountMeta =
      const VerificationMeta('postponedMessageCount');
  @override
  late final GeneratedColumn<int> postponedMessageCount = GeneratedColumn<int>(
    'postponed_message_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    newMessageCount,
    postponedMessageCount,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inbox_counters';
  @override
  VerificationContext validateIntegrity(
    Insertable<InboxCounter> instance, {
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
    if (data.containsKey('new_message_count')) {
      context.handle(
        _newMessageCountMeta,
        newMessageCount.isAcceptableOrUnknown(
          data['new_message_count']!,
          _newMessageCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_newMessageCountMeta);
    }
    if (data.containsKey('postponed_message_count')) {
      context.handle(
        _postponedMessageCountMeta,
        postponedMessageCount.isAcceptableOrUnknown(
          data['postponed_message_count']!,
          _postponedMessageCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_postponedMessageCountMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId};
  @override
  InboxCounter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InboxCounter(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      newMessageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}new_message_count'],
      )!,
      postponedMessageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}postponed_message_count'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $InboxCountersTable createAlias(String alias) {
    return $InboxCountersTable(attachedDatabase, alias);
  }
}

class InboxCounter extends DataClass implements Insertable<InboxCounter> {
  final String accountId;
  final int newMessageCount;
  final int postponedMessageCount;
  final DateTime updatedAt;
  const InboxCounter({
    required this.accountId,
    required this.newMessageCount,
    required this.postponedMessageCount,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['new_message_count'] = Variable<int>(newMessageCount);
    map['postponed_message_count'] = Variable<int>(postponedMessageCount);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  InboxCountersCompanion toCompanion(bool nullToAbsent) {
    return InboxCountersCompanion(
      accountId: Value(accountId),
      newMessageCount: Value(newMessageCount),
      postponedMessageCount: Value(postponedMessageCount),
      updatedAt: Value(updatedAt),
    );
  }

  factory InboxCounter.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InboxCounter(
      accountId: serializer.fromJson<String>(json['accountId']),
      newMessageCount: serializer.fromJson<int>(json['newMessageCount']),
      postponedMessageCount: serializer.fromJson<int>(
        json['postponedMessageCount'],
      ),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'newMessageCount': serializer.toJson<int>(newMessageCount),
      'postponedMessageCount': serializer.toJson<int>(postponedMessageCount),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  InboxCounter copyWith({
    String? accountId,
    int? newMessageCount,
    int? postponedMessageCount,
    DateTime? updatedAt,
  }) => InboxCounter(
    accountId: accountId ?? this.accountId,
    newMessageCount: newMessageCount ?? this.newMessageCount,
    postponedMessageCount: postponedMessageCount ?? this.postponedMessageCount,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  InboxCounter copyWithCompanion(InboxCountersCompanion data) {
    return InboxCounter(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      newMessageCount: data.newMessageCount.present
          ? data.newMessageCount.value
          : this.newMessageCount,
      postponedMessageCount: data.postponedMessageCount.present
          ? data.postponedMessageCount.value
          : this.postponedMessageCount,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InboxCounter(')
          ..write('accountId: $accountId, ')
          ..write('newMessageCount: $newMessageCount, ')
          ..write('postponedMessageCount: $postponedMessageCount, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(accountId, newMessageCount, postponedMessageCount, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InboxCounter &&
          other.accountId == this.accountId &&
          other.newMessageCount == this.newMessageCount &&
          other.postponedMessageCount == this.postponedMessageCount &&
          other.updatedAt == this.updatedAt);
}

class InboxCountersCompanion extends UpdateCompanion<InboxCounter> {
  final Value<String> accountId;
  final Value<int> newMessageCount;
  final Value<int> postponedMessageCount;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const InboxCountersCompanion({
    this.accountId = const Value.absent(),
    this.newMessageCount = const Value.absent(),
    this.postponedMessageCount = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InboxCountersCompanion.insert({
    required String accountId,
    required int newMessageCount,
    required int postponedMessageCount,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       newMessageCount = Value(newMessageCount),
       postponedMessageCount = Value(postponedMessageCount),
       updatedAt = Value(updatedAt);
  static Insertable<InboxCounter> custom({
    Expression<String>? accountId,
    Expression<int>? newMessageCount,
    Expression<int>? postponedMessageCount,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (newMessageCount != null) 'new_message_count': newMessageCount,
      if (postponedMessageCount != null)
        'postponed_message_count': postponedMessageCount,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InboxCountersCompanion copyWith({
    Value<String>? accountId,
    Value<int>? newMessageCount,
    Value<int>? postponedMessageCount,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return InboxCountersCompanion(
      accountId: accountId ?? this.accountId,
      newMessageCount: newMessageCount ?? this.newMessageCount,
      postponedMessageCount:
          postponedMessageCount ?? this.postponedMessageCount,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (newMessageCount.present) {
      map['new_message_count'] = Variable<int>(newMessageCount.value);
    }
    if (postponedMessageCount.present) {
      map['postponed_message_count'] = Variable<int>(
        postponedMessageCount.value,
      );
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
    return (StringBuffer('InboxCountersCompanion(')
          ..write('accountId: $accountId, ')
          ..write('newMessageCount: $newMessageCount, ')
          ..write('postponedMessageCount: $postponedMessageCount, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserPreferencesRowsTable extends UserPreferencesRows
    with TableInfo<$UserPreferencesRowsTable, UserPreferencesRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserPreferencesRowsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _preferencesJsonMeta = const VerificationMeta(
    'preferencesJson',
  );
  @override
  late final GeneratedColumn<String> preferencesJson = GeneratedColumn<String>(
    'preferences_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastCheckUpdateMeta = const VerificationMeta(
    'lastCheckUpdate',
  );
  @override
  late final GeneratedColumn<DateTime> lastCheckUpdate =
      GeneratedColumn<DateTime>(
        'last_check_update',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    accountId,
    preferencesJson,
    lastCheckUpdate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserPreferencesRow> instance, {
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
    if (data.containsKey('preferences_json')) {
      context.handle(
        _preferencesJsonMeta,
        preferencesJson.isAcceptableOrUnknown(
          data['preferences_json']!,
          _preferencesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_preferencesJsonMeta);
    }
    if (data.containsKey('last_check_update')) {
      context.handle(
        _lastCheckUpdateMeta,
        lastCheckUpdate.isAcceptableOrUnknown(
          data['last_check_update']!,
          _lastCheckUpdateMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {accountId};
  @override
  UserPreferencesRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserPreferencesRow(
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      preferencesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preferences_json'],
      )!,
      lastCheckUpdate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_check_update'],
      ),
    );
  }

  @override
  $UserPreferencesRowsTable createAlias(String alias) {
    return $UserPreferencesRowsTable(attachedDatabase, alias);
  }
}

class UserPreferencesRow extends DataClass
    implements Insertable<UserPreferencesRow> {
  final String accountId;
  final String preferencesJson;
  final DateTime? lastCheckUpdate;
  const UserPreferencesRow({
    required this.accountId,
    required this.preferencesJson,
    this.lastCheckUpdate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_id'] = Variable<String>(accountId);
    map['preferences_json'] = Variable<String>(preferencesJson);
    if (!nullToAbsent || lastCheckUpdate != null) {
      map['last_check_update'] = Variable<DateTime>(lastCheckUpdate);
    }
    return map;
  }

  UserPreferencesRowsCompanion toCompanion(bool nullToAbsent) {
    return UserPreferencesRowsCompanion(
      accountId: Value(accountId),
      preferencesJson: Value(preferencesJson),
      lastCheckUpdate: lastCheckUpdate == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCheckUpdate),
    );
  }

  factory UserPreferencesRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserPreferencesRow(
      accountId: serializer.fromJson<String>(json['accountId']),
      preferencesJson: serializer.fromJson<String>(json['preferencesJson']),
      lastCheckUpdate: serializer.fromJson<DateTime?>(json['lastCheckUpdate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountId': serializer.toJson<String>(accountId),
      'preferencesJson': serializer.toJson<String>(preferencesJson),
      'lastCheckUpdate': serializer.toJson<DateTime?>(lastCheckUpdate),
    };
  }

  UserPreferencesRow copyWith({
    String? accountId,
    String? preferencesJson,
    Value<DateTime?> lastCheckUpdate = const Value.absent(),
  }) => UserPreferencesRow(
    accountId: accountId ?? this.accountId,
    preferencesJson: preferencesJson ?? this.preferencesJson,
    lastCheckUpdate: lastCheckUpdate.present
        ? lastCheckUpdate.value
        : this.lastCheckUpdate,
  );
  UserPreferencesRow copyWithCompanion(UserPreferencesRowsCompanion data) {
    return UserPreferencesRow(
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      preferencesJson: data.preferencesJson.present
          ? data.preferencesJson.value
          : this.preferencesJson,
      lastCheckUpdate: data.lastCheckUpdate.present
          ? data.lastCheckUpdate.value
          : this.lastCheckUpdate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserPreferencesRow(')
          ..write('accountId: $accountId, ')
          ..write('preferencesJson: $preferencesJson, ')
          ..write('lastCheckUpdate: $lastCheckUpdate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountId, preferencesJson, lastCheckUpdate);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserPreferencesRow &&
          other.accountId == this.accountId &&
          other.preferencesJson == this.preferencesJson &&
          other.lastCheckUpdate == this.lastCheckUpdate);
}

class UserPreferencesRowsCompanion extends UpdateCompanion<UserPreferencesRow> {
  final Value<String> accountId;
  final Value<String> preferencesJson;
  final Value<DateTime?> lastCheckUpdate;
  final Value<int> rowid;
  const UserPreferencesRowsCompanion({
    this.accountId = const Value.absent(),
    this.preferencesJson = const Value.absent(),
    this.lastCheckUpdate = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserPreferencesRowsCompanion.insert({
    required String accountId,
    required String preferencesJson,
    this.lastCheckUpdate = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : accountId = Value(accountId),
       preferencesJson = Value(preferencesJson);
  static Insertable<UserPreferencesRow> custom({
    Expression<String>? accountId,
    Expression<String>? preferencesJson,
    Expression<DateTime>? lastCheckUpdate,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountId != null) 'account_id': accountId,
      if (preferencesJson != null) 'preferences_json': preferencesJson,
      if (lastCheckUpdate != null) 'last_check_update': lastCheckUpdate,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UserPreferencesRowsCompanion copyWith({
    Value<String>? accountId,
    Value<String>? preferencesJson,
    Value<DateTime?>? lastCheckUpdate,
    Value<int>? rowid,
  }) {
    return UserPreferencesRowsCompanion(
      accountId: accountId ?? this.accountId,
      preferencesJson: preferencesJson ?? this.preferencesJson,
      lastCheckUpdate: lastCheckUpdate ?? this.lastCheckUpdate,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (preferencesJson.present) {
      map['preferences_json'] = Variable<String>(preferencesJson.value);
    }
    if (lastCheckUpdate.present) {
      map['last_check_update'] = Variable<DateTime>(lastCheckUpdate.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserPreferencesRowsCompanion(')
          ..write('accountId: $accountId, ')
          ..write('preferencesJson: $preferencesJson, ')
          ..write('lastCheckUpdate: $lastCheckUpdate, ')
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
  late final $CachedUserGroupsTable cachedUserGroups = $CachedUserGroupsTable(
    this,
  );
  late final $InboxCountersTable inboxCounters = $InboxCountersTable(this);
  late final $UserPreferencesRowsTable userPreferencesRows =
      $UserPreferencesRowsTable(this);
  late final Index cachedUserProfilesAccountUsernameIdx = Index(
    'cached_user_profiles_account_username_idx',
    'CREATE INDEX cached_user_profiles_account_username_idx ON cached_user_profiles (account_id, username COLLATE NOCASE)',
  );
  late final Index recentEmojisAccountLastUsedAtIdx = Index(
    'recent_emojis_account_last_used_at_idx',
    'CREATE INDEX recent_emojis_account_last_used_at_idx ON recent_emojis (account_id, last_used_at DESC)',
  );
  late final Index cachedUserGroupsAccountNameIdx = Index(
    'cached_user_groups_account_name_idx',
    'CREATE INDEX cached_user_groups_account_name_idx ON cached_user_groups (account_id, name COLLATE NOCASE)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedUserProfiles,
    recentEmojis,
    cachedUserGroups,
    inboxCounters,
    userPreferencesRows,
    cachedUserProfilesAccountUsernameIdx,
    recentEmojisAccountLastUsedAtIdx,
    cachedUserGroupsAccountNameIdx,
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
typedef $$CachedUserGroupsTableCreateCompanionBuilder =
    CachedUserGroupsCompanion Function({
      required String accountId,
      required String groupId,
      required String name,
      required String displayName,
      required bool allowReference,
      required int deleteAt,
      required DateTime expiresAt,
      Value<int> rowid,
    });
typedef $$CachedUserGroupsTableUpdateCompanionBuilder =
    CachedUserGroupsCompanion Function({
      Value<String> accountId,
      Value<String> groupId,
      Value<String> name,
      Value<String> displayName,
      Value<bool> allowReference,
      Value<int> deleteAt,
      Value<DateTime> expiresAt,
      Value<int> rowid,
    });

class $$CachedUserGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedUserGroupsTable> {
  $$CachedUserGroupsTableFilterComposer({
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

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allowReference => $composableBuilder(
    column: $table.allowReference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deleteAt => $composableBuilder(
    column: $table.deleteAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedUserGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedUserGroupsTable> {
  $$CachedUserGroupsTableOrderingComposer({
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

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allowReference => $composableBuilder(
    column: $table.allowReference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deleteAt => $composableBuilder(
    column: $table.deleteAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedUserGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedUserGroupsTable> {
  $$CachedUserGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get allowReference => $composableBuilder(
    column: $table.allowReference,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deleteAt =>
      $composableBuilder(column: $table.deleteAt, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);
}

class $$CachedUserGroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedUserGroupsTable,
          CachedUserGroup,
          $$CachedUserGroupsTableFilterComposer,
          $$CachedUserGroupsTableOrderingComposer,
          $$CachedUserGroupsTableAnnotationComposer,
          $$CachedUserGroupsTableCreateCompanionBuilder,
          $$CachedUserGroupsTableUpdateCompanionBuilder,
          (
            CachedUserGroup,
            BaseReferences<
              _$AppDatabase,
              $CachedUserGroupsTable,
              CachedUserGroup
            >,
          ),
          CachedUserGroup,
          PrefetchHooks Function()
        > {
  $$CachedUserGroupsTableTableManager(
    _$AppDatabase db,
    $CachedUserGroupsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedUserGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedUserGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedUserGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> groupId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<bool> allowReference = const Value.absent(),
                Value<int> deleteAt = const Value.absent(),
                Value<DateTime> expiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedUserGroupsCompanion(
                accountId: accountId,
                groupId: groupId,
                name: name,
                displayName: displayName,
                allowReference: allowReference,
                deleteAt: deleteAt,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String groupId,
                required String name,
                required String displayName,
                required bool allowReference,
                required int deleteAt,
                required DateTime expiresAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedUserGroupsCompanion.insert(
                accountId: accountId,
                groupId: groupId,
                name: name,
                displayName: displayName,
                allowReference: allowReference,
                deleteAt: deleteAt,
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

typedef $$CachedUserGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedUserGroupsTable,
      CachedUserGroup,
      $$CachedUserGroupsTableFilterComposer,
      $$CachedUserGroupsTableOrderingComposer,
      $$CachedUserGroupsTableAnnotationComposer,
      $$CachedUserGroupsTableCreateCompanionBuilder,
      $$CachedUserGroupsTableUpdateCompanionBuilder,
      (
        CachedUserGroup,
        BaseReferences<_$AppDatabase, $CachedUserGroupsTable, CachedUserGroup>,
      ),
      CachedUserGroup,
      PrefetchHooks Function()
    >;
typedef $$InboxCountersTableCreateCompanionBuilder =
    InboxCountersCompanion Function({
      required String accountId,
      required int newMessageCount,
      required int postponedMessageCount,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$InboxCountersTableUpdateCompanionBuilder =
    InboxCountersCompanion Function({
      Value<String> accountId,
      Value<int> newMessageCount,
      Value<int> postponedMessageCount,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$InboxCountersTableFilterComposer
    extends Composer<_$AppDatabase, $InboxCountersTable> {
  $$InboxCountersTableFilterComposer({
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

  ColumnFilters<int> get newMessageCount => $composableBuilder(
    column: $table.newMessageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get postponedMessageCount => $composableBuilder(
    column: $table.postponedMessageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InboxCountersTableOrderingComposer
    extends Composer<_$AppDatabase, $InboxCountersTable> {
  $$InboxCountersTableOrderingComposer({
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

  ColumnOrderings<int> get newMessageCount => $composableBuilder(
    column: $table.newMessageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get postponedMessageCount => $composableBuilder(
    column: $table.postponedMessageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InboxCountersTableAnnotationComposer
    extends Composer<_$AppDatabase, $InboxCountersTable> {
  $$InboxCountersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<int> get newMessageCount => $composableBuilder(
    column: $table.newMessageCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get postponedMessageCount => $composableBuilder(
    column: $table.postponedMessageCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$InboxCountersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InboxCountersTable,
          InboxCounter,
          $$InboxCountersTableFilterComposer,
          $$InboxCountersTableOrderingComposer,
          $$InboxCountersTableAnnotationComposer,
          $$InboxCountersTableCreateCompanionBuilder,
          $$InboxCountersTableUpdateCompanionBuilder,
          (
            InboxCounter,
            BaseReferences<_$AppDatabase, $InboxCountersTable, InboxCounter>,
          ),
          InboxCounter,
          PrefetchHooks Function()
        > {
  $$InboxCountersTableTableManager(_$AppDatabase db, $InboxCountersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InboxCountersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InboxCountersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InboxCountersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<int> newMessageCount = const Value.absent(),
                Value<int> postponedMessageCount = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InboxCountersCompanion(
                accountId: accountId,
                newMessageCount: newMessageCount,
                postponedMessageCount: postponedMessageCount,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required int newMessageCount,
                required int postponedMessageCount,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => InboxCountersCompanion.insert(
                accountId: accountId,
                newMessageCount: newMessageCount,
                postponedMessageCount: postponedMessageCount,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InboxCountersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InboxCountersTable,
      InboxCounter,
      $$InboxCountersTableFilterComposer,
      $$InboxCountersTableOrderingComposer,
      $$InboxCountersTableAnnotationComposer,
      $$InboxCountersTableCreateCompanionBuilder,
      $$InboxCountersTableUpdateCompanionBuilder,
      (
        InboxCounter,
        BaseReferences<_$AppDatabase, $InboxCountersTable, InboxCounter>,
      ),
      InboxCounter,
      PrefetchHooks Function()
    >;
typedef $$UserPreferencesRowsTableCreateCompanionBuilder =
    UserPreferencesRowsCompanion Function({
      required String accountId,
      required String preferencesJson,
      Value<DateTime?> lastCheckUpdate,
      Value<int> rowid,
    });
typedef $$UserPreferencesRowsTableUpdateCompanionBuilder =
    UserPreferencesRowsCompanion Function({
      Value<String> accountId,
      Value<String> preferencesJson,
      Value<DateTime?> lastCheckUpdate,
      Value<int> rowid,
    });

class $$UserPreferencesRowsTableFilterComposer
    extends Composer<_$AppDatabase, $UserPreferencesRowsTable> {
  $$UserPreferencesRowsTableFilterComposer({
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

  ColumnFilters<String> get preferencesJson => $composableBuilder(
    column: $table.preferencesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastCheckUpdate => $composableBuilder(
    column: $table.lastCheckUpdate,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UserPreferencesRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $UserPreferencesRowsTable> {
  $$UserPreferencesRowsTableOrderingComposer({
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

  ColumnOrderings<String> get preferencesJson => $composableBuilder(
    column: $table.preferencesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastCheckUpdate => $composableBuilder(
    column: $table.lastCheckUpdate,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UserPreferencesRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserPreferencesRowsTable> {
  $$UserPreferencesRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get preferencesJson => $composableBuilder(
    column: $table.preferencesJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastCheckUpdate => $composableBuilder(
    column: $table.lastCheckUpdate,
    builder: (column) => column,
  );
}

class $$UserPreferencesRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserPreferencesRowsTable,
          UserPreferencesRow,
          $$UserPreferencesRowsTableFilterComposer,
          $$UserPreferencesRowsTableOrderingComposer,
          $$UserPreferencesRowsTableAnnotationComposer,
          $$UserPreferencesRowsTableCreateCompanionBuilder,
          $$UserPreferencesRowsTableUpdateCompanionBuilder,
          (
            UserPreferencesRow,
            BaseReferences<
              _$AppDatabase,
              $UserPreferencesRowsTable,
              UserPreferencesRow
            >,
          ),
          UserPreferencesRow,
          PrefetchHooks Function()
        > {
  $$UserPreferencesRowsTableTableManager(
    _$AppDatabase db,
    $UserPreferencesRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserPreferencesRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserPreferencesRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$UserPreferencesRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> accountId = const Value.absent(),
                Value<String> preferencesJson = const Value.absent(),
                Value<DateTime?> lastCheckUpdate = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UserPreferencesRowsCompanion(
                accountId: accountId,
                preferencesJson: preferencesJson,
                lastCheckUpdate: lastCheckUpdate,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountId,
                required String preferencesJson,
                Value<DateTime?> lastCheckUpdate = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UserPreferencesRowsCompanion.insert(
                accountId: accountId,
                preferencesJson: preferencesJson,
                lastCheckUpdate: lastCheckUpdate,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UserPreferencesRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserPreferencesRowsTable,
      UserPreferencesRow,
      $$UserPreferencesRowsTableFilterComposer,
      $$UserPreferencesRowsTableOrderingComposer,
      $$UserPreferencesRowsTableAnnotationComposer,
      $$UserPreferencesRowsTableCreateCompanionBuilder,
      $$UserPreferencesRowsTableUpdateCompanionBuilder,
      (
        UserPreferencesRow,
        BaseReferences<
          _$AppDatabase,
          $UserPreferencesRowsTable,
          UserPreferencesRow
        >,
      ),
      UserPreferencesRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CachedUserProfilesTableTableManager get cachedUserProfiles =>
      $$CachedUserProfilesTableTableManager(_db, _db.cachedUserProfiles);
  $$RecentEmojisTableTableManager get recentEmojis =>
      $$RecentEmojisTableTableManager(_db, _db.recentEmojis);
  $$CachedUserGroupsTableTableManager get cachedUserGroups =>
      $$CachedUserGroupsTableTableManager(_db, _db.cachedUserGroups);
  $$InboxCountersTableTableManager get inboxCounters =>
      $$InboxCountersTableTableManager(_db, _db.inboxCounters);
  $$UserPreferencesRowsTableTableManager get userPreferencesRows =>
      $$UserPreferencesRowsTableTableManager(_db, _db.userPreferencesRows);
}
