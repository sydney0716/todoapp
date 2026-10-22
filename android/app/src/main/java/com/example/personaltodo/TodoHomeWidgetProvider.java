package com.example.personaltodo;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.util.Log;
import android.widget.RemoteViews;

import androidx.work.Data;
import androidx.work.ExistingWorkPolicy;
import androidx.work.OneTimeWorkRequest;
import androidx.work.WorkManager;

import dev.fluttercommunity.workmanager.BackgroundWorker;

public class TodoHomeWidgetProvider extends AppWidgetProvider {
    private static final String ACTION_SAVE_COMPLETION =
            "com.example.personaltodo.widget.SAVE_COMPLETION";
    private static final String WIDGET_ACTION_TASK =
            "com.example.personaltodo.widget_action";
    static final String EXTRA_TASK_ID = "task_id";
    static final String EXTRA_SUBTASK_ID = "subtask_id";
    private static final String EXTRA_COMPLETED = "completed";
    private static final String EXTRA_USER_ID = "user_id";
    private static final String EXTRA_CANCEL_REMINDER = "cancel_reminder";
    private static final String EXTRA_NAVIGATE = "navigate";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (ACTION_SAVE_COMPLETION.equals(action)) {
            if (intent.getBooleanExtra(EXTRA_NAVIGATE, false)) {
                long taskId = intent.getLongExtra(EXTRA_TASK_ID, 0);
                context.startActivity(taskId > 0
                        ? MainActivity.openTaskIntent(context, taskId)
                        : MainActivity.openAppIntent(context));
                return;
            }
            saveCompletion(context, intent);
            return;
        }

        super.onReceive(context, intent);
    }

    @Override
    public void onUpdate(
            Context context,
            AppWidgetManager appWidgetManager,
            int[] appWidgetIds
    ) {
        for (int appWidgetId : appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId);
        }
    }

    static void updateWidgets(Context context) {
        AppWidgetManager appWidgetManager = AppWidgetManager.getInstance(context);
        int[] appWidgetIds = appWidgetManager.getAppWidgetIds(
                new ComponentName(context, TodoHomeWidgetProvider.class)
        );

        for (int appWidgetId : appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId);
        }
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.widgetTaskList);
    }

    private static void updateWidget(
            Context context,
            AppWidgetManager appWidgetManager,
            int appWidgetId
    ) {
        TodoHomeWidgetTheme.Palette palette = TodoHomeWidgetTheme.read(context);
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.todo_home_widget);
        applyTheme(views, palette);
        views.setRemoteAdapter(
                R.id.widgetTaskList,
                new Intent(context, TodoHomeWidgetService.class)
        );
        views.setEmptyView(R.id.widgetTaskList, R.id.widgetEmptyText);

        PendingIntent openAppIntent = PendingIntent.getActivity(
                context,
                1,
                MainActivity.openAppIntent(context),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
        views.setOnClickPendingIntent(R.id.widgetHeaderRow, openAppIntent);
        views.setOnClickPendingIntent(R.id.widgetHeaderTitle, openAppIntent);
        views.setOnClickPendingIntent(R.id.widgetRoot, openAppIntent);
        views.setOnClickPendingIntent(R.id.widgetEmptyText, openAppIntent);

        PendingIntent addTaskIntent = PendingIntent.getActivity(
                context,
                0,
                MainActivity.newTaskIntent(context),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
        views.setOnClickPendingIntent(R.id.widgetAddTaskButton, addTaskIntent);
        views.setPendingIntentTemplate(
                R.id.widgetTaskList,
                PendingIntent.getBroadcast(
                        context,
                        0,
                        new Intent(context, TodoHomeWidgetProvider.class)
                                .setAction(ACTION_SAVE_COMPLETION),
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE
                )
        );

        appWidgetManager.updateAppWidget(appWidgetId, views);
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widgetTaskList);
    }

    private static void applyTheme(
            RemoteViews views,
            TodoHomeWidgetTheme.Palette palette
    ) {
        views.setInt(
                R.id.widgetRoot,
                "setBackgroundResource",
                palette.backgroundDrawable
        );
        views.setTextColor(R.id.widgetHeaderTitle, palette.textColor);
        views.setInt(
                R.id.widgetAddTaskButton,
                "setBackgroundResource",
                palette.buttonBackgroundDrawable
        );
        views.setTextColor(R.id.widgetAddTaskButton, palette.buttonTextColor);
        views.setTextColor(R.id.widgetEmptyText, palette.textColor);
    }

    static Intent navigationIntent(long taskId) {
        return new Intent()
                .putExtra(EXTRA_NAVIGATE, true)
                .putExtra(EXTRA_TASK_ID, taskId);
    }

    static Intent completionIntent(long taskId, long subTaskId, boolean completed,
                                   String userId, boolean cancelReminder) {
        return new Intent()
                .putExtra(EXTRA_TASK_ID, taskId)
                .putExtra(EXTRA_SUBTASK_ID, subTaskId)
                .putExtra(EXTRA_COMPLETED, completed)
                .putExtra(EXTRA_USER_ID, userId)
                .putExtra(EXTRA_CANCEL_REMINDER, cancelReminder);
    }

    private void saveCompletion(Context context, Intent intent) {
        long taskId = intent.getLongExtra(EXTRA_TASK_ID, 0);
        long subTaskId = intent.getLongExtra(EXTRA_SUBTASK_ID, 0);
        String userId = intent.getStringExtra(EXTRA_USER_ID);
        boolean completed = intent.getBooleanExtra(EXTRA_COMPLETED, true);
        if (taskId <= 0 || subTaskId < 0 || userId == null) return;
        if (subTaskId > 0 && !completed) return;
        PendingResult pending = goAsync();
        try {
            TodoWidgetActionStore.enqueue(context, taskId, subTaskId, completed, userId);
            updateWidgets(context);
            if (intent.getBooleanExtra(EXTRA_CANCEL_REMINDER, false)) {
                TaskReminderStore.cancel(context, (int) taskId);
            }
            // Use the existing worker: it waits for saving/syncing and then
            // destroys its Flutter engine instead of keeping the app running.
            OneTimeWorkRequest work = new OneTimeWorkRequest.Builder(BackgroundWorker.class)
                    .setInputData(new Data.Builder()
                            .putString(BackgroundWorker.DART_TASK_KEY, WIDGET_ACTION_TASK)
                            .build())
                    .build();
            WorkManager.getInstance(context).enqueueUniqueWork(
                    WIDGET_ACTION_TASK, ExistingWorkPolicy.APPEND_OR_REPLACE, work)
                    .getResult().addListener(pending::finish, Runnable::run);
        } catch (Exception error) {
            // Persisted edits are retried on periodic refresh or app startup.
            Log.e("TodoHomeWidget", "Could not process widget completion", error);
            pending.finish();
        }
    }
}
