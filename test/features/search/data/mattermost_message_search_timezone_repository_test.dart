import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/search/data/repositories/mattermost_message_search_timezone_repository.dart';
import 'package:mattermost_flutter/src/features/search/domain/repositories/message_search_timezone_repository.dart';

void main() {
  test('uses a positive effective IANA timezone offset', () async {
    final MessageSearchTimezone timezone =
        await MattermostMessageSearchTimezoneRepository(
          api: _TimezoneApi(
            const MattermostTimezoneDto(manualTimezone: 'Asia/Tokyo'),
          ),
        ).load();

    expect(timezone.timezoneId, 'Asia/Tokyo');
    expect(timezone.offsetSeconds(DateTime.utc(2026, 1, 1)), 9 * 60 * 60);
  });

  test('uses a negative IANA timezone offset and follows DST', () async {
    final MessageSearchTimezone timezone =
        await MattermostMessageSearchTimezoneRepository(
          api: _TimezoneApi(
            const MattermostTimezoneDto(
              useAutomaticTimezone: true,
              automaticTimezone: 'America/New_York',
            ),
          ),
        ).load();

    expect(timezone.offsetSeconds(DateTime.utc(2026, 1, 1)), -5 * 60 * 60);
    expect(timezone.offsetSeconds(DateTime.utc(2026, 7, 1)), -4 * 60 * 60);
  });

  test(
    'falls back to the device offset for a missing or invalid timezone',
    () async {
      final MessageSearchTimezone timezone =
          await MattermostMessageSearchTimezoneRepository(
            api: _TimezoneApi(
              const MattermostTimezoneDto(manualTimezone: 'bad'),
            ),
          ).load();
      final DateTime instant = DateTime.utc(2026, 3, 29, 1);

      expect(timezone.timezoneId, isNull);
      expect(
        timezone.offsetSeconds(instant),
        instant.toLocal().timeZoneOffset.inSeconds,
      );
    },
  );
}

final class _TimezoneApi extends Fake implements MattermostApi {
  _TimezoneApi(this.timezone);

  final MattermostTimezoneDto timezone;

  @override
  Future<MattermostUserDto> getCurrentUser() async =>
      MattermostUserDto(id: 'me', username: 'me', timezone: timezone);
}
