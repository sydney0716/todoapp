package com.example.personaltodo;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class TaskReminderBootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        TaskReminderStore.restore(context);
        TodoHomeWidgetProvider.updateWidgets(context);
    }
}
