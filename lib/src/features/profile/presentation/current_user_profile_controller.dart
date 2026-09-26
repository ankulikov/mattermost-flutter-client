import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/profile/domain/models/current_user_profile.dart';
import 'package:mattermost_flutter/src/features/profile/domain/policies/profile_status_expiration.dart';
import 'package:mattermost_flutter/src/features/profile/domain/repositories/current_user_profile_repository.dart';

final class CurrentUserProfileViewState {
  const CurrentUserProfileViewState({
    required this.profile,
    this.updateStatus = const OperationStatus.idle(),
  });

  final CurrentUserProfile profile;
  final OperationStatus updateStatus;

  CurrentUserProfileViewState copyWith({
    CurrentUserProfile? profile,
    OperationStatus? updateStatus,
  }) => CurrentUserProfileViewState(
    profile: profile ?? this.profile,
    updateStatus: updateStatus ?? this.updateStatus,
  );
}

final class CurrentUserProfileController
    extends AsyncNotifier<CurrentUserProfileViewState> {
  CurrentUserProfileController(
    this._sessionProvider,
    this._repositoryProvider, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Provider<AuthSession?> _sessionProvider;
  final Provider<CurrentUserProfileRepository> _repositoryProvider;
  final DateTime Function() _now;
  int _actionId = 0;

  @override
  Future<CurrentUserProfileViewState> build() async {
    final AuthSession? session = ref.watch(_sessionProvider);
    if (session == null) throw StateError('No active profile session');
    final CurrentUserProfile profile = await ref
        .watch(_repositoryProvider)
        .load();
    return CurrentUserProfileViewState(profile: profile);
  }

  Future<void> refresh() async {
    final CurrentUserProfileViewState? current = state.value;
    if (current == null || current.updateStatus is OperationInProgress) return;
    final int actionId = ++_actionId;
    state = AsyncData(
      current.copyWith(updateStatus: const OperationStatus.inProgress()),
    );
    try {
      final CurrentUserProfile profile = await ref
          .read(_repositoryProvider)
          .load();
      if (actionId != _actionId) return;
      state = AsyncData(CurrentUserProfileViewState(profile: profile));
    } on Object catch (error) {
      if (actionId != _actionId) return;
      state = AsyncData(
        current.copyWith(updateStatus: OperationStatus.failed(error)),
      );
    }
  }

  Future<void> setAvailability(
    UserPresence presence, {
    AvailabilityExpiry? expiry,
  }) async {
    final CurrentUserProfileViewState? current = state.value;
    if (current == null || current.updateStatus is OperationInProgress) return;
    final int actionId = ++_actionId;
    state = AsyncData(
      current.copyWith(updateStatus: const OperationStatus.inProgress()),
    );
    try {
      final DateTime? expiresAt = presence == UserPresence.online
          ? null
          : availabilityExpiration(
              expiry ?? AvailabilityExpiry.unlimited,
              _now(),
            );
      final Availability availability = await ref
          .read(_repositoryProvider)
          .setAvailability(presence: presence, expiresAt: expiresAt);
      if (actionId != _actionId) return;
      state = AsyncData(
        CurrentUserProfileViewState(
          profile: current.profile.copyWith(availability: availability),
        ),
      );
    } on Object catch (error) {
      if (actionId != _actionId) return;
      state = AsyncData(
        current.copyWith(updateStatus: OperationStatus.failed(error)),
      );
    }
  }

  Future<void> setQuickCustomStatus(QuickCustomStatus status) async {
    final CurrentUserProfileViewState? current = state.value;
    if (current == null || current.updateStatus is OperationInProgress) return;
    final int actionId = ++_actionId;
    state = AsyncData(
      current.copyWith(updateStatus: const OperationStatus.inProgress()),
    );
    final DateTime expiresAt = customStatusExpiration(status.duration, _now());
    try {
      await ref
          .read(_repositoryProvider)
          .setCustomStatus(
            emoji: status.emoji,
            text: status.text,
            duration: status.duration,
            expiresAt: expiresAt,
          );
      if (actionId != _actionId) return;
      state = AsyncData(
        CurrentUserProfileViewState(
          profile: current.profile.copyWith(
            customStatus: CustomStatus(
              emoji: status.emoji,
              text: status.text,
              expiresAt: expiresAt,
            ),
          ),
        ),
      );
    } on Object catch (error) {
      if (actionId != _actionId) return;
      state = AsyncData(
        current.copyWith(updateStatus: OperationStatus.failed(error)),
      );
    }
  }

  Future<void> clearCustomStatus() async {
    final CurrentUserProfileViewState? current = state.value;
    if (current == null || current.updateStatus is OperationInProgress) return;
    final int actionId = ++_actionId;
    state = AsyncData(
      current.copyWith(updateStatus: const OperationStatus.inProgress()),
    );
    try {
      await ref.read(_repositoryProvider).clearCustomStatus();
      if (actionId != _actionId) return;
      state = AsyncData(
        CurrentUserProfileViewState(
          profile: current.profile.copyWith(clearCustomStatus: true),
        ),
      );
    } on Object catch (error) {
      if (actionId != _actionId) return;
      state = AsyncData(
        current.copyWith(updateStatus: OperationStatus.failed(error)),
      );
    }
  }
}
