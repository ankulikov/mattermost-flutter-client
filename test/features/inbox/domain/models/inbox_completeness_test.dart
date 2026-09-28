import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_completeness.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_source_result.dart';

void main() {
  group('InboxCompleteness', () {
    test('preserves the most limited state across source results', () {
      expect(
        InboxCompleteness.mostLimited(<InboxCompleteness>[
          InboxCompleteness.exact,
          InboxCompleteness.approximateMentions,
        ]),
        InboxCompleteness.approximateMentions,
      );
      expect(
        InboxCompleteness.mostLimited(<InboxCompleteness>[
          InboxCompleteness.approximateMentions,
          InboxCompleteness.truncated,
        ]),
        InboxCompleteness.truncated,
      );
    });
  });

  group('InboxSourceResult', () {
    test('retains only typed, immutable diagnostic codes', () {
      final InboxSourceResult result = InboxSourceResult(
        candidates: InboxSourceSnapshot(),
        completeness: InboxCompleteness.approximateMentions,
        diagnosticsCodes: <InboxSourceDiagnosticCode>[
          InboxSourceDiagnosticCode.mentionReconstructionMismatch,
          InboxSourceDiagnosticCode.mentionReconstructionMismatch,
        ],
      );

      expect(result.completeness, InboxCompleteness.approximateMentions);
      expect(result.diagnosticsCodes, <InboxSourceDiagnosticCode>{
        InboxSourceDiagnosticCode.mentionReconstructionMismatch,
      });
      expect(
        () => result.diagnosticsCodes.add(
          InboxSourceDiagnosticCode.sourceRequestFailed,
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('InboxSnapshot', () {
    test('keeps approximate mentions and truncation distinct', () {
      final InboxSnapshot approximate = InboxSnapshot(
        completeness: InboxCompleteness.approximateMentions,
        diagnosticsCodes: <InboxSourceDiagnosticCode>[
          InboxSourceDiagnosticCode.mentionReconstructionMismatch,
        ],
      );
      final InboxSnapshot truncated = InboxSnapshot(
        completeness: InboxCompleteness.truncated,
        diagnosticsCodes: <InboxSourceDiagnosticCode>[
          InboxSourceDiagnosticCode.unreadRangeSafetyCapReached,
        ],
      );

      expect(approximate.completeness, InboxCompleteness.approximateMentions);
      expect(truncated.completeness, InboxCompleteness.truncated);
      expect(approximate.diagnosticsCodes, <InboxSourceDiagnosticCode>[
        InboxSourceDiagnosticCode.mentionReconstructionMismatch,
      ]);
      expect(truncated.diagnosticsCodes, <InboxSourceDiagnosticCode>[
        InboxSourceDiagnosticCode.unreadRangeSafetyCapReached,
      ]);
    });

    test('maps the legacy mention flag without overriding truncation', () {
      final InboxSnapshot approximate = InboxSnapshot(
        hasIncompleteMentionReconstruction: true,
      );
      final InboxSnapshot truncated = InboxSnapshot(
        completeness: InboxCompleteness.truncated,
        hasIncompleteMentionReconstruction: true,
      );

      expect(approximate.completeness, InboxCompleteness.approximateMentions);
      expect(truncated.completeness, InboxCompleteness.truncated);
    });
  });
}
