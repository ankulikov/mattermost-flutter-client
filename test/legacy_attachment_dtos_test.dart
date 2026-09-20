import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';

void main() {
  test('projects legacy attachment fields and typed actions', () {
    final MattermostPostPropsDto props = MattermostPostPropsDto.fromJson(
      <String, Object?>{
        'attachments': <Object?>[
          <String, Object?>{
            'fallback': 'Fallback',
            'color': '#112233',
            'pretext': 'Before',
            'author_name': 'Release bot',
            'author_link': 'https://example.com/author',
            'author_icon': 'https://example.com/author.png',
            'title': 'Deploy?',
            'title_link': 'https://example.com/deploy',
            'text': 'Choose a target',
            'fields': <Object?>[
              <String, Object?>{
                'title': 'Environment',
                'value': 'Production',
                'short': true,
              },
            ],
            'image_url': 'https://example.com/image.png',
            'thumb_url': 'https://example.com/thumb.png',
            'footer': 'Automation',
            'footer_icon': 'https://example.com/footer.png',
            'ts': 1234,
            'actions': <Object?>[
              <String, Object?>{
                'id': 'approve',
                'name': 'Approve',
                'type': 'button',
                'tooltip': 'Approve deployment',
                'style': 'success',
                'cookie': 'opaque-button-token',
              },
              <String, Object?>{
                'id': 'target',
                'name': 'Target',
                'type': 'select',
                'data_source': 'channels',
                'default_option': 'town-square',
                'cookie': 'opaque-select-token',
                'options': <Object?>[
                  <String, Object?>{
                    'text': 'Town Square',
                    'value': 'town-square',
                  },
                ],
              },
            ],
          },
        ],
      },
    );

    final MattermostLegacyAttachmentDto attachment =
        props.legacyAttachments.single;
    expect(attachment.fallback, 'Fallback');
    expect(attachment.color, '#112233');
    expect(attachment.pretext, 'Before');
    expect(attachment.authorName, 'Release bot');
    expect(attachment.authorLink, 'https://example.com/author');
    expect(attachment.authorIcon, 'https://example.com/author.png');
    expect(attachment.title, 'Deploy?');
    expect(attachment.titleLink, 'https://example.com/deploy');
    expect(attachment.text, 'Choose a target');
    expect(attachment.fields.single.title, 'Environment');
    expect(attachment.fields.single.value, 'Production');
    expect(attachment.fields.single.isShort, isTrue);
    expect(attachment.imageUrl, 'https://example.com/image.png');
    expect(attachment.thumbUrl, 'https://example.com/thumb.png');
    expect(attachment.footer, 'Automation');
    expect(attachment.footerIcon, 'https://example.com/footer.png');
    expect((attachment.timestamp! as JsonNumberDto).value, 1234);

    final MattermostLegacyButtonActionDto button =
        attachment.actions.first as MattermostLegacyButtonActionDto;
    expect(button.id, 'approve');
    expect(button.name, 'Approve');
    expect(button.tooltip, 'Approve deployment');
    expect(button.style, 'success');
    expect(button.cookie, 'opaque-button-token');

    final MattermostLegacySelectActionDto select =
        attachment.actions.last as MattermostLegacySelectActionDto;
    expect(select.dataSource, 'channels');
    expect(select.defaultOption, 'town-square');
    expect(select.cookie, 'opaque-select-token');
    expect(select.options.single.text, 'Town Square');
    expect(select.options.single.value, 'town-square');
  });

  test(
    'preserves unknown action raw props without exposing integration data',
    () {
      final MattermostPostPropsDto props = MattermostPostPropsDto.fromJson(
        <String, Object?>{
          'attachments': <Object?>[
            <String, Object?>{
              'actions': <Object?>[
                <String, Object?>{
                  'id': 'custom',
                  'name': 'Custom',
                  'type': 'date_picker',
                  'custom_key': <String, Object?>{'nested': true},
                  'cookie': 'opaque-token',
                  'integration': <String, Object?>{
                    'url': 'https://secret.example.com',
                    'context': <String, Object?>{'secret': 'value'},
                  },
                  'context': <String, Object?>{'also': 'private'},
                },
              ],
            },
          ],
        },
      );

      final MattermostLegacyUnknownActionDto action =
          props.legacyAttachments.single.actions.single
              as MattermostLegacyUnknownActionDto;
      expect(action.type, 'date_picker');
      expect(action.cookie, 'opaque-token');
      expect(action.rawProps['custom_key'], isA<JsonObjectDto>());
      expect(action.rawProps, isNot(contains('integration')));
      expect(action.rawProps, isNot(contains('context')));

      final JsonObjectDto originalAttachment =
          (props.values['attachments']! as JsonArrayDto).values.single
              as JsonObjectDto;
      final JsonObjectDto originalAction =
          (originalAttachment.values['actions']! as JsonArrayDto).values.single
              as JsonObjectDto;
      expect(originalAction.values, contains('integration'));
      expect(originalAction.values, contains('context'));
    },
  );

  test('skips only malformed children at every legacy attachment level', () {
    final MattermostPostPropsDto props = MattermostPostPropsDto.fromJson(
      <String, Object?>{
        'attachments': <Object?>[
          'not-an-object',
          <String, Object?>{'title': 42},
          <String, Object?>{
            'title': 'Still valid',
            'fields': <Object?>[
              <String, Object?>{'title': 42},
              <String, Object?>{'title': 'Valid field', 'value': 'value'},
            ],
            'actions': <Object?>[
              <String, Object?>{'id': 42, 'type': 'button'},
              <String, Object?>{
                'id': 'select',
                'name': 'Select',
                'type': 'select',
                'options': <Object?>[
                  <String, Object?>{'text': false, 'value': 'invalid'},
                  <String, Object?>{'text': 'Valid', 'value': 'valid'},
                ],
              },
            ],
          },
        ],
      },
    );

    expect(props.legacyAttachments, hasLength(1));
    final MattermostLegacyAttachmentDto attachment =
        props.legacyAttachments.single;
    expect(attachment.title, 'Still valid');
    expect(attachment.fields.single.title, 'Valid field');
    expect(attachment.actions, hasLength(1));
    final MattermostLegacySelectActionDto action =
        attachment.actions.single as MattermostLegacySelectActionDto;
    expect(action.options.single.text, 'Valid');
  });

  test('returns no typed attachments when attachments is not an array', () {
    final MattermostPostPropsDto props = MattermostPostPropsDto.fromJson(
      <String, Object?>{
        'attachments': <String, Object?>{'title': 'invalid'},
      },
    );

    expect(props.legacyAttachments, isEmpty);
    expect(props.values['attachments'], isA<JsonObjectDto>());
  });
}
