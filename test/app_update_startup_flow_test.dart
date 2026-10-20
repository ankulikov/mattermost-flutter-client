import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/app/app.dart';
import 'package:mattermost_flutter/src/app/router.dart';
import 'package:mattermost_flutter/src/data/providers/session_providers.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/authentication_methods.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';
import 'package:mattermost_flutter/src/domain/repositories/auth_repository.dart';
import 'package:mattermost_flutter/src/domain/services/realtime_connection_service.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/models/user_preferences.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/repositories/user_preferences_repository.dart';
import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';
import 'package:mattermost_flutter/src/features/updates/domain/repositories/app_update_repository.dart';
import 'package:mattermost_flutter/src/features/updates/presentation/app_update_page.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  testWidgets('startup prompt opens the existing update screen', (
    WidgetTester tester,
  ) async {
    addTearDown(() => appRouter.go('/'));
    final _UpdateRepository updates = _UpdateRepository();
    final _PreferencesRepository preferences = _PreferencesRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_SignedOutRepository()),
        realtimeConnectionServiceProvider.overrideWithValue(
          const _RealtimeService(),
        ),
        appUpdateRepositoryProvider.overrideWithValue(updates),
        userPreferencesRepositoryProvider.overrideWithValue(preferences),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(activeAccountSessionProvider.notifier)
        .set(
          AuthSession(
            serverUrl: Uri.parse('https://chat.example.com'),
            userId: 'user-a',
            username: 'ada',
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MattermostApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New version available'), findsOneWidget);
    expect(
      find.textContaining('New version available (1.0.0+10 -> 2.3.4)'),
      findsOneWidget,
    );
    expect(updates.checkCalls, 1);
    expect(preferences.writeCalls, 1);

    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(find.byType(AppUpdatePage), findsOneWidget);
    expect(updates.checkCalls, 2);
    expect(preferences.writeCalls, 2);
  });
}

final class _PreferencesRepository implements UserPreferencesRepository {
  int writeCalls = 0;
  DateTime? lastUpdateCheck;

  @override
  Future<UserPreferences> read() async => UserPreferences.defaults;

  @override
  Future<DateTime?> readLastUpdateCheck() async => lastUpdateCheck;

  @override
  Future<void> update(UserPreferences preferences) async {}

  @override
  Future<void> writeLastUpdateCheck(DateTime checkedAt) async {
    writeCalls += 1;
    lastUpdateCheck = checkedAt;
  }
}

final class _UpdateRepository implements AppUpdateRepository {
  int checkCalls = 0;

  @override
  Stream<UpdateInstallerEvent> get installerEvents =>
      const Stream<UpdateInstallerEvent>.empty();

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<UpdateCatalog> checkForUpdates() async {
    checkCalls += 1;
    final UpdateArtifact artifact = UpdateArtifact(
      name: 'mattermost-v2.3.4-arm64-v8a.apk',
      downloadUrl: Uri.parse('https://github.com/example/update.apk'),
      size: 10,
      sha256: 'a' * 64,
      abi: 'arm64-v8a',
    );
    final UpdateRelease release = UpdateRelease(
      version: const AppVersion(major: 2, minor: 3, patch: 4),
      title: 'Mattermost 2.3.4',
      notes: 'Release notes',
      publishedAt: DateTime.utc(2026, 10, 18),
      artifacts: <UpdateArtifact>[artifact],
    );
    return UpdateCatalog(
      installed: const InstalledApplication(
        version: AppVersion(major: 1, minor: 0, patch: 0),
        buildNumber: 10,
        packageName: 'com.mattermost.mattermost_flutter',
      ),
      newerReleases: <UpdateRelease>[release],
      candidate: UpdateCandidate(release: release, artifact: artifact),
      isComplete: true,
    );
  }

  @override
  Future<bool> canRequestPackageInstalls() async => true;

  @override
  Future<void> downloadAndInstall(
    UpdateCandidate candidate, {
    required void Function(double progress) onProgress,
  }) async {}

  @override
  Future<void> openPackageInstallSettings() async {}
}

final class _RealtimeService implements RealtimeConnectionService {
  const _RealtimeService();

  @override
  RealtimeConnectionStatus get connectionStatus =>
      RealtimeConnectionStatus.connected;

  @override
  Stream<RealtimeConnectionStatus> get connectionStatuses =>
      Stream<RealtimeConnectionStatus>.value(
        RealtimeConnectionStatus.connected,
      );

  @override
  void reconnect() {}
}

final class _SignedOutRepository implements AuthRepository {
  @override
  Future<AuthSession> authenticateWithPassword({
    required Uri serverUrl,
    required String loginId,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<AuthSession> authenticateWithSessionToken({
    required Uri serverUrl,
    required String token,
  }) => throw UnimplementedError();

  @override
  Future<AuthSession> authenticateWithSso({
    required Uri serverUrl,
    required SsoProvider provider,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelSsoAuthentication() async {}

  @override
  Future<AuthenticationMethods> discoverAuthenticationMethods({
    required Uri serverUrl,
  }) => throw UnimplementedError();

  @override
  Future<List<SsoOption>> discoverSsoOptions({required Uri serverUrl}) async =>
      const <SsoOption>[];

  @override
  Future<AuthSession?> restoreSession() async => null;

  @override
  Future<void> signOut() async {}
}
