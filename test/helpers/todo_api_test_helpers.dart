import 'dart:convert';

import 'package:personaltodo/api/todo_api_transport.dart';

TodoApiResponse jsonResponse(Map<String, Object?> body) {
  return TodoApiResponse(
    statusCode: 200,
    headers: const {'content-type': 'application/json'},
    body: jsonEncode(body),
  );
}

class FakeTodoApiTransport implements TodoApiTransport {
  FakeTodoApiTransport(this._responses);

  final List<TodoApiResponse> _responses;
  final List<TodoApiRequest> requests = [];

  @override
  Future<TodoApiResponse> send(TodoApiRequest request) async {
    requests.add(request);
    return _responses.removeAt(0);
  }

  @override
  void close() {}
}
