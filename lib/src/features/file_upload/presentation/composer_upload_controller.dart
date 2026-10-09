import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/features/file_upload/domain/file_upload.dart';

enum UploadTileStatus { queued, uploading, finalizing, uploaded, failed }

final class UploadTile {
  UploadTile({required this.localId, required SelectedUploadFile file})
    : name = file.name,
      size = file.size,
      type = file.type,
      source = file;

  final int localId;
  final String name;
  final int size;
  final String? type;
  SelectedUploadFile? source;
  UploadTileStatus status = UploadTileStatus.queued;
  int percent = 0;
  String? fileId;
  UploadFailure? failure;
  DateTime? retryAt;
  RequestCancellation? cancellation;
  Timer? retryTimer;
  int generation = 0;
}

/// Volatile queue for a single account, channel and composer destination.
final class ComposerUploadController extends ChangeNotifier {
  ComposerUploadController({required this.repository, required this.channelId});

  final FileUploadRepository repository;
  final String channelId;
  final List<UploadTile> _tiles = <UploadTile>[];
  int _nextId = 0;
  int _active = 0;
  bool _closed = false;

  List<UploadTile> get tiles => List<UploadTile>.unmodifiable(_tiles);
  bool get canAdd => !_closed && _tiles.length < 5;
  bool get ready =>
      _tiles.every((tile) => tile.status == UploadTileStatus.uploaded);
  List<String> get uploadedIds => List<String>.unmodifiable(
    _tiles.map((tile) => tile.fileId!).toList(growable: false),
  );

  bool addFiles(List<SelectedUploadFile> files) {
    if (_closed || _tiles.length + files.length > 5) return false;
    for (final file in files) {
      _tiles.add(UploadTile(localId: _nextId++, file: file));
    }
    notifyListeners();
    _startQueued();
    return true;
  }

  void remove(int localId) {
    final int index = _tiles.indexWhere((tile) => tile.localId == localId);
    if (index < 0) return;
    final UploadTile tile = _tiles.removeAt(index);
    tile.generation++;
    tile.cancellation?.cancel();
    tile.retryTimer?.cancel();
    notifyListeners();
    _startQueued();
  }

  void retry(int localId) {
    final int index = _tiles.indexWhere((tile) => tile.localId == localId);
    if (index < 0) return;
    final UploadTile tile = _tiles[index];
    if (tile.status != UploadTileStatus.failed ||
        (tile.retryAt != null && DateTime.now().isBefore(tile.retryAt!))) {
      return;
    }
    tile.retryTimer?.cancel();
    tile
      ..status = UploadTileStatus.queued
      ..failure = null
      ..retryAt = null
      ..percent = 0;
    notifyListeners();
    _startQueued();
  }

  void clear() {
    for (final tile in _tiles) {
      tile.generation++;
      tile.cancellation?.cancel();
      tile.retryTimer?.cancel();
    }
    _tiles.clear();
    notifyListeners();
  }

  void _startQueued() {
    while (!_closed && _active < 2) {
      final int index = _tiles.indexWhere(
        (tile) => tile.status == UploadTileStatus.queued,
      );
      if (index < 0) return;
      final UploadTile tile = _tiles[index];
      tile.status = UploadTileStatus.uploading;
      final int generation = ++tile.generation;
      final RequestCancellation cancellation = RequestCancellation();
      tile.cancellation = cancellation;
      _active++;
      notifyListeners();
      unawaited(_upload(tile, generation, cancellation));
    }
  }

  bool _current(UploadTile tile, int generation) =>
      !_closed && _tiles.contains(tile) && tile.generation == generation;

  Future<void> _upload(
    UploadTile tile,
    int generation,
    RequestCancellation cancellation,
  ) async {
    try {
      final String id = await repository.upload(
        channelId: channelId,
        file: tile.source!,
        cancellation: cancellation,
        onProgress: (int sent, int total) {
          if (!_current(tile, generation) || total <= 0) return;
          final int percent = (sent * 100 ~/ total).clamp(0, 100);
          final bool changed =
              percent >= tile.percent + 5 ||
              (percent == 100 && tile.status != UploadTileStatus.finalizing);
          if (percent == 100) {
            tile.status = UploadTileStatus.finalizing;
          }
          if (changed) {
            tile.percent = percent;
            notifyListeners();
          }
        },
      );
      if (!_current(tile, generation)) return;
      tile
        ..fileId = id
        ..source = null
        ..status = UploadTileStatus.uploaded
        ..percent = 100;
      notifyListeners();
    } on Object catch (error) {
      if (!_current(tile, generation)) return;
      final UploadException? failure = error is UploadException ? error : null;
      tile
        ..status = UploadTileStatus.failed
        ..failure = failure?.failure ?? UploadFailure.unavailable
        ..retryAt = null;
      final Duration? retryAfter = failure?.retryAfter;
      if (tile.failure == UploadFailure.rateLimited ||
          tile.failure == UploadFailure.unavailable) {
        final Duration delay =
            retryAfter ?? Duration(milliseconds: 800 + Random().nextInt(400));
        tile.retryAt = DateTime.now().add(delay);
        tile.retryTimer = Timer(delay, () {
          if (!_current(tile, generation)) return;
          tile.retryAt = null;
          notifyListeners();
        });
      }
      notifyListeners();
    } finally {
      _active--;
      _startQueued();
    }
  }

  @override
  void dispose() {
    _closed = true;
    clear();
    super.dispose();
  }
}
