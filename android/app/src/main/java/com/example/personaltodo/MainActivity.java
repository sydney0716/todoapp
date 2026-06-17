package com.example.personaltodo;

import android.Manifest;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.Map;

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
    private static final String FLUTTER_ACTION_OPEN_NEW_TASK = "open_new_task";
    private static final String LEGACY_PREFERENCES = "personal_todo_preferences";
    private static final String FLUTTER_PREFERENCES = "FlutterSharedPreferences";
    private static final String FLUTTER_PREFERENCE_PREFIX = "flutter.";
    private static final String KEY_SHOW_COMPLETED_TASKS = "show_completed_tasks";
    private static final String KEY_THEME_MODE = "theme_mode";
    private static final String KEY_TIME_FORMAT = "time_format";
    private static final String KEY_STARTER_CONTENT_VERSION = "starter_content_version";
    private MethodChannel widgetActionsChannel;
    private String pendingWidgetAction;

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
                String action = pendingWidgetAction;
                pendingWidgetAction = null;
                result.success(action);
            } else if ("refreshWidget".equals(call.method)) {
                TodoHomeWidgetProvider.updateWidgets(this);
                result.success(null);
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
                scheduleTaskReminder(arguments);
                result.success(null);
            } else if ("cancelTaskReminder".equals(call.method)) {
                Map<?, ?> arguments = call.arguments();
                if (arguments == null) {
                    result.error("invalid_arguments", "Missing notification arguments.", null);
                    return;
                }
                cancelTaskReminder(intArgument(arguments, "notificationId"));
                result.success(null);
            } else {
                result.notImplemented();
            }
        });
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        String action = widgetActionFromIntent(intent);
        if (action == null) return;

        if (widgetActionsChannel == null) {
            pendingWidgetAction = action;
            return;
        }

        widgetActionsChannel.invokeMethod("openNewTask", null);
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
        String action = widgetActionFromIntent(intent);
        if (action != null) {
            pendingWidgetAction = action;
        }
    }

    private String widgetActionFromIntent(Intent intent) {
        if (intent == null) return null;
        if (ACTION_OPEN_NEW_TASK.equals(intent.getAction())) {
            return FLUTTER_ACTION_OPEN_NEW_TASK;
        }
        return null;
    }

    private void scheduleTaskReminder(Map<?, ?> arguments) {
        requestNotificationPermissionIfNeeded();

        int notificationId = intArgument(arguments, "notificationId");
        long triggerAtMillis = longArgument(arguments, "triggerAtMillis");
        if (notificationId <= 0 || triggerAtMillis <= System.currentTimeMillis()) {
            cancelTaskReminder(notificationId);
            return;
        }

        String title = stringArgument(arguments, "title");
        String body = stringArgument(arguments, "body");
        Intent intent = new Intent(this, TaskAlarmReceiver.class)
                .putExtra(TaskAlarmReceiver.EXTRA_NOTIFICATION_ID, notificationId)
                .putExtra(TaskAlarmReceiver.EXTRA_TITLE, title)
                .putExtra(TaskAlarmReceiver.EXTRA_BODY, body);
        PendingIntent pendingIntent = PendingIntent.getBroadcast(
                this,
                notificationId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        AlarmManager alarmManager = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
        if (alarmManager == null) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
            );
        } else {
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent);
        }
    }

    private void cancelTaskReminder(int notificationId) {
        if (notificationId <= 0) return;
        Intent intent = new Intent(this, TaskAlarmReceiver.class);
        PendingIntent pendingIntent = PendingIntent.getBroadcast(
                this,
                notificationId,
                intent,
                PendingIntent.FLAG_NO_CREATE | PendingIntent.FLAG_IMMUTABLE
        );
        if (pendingIntent == null) return;

        AlarmManager alarmManager = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
        if (alarmManager != null) {
            alarmManager.cancel(pendingIntent);
        }
        pendingIntent.cancel();
    }

    private void requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < 33) return;
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                == PackageManager.PERMISSION_GRANTED) {
            return;
        }
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
        copyIntSetting(settings, values, keyPrefix, KEY_STARTER_CONTENT_VERSION);
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

    private void copyIntSetting(
            Map<String, Object> settings,
            Map<String, ?> values,
            String keyPrefix,
            String key
    ) {
        if (settings.containsKey(key)) return;

        Object value = values.get(keyPrefix + key);
        if (value instanceof Number) {
            settings.put(key, ((Number) value).intValue());
        }
    }
}
