import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/search/domain/repositories/message_search_timezone_repository.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

final class MattermostMessageSearchTimezoneRepository
    implements MessageSearchTimezoneRepository {
  MattermostMessageSearchTimezoneRepository({required MattermostApi api})
    : _api = api;

  final MattermostApi _api;

  @override
  Future<MessageSearchTimezone> load() async {
    tz_data.initializeTimeZones();
    final String id = _effectiveTimezoneId(await _api.getCurrentUser());
    try {
      final tz.Location location = tz.getLocation(id);
      return MessageSearchTimezone(
        timezoneId: id,
        offsetSeconds: (DateTime instant) =>
            tz.TZDateTime.from(instant, location).timeZoneOffset.inSeconds,
      );
    } on Object {
      return MessageSearchTimezone(
        timezoneId: null,
        offsetSeconds: (DateTime instant) =>
            instant.toLocal().timeZoneOffset.inSeconds,
      );
    }
  }

  String _effectiveTimezoneId(MattermostUserDto user) {
    final MattermostTimezoneDto? timezone = user.timezone;
    final String value = timezone?.useAutomaticTimezone == true
        ? timezone?.automaticTimezone ?? ''
        : timezone?.manualTimezone ?? '';
    return value.trim();
  }
}
