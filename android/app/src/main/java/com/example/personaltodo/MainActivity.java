package com.example.personaltodo;

import android.Manifest;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String SETTINGS_MIGRATION_CHANNEL =
            "com.example.personaltodo/settings_migration";
    private static final String WIDGET_ACTIONS_CHANNEL =
            "com.example.personaltodo/widget_actions";
    private static final String TASK_NOTIFICATIONS_CHANNEL =
            "com.example.personaltodo/task_notifications";
    private static final int NOTIFICATION_PERMISSION_REQUEST_CODE = 9402;
    private static final String ACTION_OPEN_NEW_TASK =
            "com.example.personaltodo.widget.OPEN_NEW_TASK";
    private static final String ACTION_WIDGET_ACTION =
            "com.example.personaltodo.widget.ACTION";
    private static final String FLUTTER_ACTION_OPEN_NEW_TASK = "open_new_task";
    static final String FLUTTER_ACTION_COMPLETE_TASK = "complete_task";
    static final String FLUTTER_ACTION_TOGGLE_TASK = "toggle_task_completion";
    static final String FLUTTER_ACTION_COMPLETE_SUBTASK = "complete_subtask";
    private static final String EXTRA_FLUTTER_ACTION = "flutter_action";
    private static final String EXTRA_TASK_ID = "taskId";
    private static final String EXTRA_SUBTASK_ID = "subTaskId";
    private static final String LEGACY_PREFERENCES = "personal_todo_preferences";
    private static final String FLUTTER_PREFERENCES = "FlutterSharedPreferences";
    private static final String FLUTTER_PREFERENCE_PREFIX = "flutter.";
    private static final String KEY_SHOW_COMPLETED_TASKS = "show_completed_tasks";
    private static final String KEY_THEME_MODE = "theme_mode";
    private static final String KEY_TIME_FORMAT = "time_format";
    private MethodChannel widgetActionsChannel;
    private boolean requestedNotificationPermission;
    private final List<Map<String, Object>> pendingWidgetActions = new ArrayList<>();

    static Intent newTaskIntent(Context context) {
        return new Intent(context, MainActivity.class)
                .setAction(ACTION_OPEN_NEW_TASK)
                .setFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK
                                | Intent.FLAG_ACTIVITY_CLEAR_TOP
                                | Intent.FLAG_ACTIVITY_SINGLE_TOP
                );
    }

    static Intent openAppIntent(Context context) {
        return new Intent(context, MainActivity.class)
                .setFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK
                                | Intent.FLAG_ACTIVITY_CLEAR_TOP
                                | Intent.FLAG_ACTIVITY_SINGLE_TOP
                );
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        captureWidgetAction(getIntent());

        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                SETTINGS_MIGRATION_CHANNEL
        ).setMethodCallHandler((call, result) -> {
            if ("readLegacySettings".equals(call.method)) {
                result.success(readLegacySettings());
            } else {
                result.notImplemented();
            }
        });

        widgetActionsChannel = new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                WIDGET_ACTIONS_CHANNEL
        );
        widgetActionsChannel.setMethodCallHandler((call, result) -> {
            if ("consumeInitialAction".equals(call.method)) {
                Map<String, Object> action = consumeNextPendingWidgetAction();
                result.success(action);
            } else if ("consumePendingWidgetActions".equals(call.method)) {
                result.success(consumePendingWidgetActions());
            } else {
                result.notImplemented();
            }
        });

        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                TASK_NOTIFICATIONS_CHANNEL
        ).setMethodCallHandler((call, result) -> {
            if ("scheduleTaskReminder".equals(call.method)) {
                Map<?, ?> arguments = call.arguments();
                if (arguments == null) {
                    result.error("invalid_arguments", "Missing notification arguments.", null);
                    return;
                }
                requestNotificationPermissionIfNeeded();
                if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    result.error("notifications_denied", "Enable notifications for Personal Todo in system settings.", null);
                    return;
                }
                try {
                    boolean exact = TaskReminderStore.schedule(this, intArgument(arguments, "notificationId"),
                            longArgument(arguments, "triggerAtMillis"), stringArgument(arguments, "title"), stringArgument(arguments, "body"));
                    if (exact) result.success(null);
                    else result.error("inexact_reminder", "Reminders may be delayed. Enable Alarms & reminders for Personal Todo in system settings.", null);
                } catch (Exception error) { result.error("notification_failed", error.getMessage(), null); }
            } else if ("cancelTaskReminder".equals(call.method)) {
                Map<?, ?> arguments = call.arguments();
                if (arguments == null) {
                    result.error("invalid_arguments", "Missing notification arguments.", null);
                    return;
                }
                TaskReminderStore.cancel(this, intArgument(arguments, "notificationId"));
                result.success(null);
            } else if ("getScheduledTaskReminderIds".equals(call.method)) {
                result.success(TaskReminderStore.ids(this));
            } else {
                result.notImplemented();
            }
        });
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        Map<String, Object> action = widgetActionFromIntent(intent);
        if (action == null) return;

        if (widgetActionsChannel == null) {
            pendingWidgetActions.add(action);
            return;
        }

        widgetActionsChannel.invokeMethod("widgetAction", action);
    }

    @Override
    protected void onPause() {
        super.onPause();
        TodoHomeWidgetProvider.updateWidgets(this);
    }

    private Map<String, Object> readLegacySettings() {
        Map<String, Object> settings = new HashMap<>();
        copySettingsFromPreferences(
                settings,
                getSharedPreferences(LEGACY_PREFERENCES, Context.MODE_PRIVATE),
                ""
        );
        copySettingsFromPreferences(
                settings,
                getSharedPreferences(FLUTTER_PREFERENCES, Context.MODE_PRIVATE),
                FLUTTER_PREFERENCE_PREFIX
        );

        return settings;
    }

    private void captureWidgetAction(Intent intent) {
        Map<String, Object> action = widgetActionFromIntent(intent);
        if (action != null) {
            pendingWidgetActions.add(action);
        }
    }

    private Map<String, Object> widgetActionFromIntent(Intent intent) {
        if (intent == null) return null;
        if (ACTION_OPEN_NEW_TASK.equals(intent.getAction())) {
            return widgetAction(FLUTTER_ACTION_OPEN_NEW_TASK, intent);
        }
        if (ACTION_WIDGET_ACTION.equals(intent.getAction())) {
            String flutterAction = intent.getStringExtra(EXTRA_FLUTTER_ACTION);
            if (flutterAction == null || flutterAction.isEmpty()) return null;
            return widgetAction(flutterAction, intent);
        }
        return null;
    }

    private Map<String, Object> widgetAction(String type, Intent intent) {
        Map<String, Object> action = new HashMap<>();
        action.put("type", type);
        String actionId = intent.getStringExtra("widgetActionId");
        if (actionId == null) {
            actionId = UUID.randomUUID().toString();
            intent.putExtra("widgetActionId", actionId);
        }
        action.put("id", actionId);
        long taskId = intent.getLongExtra(EXTRA_TASK_ID, 0);
        long subTaskId = intent.getLongExtra(EXTRA_SUBTASK_ID, 0);
        if (taskId > 0) {
            action.put("taskId", taskId);
        }
        if (subTaskId > 0) {
            action.put("subTaskId", subTaskId);
        }
        return action;
    }

    private Map<String, Object> consumeNextPendingWidgetAction() {
        if (pendingWidgetActions.isEmpty()) return null;
        return pendingWidgetActions.remove(0);
    }

    private List<Map<String, Object>> consumePendingWidgetActions() {
        List<Map<String, Object>> actions = new ArrayList<>(pendingWidgetActions);
        pendingWidgetActions.clear();
        return actions;
    }

    private void requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < 33 || requestedNotificationPermission) return;
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                == PackageManager.PERMISSION_GRANTED) {
            return;
        }
        requestedNotificationPermission = true;
        requestPermissions(
                new String[]{Manifest.permission.POST_NOTIFICATIONS},
                NOTIFICATION_PERMISSION_REQUEST_CODE
        );
    }

    private int intArgument(Map<?, ?> arguments, String key) {
        Object value = arguments.get(key);
        if (value instanceof Number) return ((Number) value).intValue();
        if (value instanceof String) {
            try {
                return Integer.parseInt((String) value);
            } catch (NumberFormatException ignored) {
            }
        }
        return 0;
    }

    private long longArgument(Map<?, ?> arguments, String key) {
        Object value = arguments.get(key);
        if (value instanceof Number) return ((Number) value).longValue();
        if (value instanceof String) {
            try {
                return Long.parseLong((String) value);
            } catch (NumberFormatException ignored) {
            }
        }
        return 0L;
    }

    private String stringArgument(Map<?, ?> arguments, String key) {
        Object value = arguments.get(key);
        return value == null ? "" : value.toString();
    }

    private void copySettingsFromPreferences(
            Map<String, Object> settings,
            SharedPreferences preferences,
            String keyPrefix
    ) {
        Map<String, ?> values = preferences.getAll();

        copyBooleanSetting(settings, values, keyPrefix, KEY_SHOW_COMPLETED_TASKS);
        copyStringSetting(settings, values, keyPrefix, KEY_THEME_MODE);
        copyStringSetting(settings, values, keyPrefix, KEY_TIME_FORMAT);
    }

    private void copyBooleanSetting(
            Map<String, Object> settings,
            Map<String, ?> values,
            String keyPrefix,
            String key
    ) {
        if (settings.containsKey(key)) return;

        Object value = values.get(keyPrefix + key);
        if (value instanceof Boolean) {
            settings.put(key, value);
        }
    }

    private void copyStringSetting(
            Map<String, Object> settings,
            Map<String, ?> values,
            String keyPrefix,
            String key
    ) {
        if (settings.containsKey(key)) return;

        Object value = values.get(keyPrefix + key);
        if (value instanceof String) {
            settings.put(key, value);
        }
    }

}
