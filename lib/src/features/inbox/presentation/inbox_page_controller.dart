import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_controller.dart';

/// Tabs belonging to one mounted Inbox page.
enum InboxPageTab { newItems, postponed }

/// Volatile visual state of an Inbox page.
///
/// The session projection, including badge and realtime data, belongs to
/// [InboxSessionController]. This state deliberately contains only values that
/// should be released when the page closes.
final class InboxPageViewState {
  const InboxPageViewState({
    this.selectedTab = InboxPageTab.newItems,
    this.newItemsScrollOffset = 0,
    this.postponedScrollOffset = 0,
    this.focusedItemKey,
    this.actionStatus = const OperationStatus.idle(),
  });

  final InboxPageTab selectedTab;
  final double newItemsScrollOffset;
  final double postponedScrollOffset;
  final String? focusedItemKey;
  final OperationStatus actionStatus;

  InboxPageViewState copyWith({
    InboxPageTab? selectedTab,
    double? newItemsScrollOffset,
    double? postponedScrollOffset,
    String? focusedItemKey,
    OperationStatus? actionStatus,
  }) => InboxPageViewState(
    selectedTab: selectedTab ?? this.selectedTab,
    newItemsScrollOffset: newItemsScrollOffset ?? this.newItemsScrollOffset,
    postponedScrollOffset: postponedScrollOffset ?? this.postponedScrollOffset,
    focusedItemKey: focusedItemKey ?? this.focusedItemKey,
    actionStatus: actionStatus ?? this.actionStatus,
  );
}

/// Auto-disposed coordinator for tab, scroll, focus and action feedback of a
/// single Inbox page. It delegates projection mutations to the session owner.
final class InboxPageController extends Notifier<InboxPageViewState> {
  InboxPageController(this._sessionProvider);

  final AsyncNotifierProvider<InboxSessionController, InboxSessionViewState>
  _sessionProvider;
  var _isDisposed = false;

  @override
  InboxPageViewState build() {
    ref.onDispose(() => _isDisposed = true);
    return const InboxPageViewState();
  }

  void selectTab(InboxPageTab tab) {
    if (tab == state.selectedTab) return;
    state = state.copyWith(selectedTab: tab);
  }

  void saveScrollOffset(InboxPageTab tab, double offset) {
    if (!offset.isFinite || offset < 0) return;
    switch (tab) {
      case InboxPageTab.newItems:
        if (offset == state.newItemsScrollOffset) return;
        state = state.copyWith(newItemsScrollOffset: offset);
      case InboxPageTab.postponed:
        if (offset == state.postponedScrollOffset) return;
        state = state.copyWith(postponedScrollOffset: offset);
    }
  }

  void focusItem(String itemKey) {
    if (itemKey == state.focusedItemKey) return;
    state = state.copyWith(focusedItemKey: itemKey);
  }

  Future<bool> markRead(InboxItem item) =>
      _runAction(() => ref.read(_sessionProvider.notifier).markRead(item));

  Future<bool> postpone(InboxItem item) =>
      _runAction(() => ref.read(_sessionProvider.notifier).postpone(item));

  Future<bool> remove(InboxItem item) =>
      _runAction(() => ref.read(_sessionProvider.notifier).remove(item));

  Future<bool> _runAction(Future<bool> Function() action) async {
    if (state.actionStatus is OperationInProgress) return false;
    state = state.copyWith(actionStatus: const OperationStatus.inProgress());
    try {
      final bool succeeded = await action();
      if (_isDisposed) return succeeded;
      state = state.copyWith(
        actionStatus: succeeded
            ? const OperationStatus.idle()
            : OperationStatus.failed(StateError('Inbox action failed')),
      );
      return succeeded;
    } on Object catch (error) {
      if (!_isDisposed) {
        state = state.copyWith(actionStatus: OperationStatus.failed(error));
      }
      return false;
    }
  }
}
