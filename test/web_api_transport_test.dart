import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personaltodo/api/todo_api_transport.dart';
import 'package:personaltodo/api/todo_api_transport_web.dart';

void main() {
  test(
    'browser transport preserves UTF-8 bodies, auth headers, and status',
    () async {
      final transport = WebTodoApiTransport(
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer test-access');
          expect(jsonDecode(utf8.decode(request.bodyBytes)), {'title': '할 일'});
          return http.Response.bytes(
            utf8.encode('{"title":"완료"}'),
            409,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final response = await transport.send(
        TodoApiRequest(
          method: 'POST',
          uri: Uri.parse('https://example.invalid/sync/tasks'),
          headers: {'Authorization': 'Bearer test-access'},
          body: jsonEncode({'title': '할 일'}),
        ),
      );
      expect(response.statusCode, 409);
      expect(jsonDecode(response.body), {'title': '완료'});
    },
  );

  test('browser transport deadline aborts a stalled response body', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.write('partial body');
      await request.response.flush();
    });
    final transport = WebTodoApiTransport(
      requestTimeout: const Duration(milliseconds: 150),
    );
    addTearDown(() async {
      transport.close();
      await server.close(force: true);
    });
    await expectLater(
      transport.send(
        TodoApiRequest(
          method: 'GET',
          uri: Uri.parse('http://127.0.0.1:${server.port}/stall'),
        ),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}
