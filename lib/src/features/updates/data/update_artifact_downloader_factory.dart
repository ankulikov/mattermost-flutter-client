import 'package:dio/dio.dart';
import 'package:mattermost_flutter/src/features/updates/data/update_artifact_downloader.dart';
import 'package:mattermost_flutter/src/features/updates/data/update_artifact_downloader_stub.dart'
    if (dart.library.io) 'package:mattermost_flutter/src/features/updates/data/update_artifact_downloader_io.dart'
    as implementation;

UpdateArtifactDownloader createUpdateArtifactDownloader(Dio dio) =>
    implementation.createUpdateArtifactDownloader(dio);
