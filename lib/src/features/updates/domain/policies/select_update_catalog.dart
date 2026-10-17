import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';

UpdateCatalog selectUpdateCatalog({
  required InstalledApplication installed,
  required Iterable<UpdateRelease> releases,
  required List<String> supportedAbis,
  required bool isComplete,
}) {
  final List<UpdateRelease> newer =
      releases
          .where(
            (UpdateRelease release) => release.version.isNewerThan(installed),
          )
          .toList(growable: false)
        ..sort(
          (UpdateRelease left, UpdateRelease right) =>
              left.version.compareTo(right.version),
        );

  UpdateCandidate? candidate;
  for (final UpdateRelease release in newer.reversed) {
    final UpdateArtifact? artifact = release.compatibleArtifact(supportedAbis);
    if (artifact != null) {
      candidate = UpdateCandidate(release: release, artifact: artifact);
      break;
    }
  }

  return UpdateCatalog(
    installed: installed,
    newerReleases: List<UpdateRelease>.unmodifiable(newer),
    candidate: candidate,
    isComplete: isComplete,
  );
}
