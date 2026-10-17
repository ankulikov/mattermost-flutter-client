import 'dart:async';

import 'package:flutter/services.dart';
import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';

abstract interface class PackageInstallerGateway {
  Stream<UpdateInstallerEvent> get events;

  Future<bool> isSupported();

  Future<List<String>> supportedAbis();

  Future<int> versionCodeOffset();

  Future<bool> canRequestPackageInstalls();

  Future<void> openPackageInstallSettings();

  Future<void> install({
    required String apkPath,
    required String expectedPackageName,
  });
}

final class AndroidPackageInstallerGateway implements PackageInstallerGateway {
  AndroidPackageInstallerGateway({
    MethodChannel methodChannel = const MethodChannel(_methodChannelName),
    EventChannel eventChannel = const EventChannel(_eventChannelName),
  }) : _methodChannel = methodChannel,
       _eventChannel = eventChannel;

  static const String _methodChannelName =
      'com.mattermost.mattermost_flutter/app_update';
  static const String _eventChannelName =
      'com.mattermost.mattermost_flutter/app_update_events';

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  Stream<UpdateInstallerEvent>? _events;

  @override
  Stream<UpdateInstallerEvent> get events => _events ??= _eventChannel
      .receiveBroadcastStream()
      .where((Object? event) => event is Map<Object?, Object?>)
      .map(
        (Object? event) =>
            Map<Object?, Object?>.from(event! as Map<Object?, Object?>),
      )
      .map(_mapEvent)
      .handleError((Object _) {})
      .asBroadcastStream();

  @override
  Future<bool> isSupported() async {
    try {
      return await _methodChannel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<List<String>> supportedAbis() async {
    final List<Object?>? values = await _methodChannel
        .invokeListMethod<Object?>('getSupportedAbis');
    return values?.whereType<String>().toList(growable: false) ??
        const <String>[];
  }

  @override
  Future<int> versionCodeOffset() async =>
      await _methodChannel.invokeMethod<int>('getVersionCodeOffset') ?? 0;

  @override
  Future<bool> canRequestPackageInstalls() async =>
      await _methodChannel.invokeMethod<bool>('canRequestPackageInstalls') ??
      false;

  @override
  Future<void> openPackageInstallSettings() =>
      _methodChannel.invokeMethod<void>('openPackageInstallSettings');

  @override
  Future<void> install({
    required String apkPath,
    required String expectedPackageName,
  }) async {
    try {
      await _methodChannel.invokeMethod<int>('installApk', <String, Object>{
        'path': apkPath,
        'expectedPackageName': expectedPackageName,
      });
    } on PlatformException catch (error) {
      if (error.code == 'permission_required') {
        throw const AppUpdatePermissionRequiredException();
      }
      throw AppUpdateInstallException(
        error.code,
        rawError: _platformErrorDetails(error),
      );
    }
  }

  UpdateInstallerEvent _mapEvent(Map<Object?, Object?> event) {
    final String type = event['type'] as String? ?? 'failure';
    return switch (type) {
      'awaitingUserAction' => const UpdateInstallerAwaitingUserAction(),
      'installing' => const UpdateInstallerInstalling(),
      'success' => const UpdateInstallerSucceeded(),
      'cancelled' => const UpdateInstallerCancelled(),
      _ => UpdateInstallerFailed(
        event['reason'] as String? ?? 'unknown',
        rawError: event['rawError'] as String?,
      ),
    };
  }

  String _platformErrorDetails(PlatformException error) {
    final List<String> parts = <String>['code=${error.code}'];
    if (error.message case final String message when message.isNotEmpty) {
      parts.add('message=$message');
    }
    if (error.details != null) parts.add('details=${error.details}');
    return parts.join('; ');
  }
}
