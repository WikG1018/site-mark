import 'package:flutter/foundation.dart';

/// Selection state shared by capture list edit modes.
///
/// Owns the editing flag plus the set of currently-selected capture IDs.
/// Filter changes call [clearForFilterChange] so hidden rows do not remain
/// selected; the editing session itself stays open so the user can continue
/// selecting from the new result set. [selectedIds] is exposed as an
/// unmodifiable view to prevent external mutation.
class CaptureSelectionController extends ChangeNotifier {
  bool _editing = false;
  final Set<String> _selectedIds = <String>{};

  bool get editing => _editing;

  Set<String> get selectedIds => Set<String>.unmodifiable(_selectedIds);

  /// Enters selection mode. Idempotent: calling while already editing does
  /// not clear the existing selection.
  void enter() {
    _editing = true;
    notifyListeners();
  }

  /// Exits selection mode and drops all selected IDs.
  void exit() {
    _editing = false;
    _selectedIds.clear();
    notifyListeners();
  }

  /// Adds [id] to the selection if absent, otherwise removes it.
  void toggle(String id) {
    if (!_selectedIds.add(id)) {
      _selectedIds.remove(id);
    }
    notifyListeners();
  }

  /// Replaces the selection with [ids]. Intended for "select all" on the
  /// currently-visible eligible rows.
  void selectAll(Iterable<String> ids) {
    _selectedIds
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  /// Clears selected IDs after a filter change while keeping the editing
  /// session open. Hidden rows must not stay selected.
  void clearForFilterChange() {
    _selectedIds.clear();
    notifyListeners();
  }
}
