import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personaltodo/api/todo_api_transport.dart';

void main() {
  test('a stalled response body times out and releases transport I/O',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<void>();
    server.listen((request) async {
      request.response.write('partial body');
      await request.response.flush();
      received.complete();
      // Keep the response open to exercise the body-read deadline.
    });
    final transport = IoTodoApiTransport(
      requestTimeout: const Duration(milliseconds: 150),
    );
    addTearDown(() async {
      transport.close();
      await server.close(force: true);
    });
    final response = transport.send(TodoApiRequest(
      method: 'GET',
      uri: Uri.parse('http://127.0.0.1:${server.port}/tasks'),
    ));
    await expectLater(response, throwsA(isA<TimeoutException>()));
    expect(received.isCompleted, isTrue);
  });
}
