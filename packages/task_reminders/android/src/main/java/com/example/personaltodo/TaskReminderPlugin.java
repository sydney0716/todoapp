package com.example.personaltodo;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;

import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodChannel;

/** Available in the app engine and WorkManager's headless engines. */
public final class TaskReminderPlugin implements FlutterPlugin, ActivityAware {
    private Context context;
    private Activity activity;
    private MethodChannel channel;
    private boolean requestedPermission;

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(),
                "com.example.personaltodo/task_notifications");
        channel.setMethodCallHandler((call, result) -> {
            if ("getScheduledTaskReminderIds".equals(call.method)) {
                result.success(TaskReminderStore.ids(context));
                return;
            }
            if (!"scheduleTaskReminder".equals(call.method)
                    && !"cancelTaskReminder".equals(call.method)) {
                result.notImplemented();
                return;
            }
            Map<?, ?> args = call.arguments();
            if (args == null || !(args.get("notificationId") instanceof Number)) {
                result.error("invalid_arguments", "Missing reminder ID.", null);
                return;
            }
            int id = ((Number) args.get("notificationId")).intValue();
            try {
                if ("cancelTaskReminder".equals(call.method)) {
                    TaskReminderStore.cancel(context, id);
                    result.success(null);
                    return;
                }
                if (Build.VERSION.SDK_INT >= 33
                        && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                        != PackageManager.PERMISSION_GRANTED) {
                    // Background work must never display a permission prompt.
                    if (activity != null && !requestedPermission) {
                        requestedPermission = true;
                        activity.requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 9402);
                    }
                    result.error("notifications_denied", "Enable notifications for Personal Todo in system settings.", null);
                    return;
                }
                if (!(args.get("triggerAtMillis") instanceof Number)) {
                    result.error("invalid_arguments", "Missing reminder time.", null);
                    return;
                }
                boolean exact = TaskReminderStore.schedule(context, id,
                        ((Number) args.get("triggerAtMillis")).longValue(),
                        String.valueOf(args.get("title")), String.valueOf(args.get("body")));
                if (exact) result.success(null);
                else result.error("inexact_reminder", "Reminders may be delayed. Enable Alarms & reminders for Personal Todo in system settings.", null);
            } catch (Exception error) {
                result.error("notification_failed", error.getMessage(), null);
            }
        });
    }

    @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        context = null;
    }
    @Override public void onAttachedToActivity(ActivityPluginBinding binding) { activity = binding.getActivity(); }
    @Override public void onDetachedFromActivityForConfigChanges() { activity = null; }
    @Override public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) { activity = binding.getActivity(); }
    @Override public void onDetachedFromActivity() { activity = null; }
}
