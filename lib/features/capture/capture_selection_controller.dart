import 'package:flutter/foundation.dart';
import 'package:sitemark/data/capture_query_repository.dart';

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
  bool _allSelectedReady = false;

  bool get editing => _editing;

  Set<String> get selectedIds => Set<String>.unmodifiable(_selectedIds);

  /// Whether the latest complete qualification found every selected capture
  /// eligible and ready. Individual selection changes invalidate this value
  /// until the host finishes a fresh `inspectSelection` request.
  bool get allSelectedReady => _selectedIds.isNotEmpty && _allSelectedReady;

  /// Enters selection mode. Idempotent: calling while already editing does
  /// not clear the existing selection.
  void enter() {
    _editing = true;
    notifyListeners();
  }

  /// Enters selection mode (if not already editing) and selects [id] in one
  /// step. Host lists call this when a card reports `onSelectedChanged(true)`
  /// outside selection mode (long-press to multi-select).
  void enterWithSelection(String id) {
    _editing = true;
    _selectedIds.add(id);
    _allSelectedReady = false;
    notifyListeners();
  }

  /// Exits selection mode and drops all selected IDs.
  void exit() {
    _editing = false;
    _selectedIds.clear();
    _allSelectedReady = false;
    notifyListeners();
  }

  /// Adds [id] to the selection if absent, otherwise removes it.
  void toggle(String id) {
    if (!_selectedIds.add(id)) {
      _selectedIds.remove(id);
    }
    _allSelectedReady = false;
    notifyListeners();
  }

  /// Replaces the selection with [ids]. Intended for "select all" on the
  /// currently-visible eligible rows.
  void selectAll(Iterable<String> ids) {
    replaceAll(ids, allReady: false);
  }

  /// Replaces the complete selection, including IDs that are not loaded in
  /// the current page, and records the matching readiness qualification.
  void replaceAll(Iterable<String> ids, {required bool allReady}) {
    _selectedIds
      ..clear()
      ..addAll(ids);
    _allSelectedReady = _selectedIds.isNotEmpty && allReady;
    notifyListeners();
  }

  /// Whether every currently eligible row is selected. An empty eligible set
  /// is never treated as fully selected.
  bool allSelected(Iterable<String> eligibleIds) {
    final eligible = eligibleIds.toSet();
    return eligible.isNotEmpty && eligible.every(_selectedIds.contains);
  }

  /// Selects all eligible rows, or clears the selection when they are already
  /// all selected.
  void toggleAll(Iterable<String> eligibleIds) {
    final eligible = eligibleIds.toSet();
    if (allSelected(eligible)) {
      replaceAll(const [], allReady: false);
    } else {
      replaceAll(eligible, allReady: false);
    }
  }

  /// Applies a query-wide selectable snapshot, or clears when the same full
  /// result set is already selected.
  void toggleAllSnapshot(CaptureSelectionSnapshot snapshot) {
    final alreadySelected =
        snapshot.ids.isNotEmpty &&
        _selectedIds.length == snapshot.ids.length &&
        snapshot.ids.every(_selectedIds.contains);
    if (alreadySelected) {
      replaceAll(const [], allReady: false);
    } else {
      replaceAll(snapshot.ids, allReady: snapshot.allReady);
    }
  }

  /// Clears selected IDs after a filter change while keeping the editing
  /// session open. Hidden rows must not stay selected.
  void clearForFilterChange() {
    _selectedIds.clear();
    _allSelectedReady = false;
    notifyListeners();
  }
}
