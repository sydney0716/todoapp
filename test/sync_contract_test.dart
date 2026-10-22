import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personaltodo/sync_contract.dart';

void main() {
  test('task sync fields match repository metadata', () {
    final metadata = jsonDecode(
      File('test/fixtures/sync_task_fields.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final metadataFields =
        (metadata['changed_task_fields'] as List<Object?>).cast<String>();

    expect(changedTaskFieldsPayloadKey, '_changed_task_fields');
    expect(metadataFields, taskSyncFieldNames.toList(growable: false));
  });

  test('queue payload parsing preserves legacy values and rejects malformed data',
      () {
    expect(decodeSyncPayload(null), isNull);
    for (final json in ['null', '[]', 'true', '42', '"text"']) {
      expect(decodeSyncPayload(json), isNull);
    }
    expect(decodeSyncPayload('{"title":"할 일","note":null,"subtasks":[]}'),
        {'title': '할 일', 'note': null, 'subtasks': []});
    expect(decodeSyncPayload('{broken'), isNull);
    expect(decodeSyncPayload(''), isNull);
  });

  test('queued changed fields keep their order and tolerate mixed metadata',
      () {
    expect(changedTaskFieldsFromPayload({}), isEmpty);
    expect(changedTaskFieldsFromPayload({changedTaskFieldsPayloadKey: 'title'}),
        isEmpty);
    expect(
      changedTaskFieldsFromPayload({
        changedTaskFieldsPayloadKey: ['title', null, 42, 'note', 'title'],
      }),
      ['title', 'note', 'title'],
    );
  });
}
