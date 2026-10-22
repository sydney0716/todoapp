package com.example.personaltodo;

import android.app.AlarmManager;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

final class TaskReminderStore {
    private static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences("task_reminders", Context.MODE_PRIVATE);
    }

    static List<Integer> ids(Context context) {
        List<Integer> result = new ArrayList<>();
        for (String key : preferences(context).getAll().keySet()) {
            try { result.add(Integer.parseInt(key)); } catch (NumberFormatException ignored) { }
        }
        return result;
    }

    static boolean schedule(Context context, int id, long triggerAt, String title, String body) {
        if (id <= 0 || triggerAt <= System.currentTimeMillis()) {
            cancel(context, id);
            return true;
        }
        JSONObject reminder = new JSONObject();
        try {
            reminder.put("triggerAt", triggerAt).put("title", title).put("body", body);
        } catch (org.json.JSONException error) { throw new IllegalArgumentException(error); }
        if (!preferences(context).edit().putString(String.valueOf(id), reminder.toString()).commit()) {
            throw new IllegalStateException("Could not save reminder.");
        }
        Intent intent = alarmIntent(context)
                .putExtra("notification_id", id)
                .putExtra("title", title)
                .putExtra("body", body);
        PendingIntent pending = PendingIntent.getBroadcast(context, id, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        AlarmManager manager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (manager == null) throw new IllegalStateException("Alarm service unavailable.");
        boolean exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms();
        if (exact) {
            manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending);
        } else {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending);
        }
        return exact;
    }

    static void cancel(Context context, int id) {
        preferences(context).edit().remove(String.valueOf(id)).commit();
        PendingIntent pending = PendingIntent.getBroadcast(context, id,
                alarmIntent(context),
                PendingIntent.FLAG_NO_CREATE | PendingIntent.FLAG_IMMUTABLE);
        AlarmManager manager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (pending != null) {
            if (manager != null) manager.cancel(pending);
            pending.cancel();
        }
        NotificationManager notifications = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (notifications != null) notifications.cancel(id);
    }

    private static Intent alarmIntent(Context context) {
        // Retain the app's receiver component and alarm IDs across upgrades.
        return new Intent().setClassName(context, context.getPackageName() + ".TaskAlarmReceiver");
    }

    static void restore(Context context) {
        for (int id : ids(context)) {
            try {
                JSONObject reminder = new JSONObject(preferences(context).getString(String.valueOf(id), "{}"));
                schedule(context, id, reminder.getLong("triggerAt"), reminder.optString("title"), reminder.optString("body"));
            } catch (Exception error) { android.util.Log.e("TaskReminderStore", "Could not restore reminder " + id, error); }
        }
    }
}
