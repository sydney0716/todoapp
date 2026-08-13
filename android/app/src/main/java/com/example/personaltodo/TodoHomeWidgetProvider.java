package com.example.personaltodo;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.widget.RemoteViews;

public class TodoHomeWidgetProvider extends AppWidgetProvider {
    static final String ACTION_MARK_TASK_DONE =
            "com.example.personaltodo.widget.MARK_TASK_DONE";
    static final String ACTION_MARK_SUBTASK_DONE =
            "com.example.personaltodo.widget.MARK_SUBTASK_DONE";
    static final String EXTRA_TASK_ID = "task_id";
    static final String EXTRA_SUBTASK_ID = "subtask_id";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (ACTION_MARK_TASK_DONE.equals(action)) {
            launchFlutterWidgetAction(
                    context,
                    MainActivity.FLUTTER_ACTION_COMPLETE_TASK,
                    intent.getLongExtra(EXTRA_TASK_ID, 0),
                    0
            );
            return;
        }
        if (ACTION_MARK_SUBTASK_DONE.equals(action)) {
            launchFlutterWidgetAction(
                    context,
                    MainActivity.FLUTTER_ACTION_COMPLETE_SUBTASK,
                    intent.getLongExtra(EXTRA_TASK_ID, 0),
                    intent.getLongExtra(EXTRA_SUBTASK_ID, 0)
            );
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

        PendingIntent addTaskIntent = PendingIntent.getActivity(
                context,
                0,
                MainActivity.newTaskIntent(context),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
        views.setOnClickPendingIntent(R.id.widgetAddTaskButton, addTaskIntent);
        views.setPendingIntentTemplate(
                R.id.widgetTaskList,
                PendingIntent.getActivity(
                        context,
                        0,
                        MainActivity.widgetActionTemplateIntent(context),
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

    private static void launchFlutterWidgetAction(
            Context context,
            String flutterAction,
            long taskId,
            long subTaskId
    ) {
        if (taskId <= 0) return;
        if (MainActivity.FLUTTER_ACTION_COMPLETE_SUBTASK.equals(flutterAction)
                && subTaskId <= 0) {
            return;
        }
        context.startActivity(MainActivity.widgetActionIntent(
                context,
                flutterAction,
                taskId,
                subTaskId
        ));
    }
}
