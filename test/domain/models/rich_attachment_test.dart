import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';

void main() {
  group('rich attachment domain model', () {
    test('represents button, select, and unknown action variants', () {
      const RichAttachmentActionToken token = RichAttachmentActionToken(
        'opaque-cookie',
      );
      const List<RichAttachmentAction> actions = <RichAttachmentAction>[
        RichAttachmentButtonAction(
          id: 'approve',
          name: 'Approve',
          token: token,
          tooltip: 'Approve request',
          style: RichAttachmentButtonStyle.success,
        ),
        RichAttachmentSelectAction(
          id: 'reviewer',
          name: 'Reviewer',
          token: token,
          options: <RichAttachmentOption>[
            RichAttachmentOption(text: 'Ada', value: 'user-1'),
          ],
          defaultOption: 'user-1',
        ),
        RichAttachmentUnknownAction(
          id: 'future-action',
          name: 'Future action',
          type: 'date_picker',
          token: token,
        ),
      ];

      expect(actions[0], isA<RichAttachmentButtonAction>());
      expect(actions[1], isA<RichAttachmentSelectAction>());
      expect(actions[2], isA<RichAttachmentUnknownAction>());
      expect(
        actions.every((RichAttachmentAction action) => action.token == token),
        isTrue,
      );
    });

    test('distinguishes static and system-backed selects', () {
      const RichAttachmentSelectAction staticSelect =
          RichAttachmentSelectAction(
            id: 'priority',
            name: 'Priority',
            options: <RichAttachmentOption>[
              RichAttachmentOption(text: 'High', value: 'high'),
            ],
          );
      const RichAttachmentSelectAction channelSelect =
          RichAttachmentSelectAction(
            id: 'channel',
            name: 'Channel',
            dataSource: RichAttachmentSelectDataSource.channels,
          );

      expect(staticSelect.dataSource, isNull);
      expect(staticSelect.options.single.value, 'high');
      expect(channelSelect.dataSource, RichAttachmentSelectDataSource.channels);
      expect(channelSelect.options, isEmpty);
    });

    test('supports semantic and custom-color button styles', () {
      const RichAttachmentButtonAction semantic = RichAttachmentButtonAction(
        id: 'delete',
        name: 'Delete',
        style: RichAttachmentButtonStyle.danger,
      );
      const RichAttachmentButtonAction custom = RichAttachmentButtonAction(
        id: 'brand',
        name: 'Brand action',
        style: RichAttachmentButtonStyle.customColor,
        customColor: '#123ABC',
      );

      expect(semantic.style, RichAttachmentButtonStyle.danger);
      expect(custom.customColor, '#123ABC');
    });
  });

  group('Post rich attachments', () {
    const List<RichAttachment> richAttachments = <RichAttachment>[
      RichAttachment(
        title: 'Deployment',
        fields: <RichAttachmentField>[
          RichAttachmentField(title: 'Status', value: 'Ready', isShort: true),
        ],
      ),
    ];

    test('defaults to an empty const collection', () {
      final Post post = _post();

      expect(post.richAttachments, isEmpty);
    });

    test('withThreadSummary preserves rich attachments', () {
      final Post updated = _post(
        richAttachments: richAttachments,
      ).withThreadSummary(replyCount: 3, lastReplyAt: DateTime(2026, 1, 2));

      expect(updated.richAttachments, same(richAttachments));
      expect(updated.replyCount, 3);
    });

    test('withReactions preserves rich attachments', () {
      final Post updated = _post(richAttachments: richAttachments)
          .withReactions(const <PostReaction>[
            PostReaction(emoji: '👍', emojiName: 'thumbsup', count: 1),
          ]);

      expect(updated.richAttachments, same(richAttachments));
      expect(updated.reactions, hasLength(1));
    });
  });
}

Post _post({List<RichAttachment> richAttachments = const <RichAttachment>[]}) =>
    Post(
      id: 'post-1',
      channelId: 'channel-1',
      author: const PostAuthor(id: 'user-1', displayName: 'Ada'),
      sentAt: DateTime(2026, 1, 1),
      message: 'Message',
      richAttachments: richAttachments,
    );
