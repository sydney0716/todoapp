package com.example.personaltodo;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteException;
import android.widget.RemoteViews;

import java.io.File;
import java.util.LinkedHashSet;
import java.util.Set;

import org.json.JSONArray;
import org.json.JSONException;

public class TodoHomeWidgetProvider extends AppWidgetProvider {
    private static final String DATABASE_NAME = "personal_todo.db";
    private static final String SETTINGS_DATABASE_NAME = "personal_todo_settings.db";
    private static final String CURRENT_USER_ID_KEY = "current_user_id";
    private static final String DEFAULT_CURRENT_USER_ID =
            "00000000-0000-4000-8000-000000000001";
    private static final String PARTNER_USER_ID =
            "00000000-0000-4000-8000-000000000002";
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
            markTaskDone(context, intent.getLongExtra(EXTRA_TASK_ID, 0));
            refreshTaskList(context);
            return;
        }
        if (ACTION_MARK_SUBTASK_DONE.equals(action)) {
            markSubTaskDone(
                    context,
                    intent.getLongExtra(EXTRA_TASK_ID, 0),
                    intent.getLongExtra(EXTRA_SUBTASK_ID, 0)
            );
            refreshTaskList(context);
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

    static void refreshTaskList(Context context) {
        AppWidgetManager appWidgetManager = AppWidgetManager.getInstance(context);
        int[] appWidgetIds = appWidgetManager.getAppWidgetIds(
                new ComponentName(context, TodoHomeWidgetProvider.class)
        );
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
                PendingIntent.getBroadcast(
                        context,
                        0,
                        new Intent(context, TodoHomeWidgetProvider.class),
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

    private static void markTaskDone(Context context, long taskId) {
        if (taskId <= 0) return;
        File databaseFile = context.getDatabasePath(DATABASE_NAME);
        if (!databaseFile.exists()) return;

        long now = System.currentTimeMillis();
        String currentUserId = readCurrentUserId(context);
        try (SQLiteDatabase database = SQLiteDatabase.openDatabase(
                databaseFile.getPath(),
                null,
                SQLiteDatabase.OPEN_READWRITE
        )) {
            if (!hasSharedCompletionColumns(database)) {
                database.execSQL(
                        "UPDATE tasks "
                                + "SET isCompleted = 1, updatedAt = ?, "
                                + "syncStatus = 'pending', version = COALESCE(version, 1) + 1 "
                                + "WHERE id = ? AND deletedAt IS NULL AND isCompleted = 0",
                        new Object[]{now, taskId}
                );
                return;
            }

            try (Cursor cursor = database.rawQuery(
                    "SELECT visibility, sharedCompletionMode, completedByUserIds, isCompleted "
                            + "FROM tasks WHERE id = ? AND deletedAt IS NULL LIMIT 1",
                    new String[]{String.valueOf(taskId)}
            )) {
                if (!cursor.moveToFirst()) return;

                String visibility = cursor.getString(0);
                String sharedCompletionMode = cursor.getString(1);
                String completedByUserIdsJson = cursor.getString(2);
                boolean isCompleted = cursor.getInt(3) == 1;
                boolean requiresBothSharedCompletion =
                        "shared".equals(visibility) && "both".equals(sharedCompletionMode);

                if (requiresBothSharedCompletion) {
                    Set<String> completedByUserIds =
                            completedByUserIdsFromJson(completedByUserIdsJson);
                    if (completedByUserIds.contains(currentUserId)) return;

                    completedByUserIds.add(currentUserId);
                    boolean isFullyCompleted =
                            completedByUserIds.contains(DEFAULT_CURRENT_USER_ID)
                                    && completedByUserIds.contains(PARTNER_USER_ID);
                    database.execSQL(
                            "UPDATE tasks "
                                    + "SET isCompleted = ?, completedByUserIds = ?, "
                                    + "updatedAt = ?, syncStatus = 'pending', "
                                    + "version = COALESCE(version, 1) + 1 "
                                    + "WHERE id = ? AND deletedAt IS NULL",
                            new Object[]{
                                    isFullyCompleted ? 1 : 0,
                                    completedByUserIdsJson(completedByUserIds),
                                    now,
                                    taskId
                            }
                    );
                    return;
                }

                if (isCompleted) return;
                database.execSQL(
                        "UPDATE tasks "
                                + "SET isCompleted = 1, completedByUserIds = ?, "
                                + "updatedAt = ?, syncStatus = 'pending', "
                                + "version = COALESCE(version, 1) + 1 "
                                + "WHERE id = ? AND deletedAt IS NULL AND isCompleted = 0",
                        new Object[]{
                                "shared".equals(visibility)
                                        ? completedByUserIdsJson(singleCompletedByUserId(currentUserId))
                                        : "[]",
                                now,
                                taskId
                        }
                );
            }
        } catch (SQLiteException ignored) {
        }
    }

    private static boolean hasSharedCompletionColumns(SQLiteDatabase database) {
        return hasColumn(database, "tasks", "visibility")
                && hasColumn(database, "tasks", "sharedCompletionMode")
                && hasColumn(database, "tasks", "completedByUserIds");
    }

    private static boolean hasColumn(
            SQLiteDatabase database,
            String tableName,
            String columnName
    ) {
        try (Cursor cursor = database.rawQuery(
                "PRAGMA table_info(" + tableName + ")",
                null
        )) {
            while (cursor.moveToNext()) {
                if (columnName.equals(cursor.getString(1))) return true;
            }
        }
        return false;
    }

    private static String readCurrentUserId(Context context) {
        File settingsFile = context.getDatabasePath(SETTINGS_DATABASE_NAME);
        if (!settingsFile.exists()) return DEFAULT_CURRENT_USER_ID;

        try (SQLiteDatabase database = SQLiteDatabase.openDatabase(
                settingsFile.getPath(),
                null,
                SQLiteDatabase.OPEN_READONLY
        )) {
            try (Cursor cursor = database.rawQuery(
                    "SELECT value FROM settings WHERE key = ? LIMIT 1",
                    new String[]{CURRENT_USER_ID_KEY}
            )) {
                if (!cursor.moveToFirst()) return DEFAULT_CURRENT_USER_ID;
                return normalizeAppUserId(cursor.getString(0));
            }
        } catch (SQLiteException ignored) {
            return DEFAULT_CURRENT_USER_ID;
        }
    }

    private static String normalizeAppUserId(String value) {
        if (PARTNER_USER_ID.equals(value)
                || "partner".equals(value)
                || "partner".equals(value)) {
            return PARTNER_USER_ID;
        }
        if (DEFAULT_CURRENT_USER_ID.equals(value) || "user".equals(value)) {
            return DEFAULT_CURRENT_USER_ID;
        }
        return DEFAULT_CURRENT_USER_ID;
    }

    private static Set<String> singleCompletedByUserId(String userId) {
        Set<String> ids = new LinkedHashSet<>();
        ids.add(userId);
        return ids;
    }

    private static Set<String> completedByUserIdsFromJson(String value) {
        Set<String> ids = new LinkedHashSet<>();
        if (value == null || value.isEmpty()) return ids;

        try {
            JSONArray json = new JSONArray(value);
            for (int index = 0; index < json.length(); index++) {
                String id = normalizeAppUserId(json.optString(index));
                if (!id.isEmpty()) ids.add(id);
            }
        } catch (JSONException ignored) {
        }
        return ids;
    }

    private static String completedByUserIdsJson(Set<String> userIds) {
        JSONArray json = new JSONArray();
        if (userIds.contains(DEFAULT_CURRENT_USER_ID)) {
            json.put(DEFAULT_CURRENT_USER_ID);
        }
        if (userIds.contains(PARTNER_USER_ID)) {
            json.put(PARTNER_USER_ID);
        }
        return json.toString();
    }

    private static void markSubTaskDone(Context context, long taskId, long subTaskId) {
        if (taskId <= 0 || subTaskId <= 0) return;
        File databaseFile = context.getDatabasePath(DATABASE_NAME);
        if (!databaseFile.exists()) return;

        long now = System.currentTimeMillis();
        try (SQLiteDatabase database = SQLiteDatabase.openDatabase(
                databaseFile.getPath(),
                null,
                SQLiteDatabase.OPEN_READWRITE
        )) {
            database.beginTransaction();
            try {
                database.execSQL(
                        "UPDATE subtasks "
                                + "SET isCompleted = 1, updatedAt = ?, "
                                + "syncStatus = 'pending', version = COALESCE(version, 1) + 1 "
                                + "WHERE id = ? AND taskId = ? AND deletedAt IS NULL "
                                + "AND isCompleted = 0",
                        new Object[]{now, subTaskId, taskId}
                );
                database.execSQL(
                        "UPDATE tasks "
                                + "SET updatedAt = ?, syncStatus = 'pending', "
                                + "version = COALESCE(version, 1) + 1 "
                                + "WHERE id = ? AND deletedAt IS NULL",
                        new Object[]{now, taskId}
                );
                database.setTransactionSuccessful();
            } finally {
                database.endTransaction();
            }
        } catch (SQLiteException ignored) {
        }
    }
}
