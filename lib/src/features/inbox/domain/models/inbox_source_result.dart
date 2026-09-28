import 'dart:collection';

import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_completeness.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';

/// The result of one Inbox snapshot source.
///
/// The contract intentionally exposes source candidates and closed diagnostic
/// codes only. It must not be used to retain post text, usernames, credentials,
/// or transport payloads for diagnostics.
final class InboxSourceResult {
  InboxSourceResult({
    required this.candidates,
    this.completeness = InboxCompleteness.exact,
    Iterable<InboxItem> postponedItems = const <InboxItem>[],
    Iterable<InboxSourceDiagnosticCode> diagnosticsCodes =
        const <InboxSourceDiagnosticCode>[],
    Iterable<InboxSourceFailure> sourceFailures = const <InboxSourceFailure>[],
  }) : postponedItems = UnmodifiableListView<InboxItem>(
         postponedItems.toList(),
       ),
       diagnosticsCodes = UnmodifiableSetView<InboxSourceDiagnosticCode>(
         Set<InboxSourceDiagnosticCode>.of(diagnosticsCodes),
       ),
       sourceFailures = UnmodifiableSetView<InboxSourceFailure>(
         Set<InboxSourceFailure>.of(sourceFailures),
       );

  final InboxSourceSnapshot candidates;
  final InboxCompleteness completeness;

  /// Items owned by a durable source rather than the volatile New queue.
  ///
  /// Postponed references need source-specific hydration and timestamps, so
  /// they bypass candidate canonicalization and are reconciled by the shared
  /// projection assembler with all other source output.
  final List<InboxItem> postponedItems;
  final Set<InboxSourceDiagnosticCode> diagnosticsCodes;
  final Set<InboxSourceFailure> sourceFailures;
}
