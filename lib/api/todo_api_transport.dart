import 'dart:convert';
import 'dart:io';

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

class IoTodoApiTransport implements TodoApiTransport {
  IoTodoApiTransport({HttpClient? client})
      : _client = client ?? HttpClient(),
        _ownsClient = client == null;

  final HttpClient _client;
  final bool _ownsClient;

  @override
  Future<TodoApiResponse> send(TodoApiRequest request) async {
    final httpRequest = await _client.openUrl(request.method, request.uri);
    for (final entry in request.headers.entries) {
      httpRequest.headers.set(entry.key, entry.value);
    }

    final body = request.body;
    if (body != null) {
      final bodyBytes = utf8.encode(body);
      httpRequest.contentLength = bodyBytes.length;
      httpRequest.add(bodyBytes);
    }

    final httpResponse = await httpRequest.close();
    final responseBody = await utf8.decodeStream(httpResponse);
    final headers = <String, String>{};
    httpResponse.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });

    return TodoApiResponse(
      statusCode: httpResponse.statusCode,
      headers: headers,
      body: responseBody,
    );
  }

  @override
  void close() {
    if (_ownsClient) {
      _client.close(force: true);
    }
  }
}
