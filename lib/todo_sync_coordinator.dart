import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_todo_repository.dart';
import 'settings_controller.dart';
import 'todo_sync_service.dart';

/// One scheduler for edits, retries, foreground pulls, and explicit refreshes.
class TodoSyncCoordinator extends ChangeNotifier {
  TodoSyncCoordinator({
    required this.repository,
    required this.settings,
    required this._runner,
    this.connectivityChanges,
    this.pollInterval = const Duration(seconds: 30),
    this.backgroundPollInterval,
    this.editDelay = const Duration(seconds: 2),
  });

  final LocalTodoRepository repository;
  final SettingsController settings;
  final Stream<bool>? connectivityChanges;
  final Future<TodoSyncResult> Function(bool) _runner;
  final Duration pollInterval;
  final Duration? backgroundPollInterval;
  final Duration editDelay;
  Timer? _poll;
  Timer? _scheduled;
  StreamSubscription<bool>? _connectivitySubscription;
  Future<TodoSyncResult>? _inFlight;
  bool _foreground = true;
  bool _disposed = false;
  bool _again = false;
  bool _snapshot = false;
  String _queueSignature = '';
  String _sessionSignature = '';
  int _scheduleGeneration = 0;
  String? lastError;
  bool get isSyncing => _inFlight != null;
  bool get _canRunAutomatically =>
      _foreground || backgroundPollInterval != null;
  Future<void> waitUntilIdle() async {
    try {
      await _inFlight;
    } on Object {
      /* Recovery may follow a failed sync. */
    }
  }

  bool get canSync =>
      settings.refreshToken.isNotEmpty &&
      (settings.authDeviceId.isEmpty ||
          settings.authDeviceId == repository.deviceId);

  void start() {
    repository.addListener(_queueChanged);
    settings.addListener(_sessionChanged);
    _sessionSignature = _sessionKey;
    _connectivitySubscription = connectivityChanges?.distinct().listen(
      (connected) {
        if (connected) unawaited(retryNow());
      },
      onError: (Object _) {
        // Connectivity is only a hint; normal requests and retries still run.
      },
    );
    _startPolling();
    _schedule(const Duration(milliseconds: 600));
  }

  String get _sessionKey =>
      '${settings.apiBaseUrl}|${settings.refreshToken}|${settings.authDeviceId}';

  void _sessionChanged() {
    if (_sessionKey == _sessionSignature) return;
    _sessionSignature = _sessionKey;
    _schedule(Duration.zero);
  }

  void _queueChanged() => unawaited(_scheduleQueue());

  Future<void> _scheduleQueue() async {
    final generation = ++_scheduleGeneration;
    final queue = await repository.getPendingSyncQueue(entityTypes: {'task'});
    if (_disposed || generation != _scheduleGeneration) return;
    final signature = queue
        .map(
          (item) => '${item.id}:${item.nextAttemptAt.millisecondsSinceEpoch}',
        )
        .join(',');
    if (signature == _queueSignature) return;
    _queueSignature = signature;
    _scheduled?.cancel();
    if (queue.isEmpty || !canSync || !_canRunAutomatically) return;
    final nextAttempt = queue
        .map((item) => item.nextAttemptAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final delay = nextAttempt.difference(DateTime.now());
    _schedule(delay > Duration.zero ? delay : editDelay);
  }

  void _schedule(Duration delay) {
    _scheduled?.cancel();
    if (_disposed || !_canRunAutomatically || !canSync) return;
    _scheduled = Timer(delay, () => unawaited(_automaticSync()));
  }

  void _startPolling() {
    _poll?.cancel();
    final interval = _foreground ? pollInterval : backgroundPollInterval;
    if (interval != null) {
      _poll = Timer.periodic(interval, (_) => unawaited(_automaticSync()));
    }
  }

  void setForeground(bool value) {
    _foreground = value;
    _scheduled?.cancel();
    _startPolling();
    if (value) unawaited(retryNow());
    if (!value && backgroundPollInterval != null) {
      _queueSignature = '';
      unawaited(_scheduleQueue());
    }
  }

  Future<void> retryNow() async {
    if (_disposed || !_canRunAutomatically || !canSync) return;
    try {
      if (!_foreground &&
          (await repository.getPendingSyncQueue(
            entityTypes: {'task'},
          )).isEmpty) {
        return;
      }
      await repository.retryFailedSyncQueueNow();
      if (_disposed || !_canRunAutomatically || !canSync) return;
      await syncNow();
    } on Object {
      // The durable queue and scheduled retries remain available after failure.
    }
  }

  Future<void> finishPendingChanges() async {
    if (_disposed || !canSync) return;
    try {
      final pending = await repository.getPendingSyncQueue(
        now: DateTime.now(),
        entityTypes: {'task'},
      );
      if (_disposed) return;
      if (pending.isNotEmpty) {
        await syncNow();
      } else {
        await waitUntilIdle();
      }
    } on Object {
      // Leaving the app must not lose changes if the OS suspends the upload.
    }
  }

  Future<void> _automaticSync() async {
    if (_disposed || !_canRunAutomatically || !canSync || isSyncing) return;
    try {
      await syncNow();
    } on Object {
      // lastError remains observable; the next foreground poll retries I/O.
    }
  }

  Future<TodoSyncResult> syncNow({bool reconcileSnapshot = false}) {
    _scheduled?.cancel();
    _snapshot = _snapshot || reconcileSnapshot;
    _again = true;
    final active = _inFlight;
    if (active != null) return active;
    final sync = _run();
    _inFlight = sync;
    notifyListeners();
    return sync;
  }

  Future<TodoSyncResult> _run() async {
    try {
      late TodoSyncResult result;
      do {
        _again = false;
        final snapshot = _snapshot;
        _snapshot = false;
        result = await _runner(snapshot);
        lastError = result.failedCount > 0
            ? 'Some changes are waiting to retry.'
            : null;
      } while (_again && !_disposed && canSync);
      return result;
    } on Object catch (error) {
      lastError = error.toString();
      rethrow;
    } finally {
      _inFlight = null;
      if (!_disposed) {
        notifyListeners();
        _queueSignature = '';
        await _scheduleQueue();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _scheduled?.cancel();
    unawaited(_connectivitySubscription?.cancel());
    repository.removeListener(_queueChanged);
    settings.removeListener(_sessionChanged);
    super.dispose();
  }
}
