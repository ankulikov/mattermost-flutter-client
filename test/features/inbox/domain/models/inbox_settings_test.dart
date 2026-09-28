import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_settings.dart';

void main() {
  group('InboxSettings defaults', () {
    test('are enabled and can only narrow the local projection', () {
      const InboxSettings settings = InboxSettings.defaults;

      expect(settings.enabled, isTrue);
      expect(settings.sources.directMessages, isTrue);
      expect(settings.sources.groupMessages, isTrue);
      expect(settings.sources.mentions, isTrue);
      expect(settings.sources.followedThreads, isTrue);
      expect(settings.sources.allActivity, isTrue);
      expect(settings.sources.automations, InboxAutomationVisibility.separate);
      expect(settings.postponed.reactivateOnMention, isTrue);
      expect(settings.postponed.removeOnOpen, isFalse);
      expect(settings.directGrouping.mode, InboxDirectGroupingMode.consecutive);
      expect(settings.inAppNotification.showMessagePreview, isFalse);
    });

    test('bounds the persisted direct grouping window', () {
      expect(InboxDirectGroupingSettings.minWindowSeconds, 1);
      expect(InboxDirectGroupingSettings.defaultWindowSeconds, 120);
      expect(InboxDirectGroupingSettings.maxWindowSeconds, 3600);
    });
  });
}
