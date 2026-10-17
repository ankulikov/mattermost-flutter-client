import 'dart:async';

import 'package:dio/dio.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';

final class GithubReleaseAssetDto {
  const GithubReleaseAssetDto({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.digest,
  });

  factory GithubReleaseAssetDto.fromJson(Map<String, Object?> json) =>
      GithubReleaseAssetDto(
        name: json['name'] as String? ?? '',
        downloadUrl: Uri.tryParse(
          json['browser_download_url'] as String? ?? '',
        ),
        size: json['size'] as int? ?? -1,
        digest: json['digest'] as String?,
      );

  final String name;
  final Uri? downloadUrl;
  final int size;
  final String? digest;
}

final class GithubReleaseDto {
  const GithubReleaseDto({
    required this.tagName,
    required this.name,
    required this.body,
    required this.draft,
    required this.prerelease,
    required this.publishedAt,
    required this.assets,
  });

  factory GithubReleaseDto.fromJson(Map<String, Object?> json) {
    final Object? rawAssets = json['assets'];
    return GithubReleaseDto(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      draft: json['draft'] as bool? ?? false,
      prerelease: json['prerelease'] as bool? ?? false,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      assets: rawAssets is List<Object?>
          ? rawAssets
                .whereType<Map<String, Object?>>()
                .map(GithubReleaseAssetDto.fromJson)
                .toList(growable: false)
          : const <GithubReleaseAssetDto>[],
    );
  }

  final String tagName;
  final String name;
  final String body;
  final bool draft;
  final bool prerelease;
  final DateTime? publishedAt;
  final List<GithubReleaseAssetDto> assets;
}

final class GithubReleaseListing {
  const GithubReleaseListing({
    required this.releases,
    required this.isComplete,
  });

  final List<GithubReleaseDto> releases;
  final bool isComplete;
}

final class GithubReleaseApi {
  GithubReleaseApi({required Dio dio, DateTime Function()? clock})
    : _dio = dio,
      _clock = clock ?? DateTime.now;

  static const int _perPage = 100;
  static const int _maximumPages = 10;

  final Dio _dio;
  final DateTime Function() _clock;
  final Map<int, _CachedGithubPage> _cache = <int, _CachedGithubPage>{};
  DateTime? _retryAt;

  Future<GithubReleaseListing> listStableReleases() async {
    final DateTime? retryAt = _retryAt;
    if (retryAt != null && _clock().isBefore(retryAt)) {
      throw AppUpdateRateLimitedException(retryAt);
    }

    final List<GithubReleaseDto> releases = <GithubReleaseDto>[];
    var page = 1;
    var hasNext = true;
    while (hasNext && page <= _maximumPages) {
      try {
        final _GithubPage result = await _loadPage(page);
        releases.addAll(
          result.releases.where(
            (GithubReleaseDto release) => !release.draft && !release.prerelease,
          ),
        );
        hasNext = result.hasNext;
        page += 1;
      } on AppUpdateRateLimitedException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } on Object {
        if (releases.isEmpty) rethrow;
        return GithubReleaseListing(
          releases: List<GithubReleaseDto>.unmodifiable(releases),
          isComplete: false,
        );
      }
    }
    return GithubReleaseListing(
      releases: List<GithubReleaseDto>.unmodifiable(releases),
      isComplete: !hasNext,
    );
  }

  Future<_GithubPage> _loadPage(int page) async {
    final CancelToken cancelToken = CancelToken();
    final RequestCancellation? cancellation = RequestCancellation.current;
    final void Function()? detach = cancellation?.addListener(
      (Object? reason) => cancelToken.cancel(reason),
    );
    final _CachedGithubPage? cached = _cache[page];
    try {
      final Response<Object?> response = await _dio.get<Object?>(
        '/repos/ankulikov/mattermost-flutter-client/releases',
        queryParameters: <String, Object?>{'per_page': _perPage, 'page': page},
        options: Options(
          headers: <String, String>{
            if (cached?.etag != null) 'If-None-Match': cached!.etag!,
          },
          validateStatus: (int? status) => status == 200 || status == 304,
        ),
        cancelToken: cancelToken,
      );
      if (response.statusCode == 304 && cached != null) return cached.page;
      final Object? data = response.data;
      if (data is! List<Object?>) {
        throw const AppUpdateInvalidReleaseException(
          'GitHub returned an invalid releases response.',
        );
      }
      final List<GithubReleaseDto> parsed = data
          .whereType<Map<String, Object?>>()
          .map(GithubReleaseDto.fromJson)
          .toList(growable: false);
      final String? link = response.headers.value('link');
      final _GithubPage result = _GithubPage(
        releases: parsed,
        hasNext:
            _hasNextPage(link) || (link == null && parsed.length == _perPage),
      );
      _cache[page] = _CachedGithubPage(
        etag: response.headers.value('etag'),
        page: result,
      );
      return result;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        throw RequestCancelledException(error.error);
      }
      final int? status = error.response?.statusCode;
      if (status == 403 || status == 429) {
        final DateTime? retryAt = _rateLimitRetryAt(error.response?.headers);
        _retryAt = retryAt ?? _clock().add(const Duration(minutes: 5));
        throw AppUpdateRateLimitedException(_retryAt);
      }
      rethrow;
    } finally {
      detach?.call();
    }
  }

  bool _hasNextPage(String? link) =>
      link?.split(',').any((String part) => part.contains('rel="next"')) ??
      false;

  DateTime? _rateLimitRetryAt(Headers? headers) {
    if (headers == null) return null;
    final int? retrySeconds = int.tryParse(headers.value('retry-after') ?? '');
    if (retrySeconds != null) {
      return _clock().add(Duration(seconds: retrySeconds));
    }
    final int? resetSeconds = int.tryParse(
      headers.value('x-ratelimit-reset') ?? '',
    );
    return resetSeconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(resetSeconds * 1000);
  }
}

final class _GithubPage {
  const _GithubPage({required this.releases, required this.hasNext});

  final List<GithubReleaseDto> releases;
  final bool hasNext;
}

final class _CachedGithubPage {
  const _CachedGithubPage({required this.etag, required this.page});

  final String? etag;
  final _GithubPage page;
}
