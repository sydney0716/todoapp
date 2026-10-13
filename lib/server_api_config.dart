import 'package:flutter/foundation.dart';

const defaultTodoApiBaseUrl = String.fromEnvironment('TODO_API_BASE_URL',
    defaultValue: 'https://todo.example.com');
const previousTodoApiBaseUrl =
    String.fromEnvironment('TODO_PREVIOUS_API_BASE_URL');

String get initialTodoApiBaseUrl =>
    kIsWeb && !const bool.hasEnvironment('TODO_API_BASE_URL')
        ? Uri.base.origin
        : defaultTodoApiBaseUrl;

String validateTodoApiBaseUrl(String value) {
  var candidate = value.trim();
  if (!candidate.contains('://')) candidate = 'https://$candidate';
  final uri = Uri.parse(candidate);
  if ((uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException(
        'Enter an HTTP or HTTPS server address without credentials, query, or fragment.');
  }
  return uri
      .replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''))
      .toString();
}

String normalizeTodoApiBaseUrl(String value) {
  try {
    return validateTodoApiBaseUrl(value);
  } on FormatException {
    return defaultTodoApiBaseUrl;
  }
}

Uri todoApiUri(String baseUrl, String path) {
  final normalized = normalizeTodoApiBaseUrl(baseUrl);
  final baseUri = Uri.parse('$normalized/');
  final relativePath = path.startsWith('/') ? path.substring(1) : path;
  return baseUri.resolve(relativePath);
}
