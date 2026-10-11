import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/data/providers/repository_providers.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/channel_members/domain/channel_member.dart';
import 'package:mattermost_flutter/src/features/channel_members/domain/channel_members_repository.dart';
import 'package:mattermost_flutter/src/features/channel_members/presentation/channel_members_controller.dart';
import 'package:mattermost_flutter/src/features/channel_members/presentation/channel_members_providers.dart';

void main() {
  test('appends the next page and marks the list complete', () async {
    final _PagedRepository repository = _PagedRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        channelMembersRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final provider = channelMembersProvider('channel-1');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    final ChannelMembersViewState initial = await container.read(
      provider.future,
    );
    expect(initial.members, hasLength(ChannelMembersController.pageSize));
    expect(initial.hasMore, isTrue);

    await container.read(provider.notifier).loadMore();

    final ChannelMembersViewState completed = container.read(provider).value!;
    expect(completed.members, hasLength(61));
    expect(completed.members.last.user.id, 'last');
    expect(completed.page, 1);
    expect(completed.hasMore, isFalse);
  });

  test('preserves loaded members when pagination fails', () async {
    final _PagedRepository repository = _PagedRepository(failSecondPage: true);
    final ProviderContainer container = ProviderContainer(
      overrides: [
        channelMembersRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final provider = channelMembersProvider('channel-1');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);

    await container.read(provider.notifier).loadMore();

    final ChannelMembersViewState failed = container.read(provider).value!;
    expect(failed.members, hasLength(ChannelMembersController.pageSize));
    expect(failed.paginationStatus, isA<OperationFailed>());
    expect(failed.hasMore, isTrue);
  });
}

final class _PagedRepository implements ChannelMembersRepository {
  _PagedRepository({this.failSecondPage = false});

  final bool failSecondPage;

  @override
  Future<int> getCount(String channelId) async => 61;

  @override
  Future<ChannelMembersPage> loadPage({
    required String channelId,
    required int page,
    required int perPage,
  }) async {
    if (page == 1 && failSecondPage) throw StateError('offline');
    if (page == 1) {
      return ChannelMembersPage(members: <ChannelMember>[_member('last')]);
    }
    return ChannelMembersPage(
      members: List<ChannelMember>.generate(
        perPage,
        (int index) => _member('user-$index'),
        growable: false,
      ),
      hasMore: true,
    );
  }
}

ChannelMember _member(String id) => ChannelMember(
  user: UserSummary(
    id: id,
    firstName: id,
    lastName: '',
    username: id,
    nickname: '',
    position: '',
    email: '',
  ),
);
