import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:sitemark/domain/capture_list_query.dart';

/// The filtered list and row position that opened a capture detail route.
final class CaptureNavigationContext {
  const CaptureNavigationContext({required this.query, required this.cursor});

  final CaptureListQuery query;
  final CapturePageCursor cursor;
}

/// Lazily resolves one photo shown by the fullscreen viewer.
///
/// [initialPath] and [previewImage] keep the tapped photo visible while the
/// full-resolution image is resolved.
final class CaptureFullscreenPhoto {
  CaptureFullscreenPhoto({
    required this.id,
    required this.resolvePath,
    this.initialPath,
    this.previewImage,
    this.includeInSequence = true,
  });

  factory CaptureFullscreenPhoto.resolved({
    required String path,
    ImageProvider<Object>? previewImage,
  }) {
    return CaptureFullscreenPhoto(
      id: path,
      initialPath: path,
      previewImage: previewImage,
      resolvePath: () async => path,
    );
  }

  final String id;
  final Future<String?> Function() resolvePath;
  final String? initialPath;
  final ImageProvider<Object>? previewImage;

  /// False for rows that advance an adjacent-page cursor but cannot display
  /// the source selected in detail (for example, a cleared original).
  final bool includeInSequence;
}

enum CaptureFullscreenDirection { newer, older }

typedef CaptureFullscreenPageLoader =
    Future<List<CaptureFullscreenPhoto>> Function(
      CaptureFullscreenDirection direction,
      String anchorId,
    );

/// A current-first, incrementally loaded fullscreen photo sequence.
final class CaptureFullscreenSequence extends ChangeNotifier {
  CaptureFullscreenSequence({
    required CaptureFullscreenPhoto current,
    required this.loader,
    this.pageSize = 10,
  }) : assert(pageSize > 0),
       _photos = [current],
       _seenIds = {current.id},
       _currentId = current.id,
       _newerAnchorId = current.id,
       _olderAnchorId = current.id;

  final int pageSize;
  final CaptureFullscreenPageLoader loader;
  final List<CaptureFullscreenPhoto> _photos;
  final Set<String> _seenIds;
  String _currentId;
  String _newerAnchorId;
  String _olderAnchorId;
  Future<void>? _newerPending;
  Future<void>? _olderPending;
  Object? _newerError;
  Object? _olderError;
  bool _newerEnded = false;
  bool _olderEnded = false;
  bool _disposed = false;

  List<CaptureFullscreenPhoto> get photos => UnmodifiableListView(_photos);
  String get currentId => _currentId;
  bool get newerLoading => _newerPending != null;
  bool get olderLoading => _olderPending != null;
  bool get newerEnded => _newerEnded;
  bool get olderEnded => _olderEnded;
  Object? get newerError => _newerError;
  Object? get olderError => _olderError;

  void select(String id) {
    if (_disposed || !_photos.any((photo) => photo.id == id)) return;
    _currentId = id;
  }

  Future<void> loadNewer() => _start(CaptureFullscreenDirection.newer);

  Future<void> loadOlder() => _start(CaptureFullscreenDirection.older);

  Future<void> retryNewer() => _retry(CaptureFullscreenDirection.newer);

  Future<void> retryOlder() => _retry(CaptureFullscreenDirection.older);

  Future<void> _retry(CaptureFullscreenDirection direction) {
    if (_disposed) return Future.value();
    if (direction == CaptureFullscreenDirection.newer) {
      _newerError = null;
    } else {
      _olderError = null;
    }
    return _start(direction);
  }

  Future<void> _start(CaptureFullscreenDirection direction) {
    if (_disposed || _ended(direction) || _error(direction) != null) {
      return Future.value();
    }
    final pending = _pending(direction);
    if (pending != null) return pending;

    final completer = Completer<void>();
    if (direction == CaptureFullscreenDirection.newer) {
      _newerPending = completer.future;
      _newerError = null;
    } else {
      _olderPending = completer.future;
      _olderError = null;
    }
    notifyListeners();
    unawaited(_perform(direction, completer));
    return completer.future;
  }

  Future<void> _perform(
    CaptureFullscreenDirection direction,
    Completer<void> completer,
  ) async {
    try {
      final anchorId = direction == CaptureFullscreenDirection.newer
          ? _newerAnchorId
          : _olderAnchorId;
      final loaded = await loader(direction, anchorId);
      if (_disposed) return;

      final unique = <CaptureFullscreenPhoto>[];
      for (final photo in loaded) {
        if (_seenIds.add(photo.id) && photo.includeInSequence) {
          unique.add(photo);
        }
      }
      if (direction == CaptureFullscreenDirection.newer) {
        _photos.insertAll(0, unique);
      } else {
        _photos.addAll(unique);
      }
      final nextAnchorId = loaded.isEmpty
          ? anchorId
          : direction == CaptureFullscreenDirection.newer
          ? loaded.first.id
          : loaded.last.id;
      if (direction == CaptureFullscreenDirection.newer) {
        _newerAnchorId = nextAnchorId;
      } else {
        _olderAnchorId = nextAnchorId;
      }
      if (loaded.length < pageSize || nextAnchorId == anchorId) {
        _setEnded(direction);
      }
    } catch (error) {
      if (!_disposed) _setError(direction, error);
    } finally {
      if (!_disposed) {
        if (direction == CaptureFullscreenDirection.newer) {
          _newerPending = null;
        } else {
          _olderPending = null;
        }
        notifyListeners();
      }
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<void>? _pending(CaptureFullscreenDirection direction) =>
      direction == CaptureFullscreenDirection.newer
      ? _newerPending
      : _olderPending;

  bool _ended(CaptureFullscreenDirection direction) =>
      direction == CaptureFullscreenDirection.newer ? _newerEnded : _olderEnded;

  Object? _error(CaptureFullscreenDirection direction) =>
      direction == CaptureFullscreenDirection.newer ? _newerError : _olderError;

  void _setEnded(CaptureFullscreenDirection direction) {
    if (direction == CaptureFullscreenDirection.newer) {
      _newerEnded = true;
    } else {
      _olderEnded = true;
    }
  }

  void _setError(CaptureFullscreenDirection direction, Object error) {
    if (direction == CaptureFullscreenDirection.newer) {
      _newerError = error;
    } else {
      _olderError = error;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
