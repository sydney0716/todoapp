import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personaltodo/sync_contract.dart';

void main() {
  test('task sync fields match repository metadata', () {
    final metadata =
        jsonDecode(File('docs/sync_task_fields.json').readAsStringSync())
            as Map<String, Object?>;
    final metadataFields =
        (metadata['changed_task_fields'] as List<Object?>).cast<String>();

    expect(changedTaskFieldsPayloadKey, '_changed_task_fields');
    expect(metadataFields, taskSyncFieldNames.toList(growable: false));
  });
}
