void initializeBrowserStorage() {}

Future<T?> withBrowserSyncLock<T>(
    String databasePath, Future<T> Function() action) {
  throw UnsupportedError('Browser sync locks are only available on the web.');
}
