import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/domain/project_lifecycle.dart';

void main() {
  test('lifecycle storage values are stable', () {
    expect(ProjectLifecycleStatus.values.map((value) => value.name), [
      'active',
      'completed',
      'archived',
    ]);
    const converter = ProjectLifecycleStatusConverter();
    expect(converter.fromSql('completed'), ProjectLifecycleStatus.completed);
    expect(converter.toSql(ProjectLifecycleStatus.archived), 'archived');
    expect(() => converter.fromSql('deleted'), throwsStateError);
  });
}
