import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_draft_dto.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/drafts/data/mattermost_draft_repository.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft.dart';

void main() {
  test('parses typed draft fields and preserves flexible server values', () {
    final dto = MattermostDraftDto.fromJson(<String, Object?>{
      'channel_id': 'channel',
      'user_id': 'user',
      'root_id': 'root',
      'message': '**hello**',
      'create_at': 123,
      'update_at': 456,
      'file_ids': <Object?>['file'],
      'metadata': <String, Object?>{
        'files': <Object?>[
          <String, Object?>{'id': 'file', 'name': 'a.txt'},
        ],
      },
      'props': <String, Object?>{
        'nested': <String, Object?>{'flag': true},
      },
      'priority': <String, Object?>{'priority': 'urgent'},
    });
    expect(dto.channelId, 'channel');
    expect(dto.userId, 'user');
    expect(dto.rootId, 'root');
    expect(dto.message, '**hello**');
    expect(dto.createAt, 123);
    expect(dto.updateAt, 456);
    expect(dto.fileInfos.single.name, 'a.txt');
    expect(dto.toJson(), <String, Object?>{
      'channel_id': 'channel',
      'message': '**hello**',
      'root_id': 'root',
      'file_ids': <String>['file'],
      'props': <String, Object?>{
        'nested': <String, Object?>{'flag': true},
      },
      'priority': <String, Object?>{'priority': 'urgent'},
    });
  });

  test('defaults absent and null optional draft fields', () {
    final dto = MattermostDraftDto.fromJson(<String, Object?>{
      'channel_id': 'channel',
      'message': null,
      'file_ids': null,
      'file_infos': null,
      'create_at': null,
      'update_at': null,
    });
    expect(dto.message, '');
    expect(dto.fileIds, isEmpty);
    expect(dto.fileInfos, isEmpty);
    expect(dto.toJson(), <String, Object?>{
      'channel_id': 'channel',
      'message': '',
    });
  });
  test(
    'preserves server options and attachment metadata on draft save',
    () async {
      final _Api api = _Api();
      final MattermostDraftRepository repository = MattermostDraftRepository(
        api,
      );
      final Draft draft = (await repository.listTeamDrafts('team')).single;
      expect(draft.fileInfos.single.name, 'file.txt');
      expect(draft.fileInfos.single.size, 123);
      expect(draft.fileInfos.single.mimeType, 'text/plain');
      expect(draft.fileInfos.single.channelId, 'channel');
      expect(draft.fileInfos.single.width, 42);
      expect(draft.fileInfos.single.miniPreview, 'preview');
      expect(draft.fileIds, <String>['file']);
      expect(draft.priority, <String, Object?>{'priority': 'urgent'});
      await repository.saveDraft(draft);
      expect(api.saved?.toJson(), <String, Object?>{
        'channel_id': 'channel',
        'root_id': 'root',
        'message': 'hello',
        'file_ids': <String>['file'],
        'type': 'custom',
        'props': <String, Object?>{'custom': true},
        'priority': <String, Object?>{'priority': 'urgent'},
      });
    },
  );
}

final class _Api extends Fake implements MattermostApi {
  MattermostDraftDto? saved;

  @override
  Future<List<MattermostDraftDto>> listTeamDrafts(String teamId) async =>
      <MattermostDraftDto>[
        MattermostDraftDto.fromJson(<String, Object?>{
          'channel_id': 'channel',
          'root_id': 'root',
          'message': 'hello',
          'file_ids': <String>['file'],
          'metadata': <String, Object?>{
            'files': <Object?>[
              <String, Object?>{
                'id': 'file',
                'name': 'file.txt',
                'size': 123,
                'mime_type': 'text/plain',
                'channel_id': 'channel',
                'width': 42,
                'mini_preview': 'preview',
              },
            ],
          },
          'type': 'custom',
          'props': <String, Object?>{'custom': true},
          'priority': <String, Object?>{'priority': 'urgent'},
        }),
      ];

  @override
  Future<MattermostDraftDto?> saveDraft(MattermostDraftDto draft) async {
    saved = draft;
    return draft;
  }
}
