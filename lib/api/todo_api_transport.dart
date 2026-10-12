import 'todo_api_transport_io.dart'
    if (dart.library.js_interop) 'todo_api_transport_web.dart' as platform;

export 'todo_api_transport_io.dart'
    if (dart.library.js_interop) 'todo_api_transport_web.dart'
    hide createTodoApiTransport;

TodoApiTransport createTodoApiTransport() => platform.createTodoApiTransport();

class TodoApiRequest {
  const TodoApiRequest({
    required this.method,
    required this.uri,
    this.headers = const {},
    this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
}

class TodoApiResponse {
  const TodoApiResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

abstract class TodoApiTransport {
  Future<TodoApiResponse> send(TodoApiRequest request);

  void close() {}
}
