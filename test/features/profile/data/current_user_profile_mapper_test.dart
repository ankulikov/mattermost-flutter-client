import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/profile/data/mappers/current_user_profile_mapper.dart';
import 'package:mattermost_flutter/src/features/profile/domain/models/current_user_profile.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 9, 10, 12);

  test('maps current availability, expiry, and custom status', () {
    final profile = mapCurrentUserProfile(
      user: MattermostUserDto.fromJson(<String, Object?>{
        'id': 'me',
        'username': 'ada',
        'first_name': 'Ada',
        'last_name': 'Lovelace',
        'props': <String, Object?>{
          'customStatus':
              '{"emoji":"calendar","text":"In a meeting",'
              '"duration":"one_hour",'
              '"expires_at":"2026-09-10T13:00:00.000Z"}',
        },
      }),
      status: const MattermostUserStatusDto(
        userId: 'me',
        status: 'dnd',
        dndEndTime: 1789047000,
      ),
      now: now,
    );

    expect(profile.user.fullName, 'Ada Lovelace');
    expect(profile.availability.presence, UserPresence.doNotDisturb);
    expect(
      profile.availability.expiresAt,
      DateTime.fromMillisecondsSinceEpoch(1789047000000, isUtc: true),
    );
    expect(profile.customStatus?.emoji, 'calendar');
    expect(profile.customStatus?.text, 'In a meeting');
    expect(profile.customStatus?.expiresAt, DateTime.utc(2026, 9, 10, 13));
  });

  test('ignores expired and malformed custom status props', () {
    UserPropsDto props(String value) =>
        UserPropsDto.fromJson(<String, Object?>{'customStatus': value});

    expect(
      mapCurrentCustomStatus(
        props(
          '{"emoji":"bus","text":"Commuting",'
          '"expires_at":"2026-09-10T11:59:00.000Z"}',
        ),
        now,
      ),
      isNull,
    );
    expect(mapCurrentCustomStatus(props('{broken'), now), isNull);
  });

  test('keeps a custom status with the server zero expiration', () {
    final CustomStatus? status = mapCurrentCustomStatus(
      UserPropsDto.fromJson(<String, Object?>{
        'customStatus':
            '{"emoji":"speech_balloon","text":"Heads down",'
            '"expires_at":"0001-01-01T00:00:00Z"}',
      }),
      now,
    );

    expect(status?.text, 'Heads down');
    expect(status?.expiresAt, isNull);
  });
}
