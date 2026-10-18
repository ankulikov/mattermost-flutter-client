abstract final class AppUpdateStrings {
  static const String title = 'App updates';
  static const String checkForUpdates = 'Check for updates';
  static const String checking = 'Checking for updates';
  static const String retry = 'Retry';
  static const String installedVersion = 'Installed version';
  static const String availableVersion = 'Available version';
  static const String upToDate = 'You are using the latest version.';
  static const String unsupported =
      'In-app updates are currently available on Android only.';
  static const String checkFailed = 'Could not check for updates.';
  static const String rateLimited =
      'GitHub is temporarily limiting update checks. Try again later.';
  static const String partialHistory =
      'Some release history could not be loaded. Retry before installing.';
  static const String noCompatibleBuild =
      'No compatible Android build is available for this device.';
  static const String whatsNew = "What's new";
  static const String noReleaseNotes = 'No release notes were provided.';
  static const String installPermissionTitle = 'Allow app installations';
  static const String installPermissionDescription =
      'Android must allow Mattermost to install updates from this source.';
  static const String openSettings = 'Open Android settings';
  static const String downloading = 'Downloading update';
  static const String verifying = 'Verifying and preparing the update';
  static const String confirmationRequired =
      'Confirm the update in the Android system installer.';
  static const String installing = 'Android is installing the update.';
  static const String installComplete = 'Update installed.';
  static const String installFailed = 'Could not install the update.';
  static const String checksumFailed =
      'The downloaded update failed its security check. Please retry.';

  static String installVersion(String version) => 'Install $version';

  static String version(String version) => 'Version $version';

  static String downloadPercent(int percent) => 'Downloading update: $percent%';
}
