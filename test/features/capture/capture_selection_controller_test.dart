import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/features/capture/capture_selection_controller.dart';

void main() {
  test('filter change clears hidden selections', () {
    final controller = CaptureSelectionController()..enter();
    controller.toggle('a');
    controller.toggle('b');
    controller.clearForFilterChange();
    expect(controller.selectedIds, isEmpty);
    expect(controller.editing, isTrue);
  });

  test('select all replaces selection with visible eligible IDs', () {
    final controller = CaptureSelectionController()..enter();
    controller.selectAll(['a', 'c']);
    expect(controller.selectedIds, {'a', 'c'});
  });

  test('toggle all selects then deselects the same eligible IDs', () {
    final controller = CaptureSelectionController()..enter();

    controller.toggleAll(['a', 'b']);
    expect(controller.selectedIds, {'a', 'b'});
    expect(controller.allSelected(['a', 'b']), isTrue);

    controller.toggleAll(['a', 'b']);
    expect(controller.selectedIds, isEmpty);
    expect(controller.allSelected(['a', 'b']), isFalse);
  });

  test('an empty eligible set is never considered fully selected', () {
    final controller = CaptureSelectionController()..enter();
    expect(controller.allSelected(const []), isFalse);
  });
}
