import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/features/channel_members/domain/channel_member.dart';
import 'package:mattermost_flutter/src/features/channel_members/domain/channel_members_repository.dart';

final class ChannelMembersViewState {
  const ChannelMembersViewState({
    this.members = const <ChannelMember>[],
    this.page = 0,
    this.hasMore = false,
    this.paginationStatus = const OperationStatus.idle(),
  });

  final List<ChannelMember> members;
  final int page;
  final bool hasMore;
  final OperationStatus paginationStatus;

  ChannelMembersViewState copyWith({
    List<ChannelMember>? members,
    int? page,
    bool? hasMore,
    OperationStatus? paginationStatus,
  }) => ChannelMembersViewState(
    members: members ?? this.members,
    page: page ?? this.page,
    hasMore: hasMore ?? this.hasMore,
    paginationStatus: paginationStatus ?? this.paginationStatus,
  );
}

final class ChannelMembersController
    extends AsyncNotifier<ChannelMembersViewState> {
  ChannelMembersController(this.channelId, this._repositoryProvider);

  static const int pageSize = 60;

  final String channelId;
  final Provider<ChannelMembersRepository> _repositoryProvider;
  late RequestCancellation _cancellation;
  ChannelMembersRepository? _repository;

  @override
  Future<ChannelMembersViewState> build() async {
    final RequestCancellation cancellation = RequestCancellation();
    _cancellation = cancellation;
    ref.onDispose(cancellation.cancel);
    final ChannelMembersRepository repository = ref.watch(_repositoryProvider);
    _repository = repository;
    return _loadFirstPage(repository);
  }

  Future<void> retry() async {
    final ChannelMembersRepository? repository = _repository;
    if (repository == null) return;
    state = const AsyncLoading<ChannelMembersViewState>();
    state = await AsyncValue.guard(() => _loadFirstPage(repository));
  }

  Future<void> loadMore() async {
    final ChannelMembersViewState? current = state.value;
    final ChannelMembersRepository? repository = _repository;
    if (current == null ||
        repository == null ||
        !current.hasMore ||
        current.paginationStatus is OperationInProgress) {
      return;
    }
    state = AsyncData<ChannelMembersViewState>(
      current.copyWith(paginationStatus: const OperationStatus.inProgress()),
    );
    try {
      final int nextPage = current.page + 1;
      final ChannelMembersPage page = await _cancellation.run(
        () => repository.loadPage(
          channelId: channelId,
          page: nextPage,
          perPage: pageSize,
        ),
      );
      final Map<String, ChannelMember> merged = <String, ChannelMember>{
        for (final ChannelMember member in current.members)
          member.user.id: member,
        for (final ChannelMember member in page.members) member.user.id: member,
      };
      state = AsyncData<ChannelMembersViewState>(
        ChannelMembersViewState(
          members: List<ChannelMember>.unmodifiable(merged.values),
          page: nextPage,
          hasMore: page.hasMore,
        ),
      );
    } on Object catch (error) {
      if (_cancellation.isCancelled) return;
      state = AsyncData<ChannelMembersViewState>(
        current.copyWith(paginationStatus: OperationStatus.failed(error)),
      );
    }
  }

  Future<ChannelMembersViewState> _loadFirstPage(
    ChannelMembersRepository repository,
  ) async {
    final ChannelMembersPage page = await _cancellation.run(
      () =>
          repository.loadPage(channelId: channelId, page: 0, perPage: pageSize),
    );
    return ChannelMembersViewState(
      members: page.members,
      hasMore: page.hasMore,
    );
  }
}
