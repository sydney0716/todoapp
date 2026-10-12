package com.example.personaltodo;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class TaskAlarmReceiver extends BroadcastReceiver {
    static final String EXTRA_NOTIFICATION_ID = "notification_id";
    static final String EXTRA_TITLE = "title";
    static final String EXTRA_BODY = "body";

    private static final String CHANNEL_ID = "task_reminders";
    private static final String CHANNEL_NAME = "Task reminders";

    @Override
    public void onReceive(Context context, Intent intent) {
        int notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, 0);
        if (notificationId <= 0) return;

        String title = intent.getStringExtra(EXTRA_TITLE);
        String body = intent.getStringExtra(EXTRA_BODY);
        if (title == null || title.isEmpty()) title = context.getString(R.string.app_name);
        if (body == null) body = "";

        NotificationManager manager =
                (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager == null) return;

        ensureChannel(manager);

        PendingIntent contentIntent = PendingIntent.getActivity(
                context,
                notificationId,
                MainActivity.openAppIntent(context),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        Notification.Builder builder = new Notification.Builder(context, CHANNEL_ID);

        Notification notification = builder
                .setSmallIcon(R.drawable.ic_stat_task_alarm)
                .setContentTitle(title)
                .setContentText(body)
                .setContentIntent(contentIntent)
                .setAutoCancel(true)
                .setShowWhen(true)
                .build();

        try { manager.notify(notificationId, notification); }
        catch (SecurityException error) { android.util.Log.w("TaskAlarmReceiver", "Notification permission denied", error); }
        // Fired reminders no longer need restoration after reboot.
        context.getSharedPreferences("task_reminders", Context.MODE_PRIVATE).edit().remove(String.valueOf(notificationId)).apply();
    }

    private void ensureChannel(NotificationManager manager) {
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_DEFAULT
        );
        manager.createNotificationChannel(channel);
    }
}
