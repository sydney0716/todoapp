import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'todo_api_transport.dart';

TodoApiTransport createTodoApiTransport() => WebTodoApiTransport();

class WebTodoApiTransport implements TodoApiTransport {
  WebTodoApiTransport({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 30),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Duration requestTimeout;

  @override
  Future<TodoApiResponse> send(TodoApiRequest request) async {
    final abort = Completer<void>();
    final timer = Timer(requestTimeout, abort.complete);
    try {
      final outgoing = http.AbortableRequest(
        request.method,
        request.uri,
        abortTrigger: abort.future,
      )..headers.addAll(request.headers);
      if (request.body != null) outgoing.bodyBytes = utf8.encode(request.body!);
      final streamed = await _client.send(outgoing);
      final bytes = await streamed.stream.toBytes();
      return TodoApiResponse(
        statusCode: streamed.statusCode,
        headers: streamed.headers,
        body: utf8.decode(bytes),
      );
    } on http.RequestAbortedException {
      throw TimeoutException('Server did not respond in time.', requestTimeout);
    } finally {
      timer.cancel();
    }
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
