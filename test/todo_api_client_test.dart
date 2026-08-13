import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personaltodo/api/todo_api_client.dart';
import 'package:personaltodo/api/todo_api_models.dart';
import 'package:personaltodo/models.dart';

import 'helpers/todo_api_test_helpers.dart';

const userId = defaultCurrentUserId;
const deviceId = '11111111-1111-4111-8111-111111111111';

void main() {
  test('login posts credentials and parses auth session', () async {
    final transport = FakeTodoApiTransport([
      jsonResponse({
        'access_token': 'access-token',
        'refresh_token': 'refresh-token',
        'token_type': 'bearer',
        'user_id': userId,
        'device_id': deviceId,
      }),
    ]);
    final client = TodoApiClient(
      baseUrl: 'https://example.test/api/',
      transport: transport,
    );

    final session = await client.login(
      username: 'user1',
      password: 'private-password',
      deviceId: deviceId,
      platform: 'test',
    );

    expect(session.accessToken, 'access-token');
    expect(session.refreshToken, 'refresh-token');
    expect(session.userId, userId);
    expect(session.deviceId, deviceId);

    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.toString(), 'https://example.test/api/auth/login');
    expect(request.headers['Content-Type'], 'application/json');
    final body = jsonDecode(request.body!) as Map<String, Object?>;
    expect(body['username'], 'user1');
    expect(body['password'], 'private-password');
    expect(body['device_id'], deviceId);
    expect(body['device_name'], 'Flutter Todo App');
    expect(body['platform'], 'test');
  });

  test('refresh posts refresh token and parses replacement tokens', () async {
    final transport = FakeTodoApiTransport([
      jsonResponse({
        'access_token': 'new-access-token',
        'refresh_token': 'new-refresh-token',
        'token_type': 'bearer',
        'user_id': userId,
        'device_id': deviceId,
      }),
    ]);
    final client = TodoApiClient(transport: transport);

    final session = await client.refresh(
      refreshToken: 'old-refresh-token',
      deviceId: deviceId,
    );

    expect(session.accessToken, 'new-access-token');
    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.toString(), 'https://hytodo.duckdns.org/auth/refresh');
    final body = jsonDecode(request.body!) as Map<String, Object?>;
    expect(body['refresh_token'], 'old-refresh-token');
    expect(body['device_id'], deviceId);
  });

  test('verifyConnection logs in then bootstraps with bearer token', () async {
    final transport = FakeTodoApiTransport([
      jsonResponse({
        'access_token': 'access-token',
        'refresh_token': 'refresh-token',
        'token_type': 'bearer',
        'user_id': userId,
        'device_id': deviceId,
      }),
      jsonResponse({
        'cursor': '0',
        'tasks': <Object?>[],
      }),
    ]);
    final client = TodoApiClient(transport: transport);

    final result = await client.verifyConnection(
      username: 'user1',
      password: 'private-password',
      deviceId: deviceId,
    );

    expect(result.bootstrap.cursor, '0');
    expect(result.bootstrap.tasks, isEmpty);
    expect(transport.requests, hasLength(2));
    expect(transport.requests[0].uri.path, '/auth/login');
    expect(transport.requests[1].method, 'GET');
    expect(transport.requests[1].uri.path, '/sync/bootstrap');
    expect(
      transport.requests[1].headers['Authorization'],
      'Bearer access-token',
    );
    expect(transport.requests[1].body, isNull);
  });

  test('bootstrap parses remote task records for later repository sync',
      () async {
    final bootstrap = SyncBootstrap.fromJson({
      'cursor': '12',
      'tasks': [
        {
          'id': '22222222-2222-4222-8222-222222222222',
          'owner_user_id': userId,
          'visibility': 'private',
          'workspace_id': null,
          'title': 'Remote task',
          'note': 'From server',
          'category': 'Work',
          'is_completed': false,
          'due_at': '2026-06-05T03:00:00Z',
          'reminder_option': 'none',
          'reminder_value': null,
          'created_at': '2026-06-05T01:00:00Z',
          'updated_at': '2026-06-05T02:00:00Z',
          'version': 3,
          'deleted_at': null,
          'purge_after': null,
          'created_by_user_id': userId,
          'updated_by_user_id': userId,
          'device_id': deviceId,
          'subtasks': [
            {
              'id': '33333333-3333-4333-8333-333333333333',
              'task_id': '22222222-2222-4222-8222-222222222222',
              'title': 'Remote subtask',
              'is_completed': true,
              'due_at': '2026-06-05T04:00:00Z',
              'position': 0,
              'updated_at': '2026-06-05T02:30:00Z',
              'version': 1,
              'deleted_at': null,
            },
          ],
        },
      ],
    });

    expect(bootstrap.cursor, '12');
    expect(bootstrap.tasks.single.title, 'Remote task');
    expect(bootstrap.tasks.single.subtasks.single.title, 'Remote subtask');

    final task = bootstrap.tasks.single.toTodoTask();
    expect(task.syncId, '22222222-2222-4222-8222-222222222222');
    expect(task.syncStatus, SyncStatus.synced);
    expect(task.subTasks.single.syncStatus, SyncStatus.synced);
    expect(task.subTasks.single.dueDateTime,
        DateTime.parse('2026-06-05T04:00:00Z'));
  });

  test('pushTaskChanges posts task changes and parses accepted records',
      () async {
    final remoteTask = _remoteTaskJson(
      id: '22222222-2222-4222-8222-222222222222',
      title: 'Accepted task',
    );
    final transport = FakeTodoApiTransport([
      jsonResponse({
        'cursor': '13',
        'accepted': [remoteTask],
        'rejected': <Object?>[],
      }),
    ]);
    final client = TodoApiClient(transport: transport);

    final result = await client.pushTaskChanges(
      accessToken: 'access-token',
      deviceId: deviceId,
      changes: [
        SyncTaskChange(
          operation: 'upsert',
          record: remoteTask,
          changedTaskFields: const ['title'],
          changedSubtaskIds: const ['33333333-3333-4333-8333-333333333333'],
        ),
      ],
    );

    expect(result.cursor, '13');
    expect(result.accepted.single.title, 'Accepted task');
    expect(result.rejected, isEmpty);

    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/sync/tasks');
    expect(request.headers['Authorization'], 'Bearer access-token');
    final body = jsonDecode(request.body!) as Map<String, Object?>;
    expect(body['device_id'], deviceId);
    expect(body.containsKey('base_cursor'), isFalse);
    final changes = body['changes'] as List<Object?>;
    expect(changes, hasLength(1));
    final change = changes.single as Map<String, Object?>;
    expect(change['operation'], 'upsert');
    expect(change['changed_task_fields'], ['title']);
    expect(change['changed_subtask_ids'], [
      '33333333-3333-4333-8333-333333333333',
    ]);
  });

  test('pullTaskChanges reads cursor changes', () async {
    final transport = FakeTodoApiTransport([
      jsonResponse({
        'cursor': '14',
        'changes': [
          {
            'operation': 'upsert',
            'event_id': 14,
            'origin_device_id': '99999999-9999-4999-8999-999999999999',
            'changed_task_fields': ['title'],
            'changed_subtask_ids': ['33333333-3333-4333-8333-333333333333'],
            'record': _remoteTaskJson(
              id: '22222222-2222-4222-8222-222222222222',
              title: 'Pulled task',
            ),
          },
        ],
      }),
    ]);
    final client = TodoApiClient(transport: transport);

    final result = await client.pullTaskChanges(
      accessToken: 'access-token',
      cursor: '12',
    );

    expect(result.cursor, '14');
    expect(result.changes.single.operation, 'upsert');
    expect(result.changes.single.eventId, 14);
    expect(
      result.changes.single.originDeviceId,
      '99999999-9999-4999-8999-999999999999',
    );
    expect(result.changes.single.changedTaskFields, ['title']);
    expect(
      result.changes.single.changedSubtaskIds,
      ['33333333-3333-4333-8333-333333333333'],
    );
    expect(result.changes.single.record.title, 'Pulled task');
    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.toString(),
        'https://hytodo.duckdns.org/sync/tasks?cursor=12');
    expect(request.headers['Authorization'], 'Bearer access-token');
  });
}

Map<String, Object?> _remoteTaskJson({
  required String id,
  required String title,
}) {
  return {
    'id': id,
    'owner_user_id': userId,
    'visibility': 'private',
    'workspace_id': null,
    'title': title,
    'note': '',
    'category': '',
    'is_completed': false,
    'due_at': null,
    'reminder_option': 'none',
    'reminder_value': null,
    'created_at': '2026-06-05T01:00:00Z',
    'updated_at': '2026-06-05T02:00:00Z',
    'version': 1,
    'deleted_at': null,
    'purge_after': null,
    'created_by_user_id': userId,
    'updated_by_user_id': userId,
    'device_id': deviceId,
    'subtasks': <Object?>[],
  };
}
