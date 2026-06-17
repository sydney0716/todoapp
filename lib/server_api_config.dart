const defaultTodoApiBaseUrl = 'https://hytodo.duckdns.org';

String normalizeTodoApiBaseUrl(String value) {
  var trimmed = value.trim();
  if (trimmed.isEmpty) return defaultTodoApiBaseUrl;
  if (!trimmed.contains('://')) {
    trimmed = 'https://$trimmed';
  }

  try {
    final uri = Uri.parse(trimmed);
    if (!uri.hasScheme || uri.host.isEmpty) return defaultTodoApiBaseUrl;
    final normalizedPath = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: normalizedPath,
    ).toString();
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
