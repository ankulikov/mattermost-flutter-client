import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/data/repositories/mattermost_inbox_settings_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_settings.dart';

void main() {
  final AuthSession session = AuthSession(
    serverUrl: Uri.parse('https://chat.example'),
    userId: 'me',
    username: 'me',
  );

  group('MattermostInboxSettingsRepository', () {
    test('uses defaults when the settings preference is absent', () async {
      final _PreferencesApi api = _PreferencesApi();

      final InboxSettingsSnapshot snapshot =
          await MattermostInboxSettingsRepository(
            api: api,
          ).load(session: session);

      expect(snapshot.state, InboxSettingsLoadState.defaults);
      expect(snapshot.settings.enabled, isTrue);
      expect(api.requestedCategories, <String>[
        MattermostInboxSettingsRepository.category,
      ]);
    });

    test('parses a valid v1 document with bounded known values', () async {
      final _PreferencesApi api = _PreferencesApi(
        preferences: <MattermostPreferenceDto>[
          _settingsPreference(<String, Object?>{
            'v': 1,
            'enabled': false,
            'sources': <String, Object?>{
              'direct_messages': false,
              'group_messages': false,
              'mentions': true,
              'followed_threads': false,
              'all_activity': false,
              'automations': 'exclude',
            },
            'postponed': <String, Object?>{
              'reactivate_on_mention': false,
              'remove_on_open': true,
            },
            'direct_grouping': <String, Object?>{
              'mode': 'consecutive',
              'window_seconds': 240,
            },
            'in_app_notification': <String, Object?>{
              'show_message_preview': true,
            },
          }),
        ],
      );

      final InboxSettingsSnapshot snapshot =
          await MattermostInboxSettingsRepository(
            api: api,
          ).load(session: session);

      expect(snapshot.state, InboxSettingsLoadState.parsed);
      expect(snapshot.settings.enabled, isFalse);
      expect(snapshot.settings.sources.directMessages, isFalse);
      expect(snapshot.settings.sources.groupMessages, isFalse);
      expect(
        snapshot.settings.sources.automations,
        InboxAutomationVisibility.exclude,
      );
      expect(snapshot.settings.postponed.reactivateOnMention, isFalse);
      expect(snapshot.settings.postponed.removeOnOpen, isTrue);
      expect(
        snapshot.settings.directGrouping.mode,
        InboxDirectGroupingMode.consecutive,
      );
      expect(snapshot.settings.directGrouping.windowSeconds, 240);
      expect(snapshot.settings.inAppNotification.showMessagePreview, isTrue);
    });

    test(
      'returns safe defaults for unsupported and malformed documents',
      () async {
        final _PreferencesApi unknownVersion = _PreferencesApi(
          preferences: <MattermostPreferenceDto>[
            _settingsPreference(<String, Object?>{'v': 2, 'enabled': false}),
          ],
        );
        final _PreferencesApi malformed = _PreferencesApi(
          preferences: <MattermostPreferenceDto>[
            const MattermostPreferenceDto(
              userId: 'me',
              category: MattermostInboxSettingsRepository.category,
              name: MattermostInboxSettingsRepository.name,
              value: '{not-json',
            ),
          ],
        );

        final InboxSettingsSnapshot unknown =
            await MattermostInboxSettingsRepository(
              api: unknownVersion,
            ).load(session: session);
        final InboxSettingsSnapshot invalid =
            await MattermostInboxSettingsRepository(
              api: malformed,
            ).load(session: session);

        expect(unknown.state, InboxSettingsLoadState.unsupportedVersion);
        expect(unknown.settings.enabled, isTrue);
        expect(invalid.state, InboxSettingsLoadState.malformed);
        expect(invalid.settings.sources.mentions, isTrue);
      },
    );

    test(
      'rejects an oversized server settings document before decoding',
      () async {
        final _PreferencesApi api = _PreferencesApi(
          preferences: <MattermostPreferenceDto>[
            MattermostPreferenceDto(
              userId: 'me',
              category: MattermostInboxSettingsRepository.category,
              name: MattermostInboxSettingsRepository.name,
              value: 'x' * (64 * 1024 + 1),
            ),
          ],
        );

        final InboxSettingsSnapshot snapshot =
            await MattermostInboxSettingsRepository(
              api: api,
            ).load(session: session);

        expect(snapshot.state, InboxSettingsLoadState.malformed);
        expect(snapshot.settings.enabled, isTrue);
        expect(snapshot.settings.sources.mentions, isTrue);
      },
    );

    test(
      'falls back per field and rejects unknown enum values safely',
      () async {
        final _PreferencesApi api = _PreferencesApi(
          preferences: <MattermostPreferenceDto>[
            _settingsPreference(<String, Object?>{
              'v': 1,
              'enabled': 'false',
              'sources': <String, Object?>{
                'mentions': 'later',
                'automations': 'future-mode',
              },
              'direct_grouping': <String, Object?>{
                'mode': 'unbounded',
                'window_seconds': 999999,
              },
            }),
          ],
        );

        final InboxSettingsSnapshot snapshot =
            await MattermostInboxSettingsRepository(
              api: api,
            ).load(session: session);

        expect(snapshot.state, InboxSettingsLoadState.malformed);
        expect(snapshot.settings.enabled, isTrue);
        expect(snapshot.settings.sources.mentions, isTrue);
        expect(
          snapshot.settings.sources.automations,
          InboxAutomationVisibility.separate,
        );
        expect(
          snapshot.settings.directGrouping.mode,
          InboxDirectGroupingMode.consecutive,
        );
        expect(
          snapshot.settings.directGrouping.windowSeconds,
          InboxDirectGroupingSettings.defaultWindowSeconds,
        );
      },
    );

    test(
      'preserves unknown v1 fields through a load and save round trip',
      () async {
        final _PreferencesApi api = _PreferencesApi(
          preferences: <MattermostPreferenceDto>[
            _settingsPreference(<String, Object?>{
              'v': 1,
              'enabled': false,
              'future_root': <String, Object?>{
                'nested': <Object?>[1, true],
              },
              'sources': <String, Object?>{
                'mentions': false,
                'future_source': 'retain-me',
              },
              'postponed': <String, Object?>{'future_postponed': 7},
              'direct_grouping': <String, Object?>{'future_grouping': false},
              'in_app_notification': <String, Object?>{
                'show_message_preview': true,
                'future_notification': 'keep-me',
              },
            }),
          ],
        );
        final MattermostInboxSettingsRepository repository =
            MattermostInboxSettingsRepository(api: api);

        final InboxSettingsSnapshot loaded = await repository.load(
          session: session,
        );
        await repository.save(session: session, settings: loaded.settings);

        final MattermostPreferenceDto saved = api.saved.single.single;
        final Map<String, Object?> document =
            jsonDecode(saved.value) as Map<String, Object?>;
        expect(document['future_root'], <String, Object?>{
          'nested': <Object?>[1, true],
        });
        expect(
          (document['sources'] as Map<String, Object?>)['future_source'],
          'retain-me',
        );
        expect(
          (document['postponed'] as Map<String, Object?>)['future_postponed'],
          7,
        );
        expect(
          (document['direct_grouping']
              as Map<String, Object?>)['future_grouping'],
          isFalse,
        );
        expect(
          (document['in_app_notification']
              as Map<String, Object?>)['future_notification'],
          'keep-me',
        );
        expect(
          (document['in_app_notification']
              as Map<String, Object?>)['show_message_preview'],
          isTrue,
        );
        expect(document['v'], InboxSettings.currentVersion);
        expect(document['enabled'], isFalse);
      },
    );

    test(
      'scopes reads and writes to the active session and one preference',
      () async {
        final _PreferencesApi api = _PreferencesApi(
          preferences: <MattermostPreferenceDto>[
            const MattermostPreferenceDto(
              userId: 'other-user',
              category: MattermostInboxSettingsRepository.category,
              name: MattermostInboxSettingsRepository.name,
              value: '{"v":1,"enabled":false}',
            ),
          ],
        );
        final MattermostInboxSettingsRepository repository =
            MattermostInboxSettingsRepository(api: api);

        final InboxSettingsSnapshot loaded = await repository.load(
          session: session,
        );
        await repository.save(
          session: session,
          settings: const InboxSettings(),
        );

        expect(loaded.state, InboxSettingsLoadState.defaults);
        expect(api.saved, hasLength(1));
        expect(api.saved.single, hasLength(1));
        final MattermostPreferenceDto saved = api.saved.single.single;
        expect(saved.userId, session.userId);
        expect(saved.category, MattermostInboxSettingsRepository.category);
        expect(saved.name, MattermostInboxSettingsRepository.name);
      },
    );

    test(
      'persists the selected direct grouping mode and bounded window',
      () async {
        final _PreferencesApi api = _PreferencesApi();
        final MattermostInboxSettingsRepository repository =
            MattermostInboxSettingsRepository(api: api);

        await repository.save(
          session: session,
          settings: const InboxSettings(
            directGrouping: InboxDirectGroupingSettings(
              mode: InboxDirectGroupingMode.conversation,
              windowSeconds: 300,
            ),
          ),
        );

        final Map<String, Object?> document =
            jsonDecode(api.saved.single.single.value) as Map<String, Object?>;
        expect(document['direct_grouping'], <String, Object?>{
          'mode': 'conversation',
          'window_seconds': 300,
        });
        expect(document['in_app_notification'], <String, Object?>{
          'show_message_preview': false,
        });
      },
    );

    test('does not report a save success when the API write fails', () async {
      final _PreferencesApi api = _PreferencesApi(
        saveError: StateError('failed'),
      );
      final MattermostInboxSettingsRepository repository =
          MattermostInboxSettingsRepository(api: api);

      await expectLater(
        repository.save(session: session, settings: const InboxSettings()),
        throwsStateError,
      );
      expect(api.saved, isEmpty);
    });

    test('treats the server missing-category response as defaults', () async {
      final _PreferencesApi api = _PreferencesApi(
        getError: DioException(
          requestOptions: RequestOptions(
            path:
                '/users/me/preferences/${MattermostInboxSettingsRepository.category}',
          ),
          response: Response<Object?>(
            requestOptions: RequestOptions(
              path:
                  '/users/me/preferences/${MattermostInboxSettingsRepository.category}',
            ),
            statusCode: 404,
            data: const <String, Object?>{
              'id': 'api.preference.preferences_category.get.app_error',
            },
          ),
        ),
      );

      final InboxSettingsSnapshot snapshot =
          await MattermostInboxSettingsRepository(
            api: api,
          ).load(session: session);

      expect(snapshot.state, InboxSettingsLoadState.defaults);
    });
  });
}

MattermostPreferenceDto _settingsPreference(Map<String, Object?> document) =>
    MattermostPreferenceDto(
      userId: 'me',
      category: MattermostInboxSettingsRepository.category,
      name: MattermostInboxSettingsRepository.name,
      value: jsonEncode(document),
    );

final class _PreferencesApi extends Fake implements MattermostApi {
  _PreferencesApi({
    this.preferences = const <MattermostPreferenceDto>[],
    this.getError,
    this.saveError,
  });

  final List<MattermostPreferenceDto> preferences;
  final Object? getError;
  final Object? saveError;
  final List<String> requestedCategories = <String>[];
  final List<List<MattermostPreferenceDto>> saved =
      <List<MattermostPreferenceDto>>[];

  @override
  Future<List<MattermostPreferenceDto>> getPreferencesByCategory({
    required String userId,
    required String category,
  }) async {
    requestedCategories.add(category);
    if (getError != null) throw getError!;
    return preferences;
  }

  @override
  Future<void> savePreferences({
    required String userId,
    required List<MattermostPreferenceDto> preferences,
  }) async {
    if (saveError != null) throw saveError!;
    saved.add(preferences);
  }
}
