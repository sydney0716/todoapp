import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../server_api_config.dart';
import 'todo_api_models.dart';
import 'todo_api_transport.dart';

class TodoApiClient {
  TodoApiClient({
    String baseUrl = defaultTodoApiBaseUrl,
    TodoApiTransport? transport,
  })  : baseUrl = normalizeTodoApiBaseUrl(baseUrl),
        _transport = transport ?? IoTodoApiTransport(),
        _ownsTransport = transport == null;

  final String baseUrl;
  final TodoApiTransport _transport;
  final bool _ownsTransport;

  Future<AuthSession> login({
    required String username,
    required String password,
    required String deviceId,
    String deviceName = 'Flutter Todo App',
    String? platform,
  }) async {
    final response = await _sendJson(
      method: 'POST',
      path: '/auth/login',
      body: {
        'username': username,
        'password': password,
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform ?? defaultTargetPlatform.name.toLowerCase(),
      },
    );
    return AuthSession.fromJson(_decodeObject(response.body));
  }

  Future<AuthSession> refresh({
    required String refreshToken,
    required String deviceId,
  }) async {
    final response = await _sendJson(
      method: 'POST',
      path: '/auth/refresh',
      body: {
        'refresh_token': refreshToken,
        'device_id': deviceId,
      },
    );
    return AuthSession.fromJson(_decodeObject(response.body));
  }

  Future<SyncBootstrap> bootstrap({
    required String accessToken,
  }) async {
    final response = await _sendJson(
      method: 'GET',
      path: '/sync/bootstrap',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return SyncBootstrap.fromJson(_decodeObject(response.body));
  }

  Future<SyncPushResult> pushTaskChanges({
    required String accessToken,
    required String deviceId,
    required List<SyncTaskChange> changes,
  }) async {
    final response = await _sendJson(
      method: 'POST',
      path: '/sync/tasks',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: {
        'device_id': deviceId,
        'changes': changes.map((change) => change.toJson()).toList(),
      },
    );
    return SyncPushResult.fromJson(_decodeObject(response.body));
  }

  Future<SyncPullResult> pullTaskChanges({
    required String accessToken,
    String? cursor,
  }) async {
    final path = cursor == null || cursor.isEmpty
        ? '/sync/tasks'
        : '/sync/tasks?cursor=${Uri.encodeQueryComponent(cursor)}';
    final response = await _sendJson(
      method: 'GET',
      path: path,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return SyncPullResult.fromJson(_decodeObject(response.body));
  }

  Future<ConnectionCheckResult> verifyConnection({
    required String username,
    required String password,
    required String deviceId,
  }) async {
    final session = await login(
      username: username,
      password: password,
      deviceId: deviceId,
    );
    final bootstrap = await this.bootstrap(accessToken: session.accessToken);
    return ConnectionCheckResult(session: session, bootstrap: bootstrap);
  }

  void close() {
    if (_ownsTransport) {
      _transport.close();
    }
  }

  Future<TodoApiResponse> _sendJson({
    required String method,
    required String path,
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
  }) async {
    final requestHeaders = {
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      ...headers,
    };
    final response = await _transport.send(
      TodoApiRequest(
        method: method,
        uri: todoApiUri(baseUrl, path),
        headers: requestHeaders,
        body: body == null ? null : jsonEncode(body),
      ),
    );
    if (!response.isSuccess) {
      throw _exceptionFromResponse(response);
    }
    return response;
  }

  TodoApiException _exceptionFromResponse(TodoApiResponse response) {
    var message = 'Request failed';
    try {
      final json = _decodeObject(response.body);
      final detail = json['detail'];
      if (detail is String && detail.isNotEmpty) {
        message = detail;
      }
    } on FormatException {
      if (response.body.trim().isNotEmpty) {
        message = response.body.trim();
      }
    }
    return TodoApiException(
      statusCode: response.statusCode,
      message: message,
    );
  }

  Map<String, Object?> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) return Map<String, Object?>.from(decoded);
    throw const FormatException('Expected JSON object response');
  }
}

Future<ConnectionCheckResult> verifyTodoServerConnection({
  required String baseUrl,
  required String username,
  required String password,
  required String deviceId,
}) async {
  final client = TodoApiClient(baseUrl: baseUrl);
  try {
    return await client.verifyConnection(
      username: username,
      password: password,
      deviceId: deviceId,
    );
  } finally {
    client.close();
  }
}
