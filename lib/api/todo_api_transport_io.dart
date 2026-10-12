import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'todo_api_transport.dart';

TodoApiTransport createTodoApiTransport() => IoTodoApiTransport();

class IoTodoApiTransport implements TodoApiTransport {
  IoTodoApiTransport(
      {HttpClient? client, this.requestTimeout = const Duration(seconds: 30)})
      : _client = client ?? HttpClient(),
        _ownsClient = client == null;

  final HttpClient _client;
  final bool _ownsClient;
  final Duration requestTimeout;

  @override
  Future<TodoApiResponse> send(TodoApiRequest request) async {
    HttpClientRequest? activeRequest;
    var expired = false;
    Future<TodoApiResponse> perform() async {
      final httpRequest = await _client.openUrl(request.method, request.uri);
      activeRequest = httpRequest;
      if (expired) {
        httpRequest.abort();
        throw TimeoutException(
            'Request exceeded its deadline.', requestTimeout);
      }
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

    return perform().timeout(requestTimeout, onTimeout: () {
      expired = true;
      activeRequest?.abort();
      if (_ownsClient) _client.close(force: true);
      throw TimeoutException('Server did not respond in time.', requestTimeout);
    });
  }

  @override
  void close() {
    if (_ownsClient) {
      _client.close(force: true);
    }
  }
}
