package com.example.personaltodo;

import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteException;
import android.view.View;
import android.widget.RemoteViews;
import android.widget.RemoteViewsService;
import android.widget.RemoteViewsService.RemoteViewsFactory;

import java.io.File;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.List;

public class TodoHomeWidgetService extends RemoteViewsService {
    @Override
    public RemoteViewsFactory onGetViewFactory(Intent intent) {
        return new TodoRemoteViewsFactory(getApplicationContext());
    }

    private static final class TodoRemoteViewsFactory implements RemoteViewsFactory {
        private static final String DATABASE_NAME = "personal_todo.db";
        private static final String SETTINGS_DATABASE_NAME = "personal_todo_settings.db";
        private static final String TASK_SORT_OPTION_KEY = "task_sort_option";
        private static final String TASK_SORT_DIRECTION_KEY = "task_sort_direction";
        private static final String SORT_OPTION_TITLE = "title";
        private static final String SORT_OPTION_LAST_MODIFIED = "last_modified";
        private static final String SORT_DIRECTION_DESCENDING = "descending";
        private static final String[] SHORT_MONTH_NAMES = {
                "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
        };
        private static final int MAX_VISIBLE_SUBTASKS = 5;
        private static final int ROW_TYPE_TASK = 0;
        private static final int ROW_TYPE_SUBTASK = 1;
        private static final int ROW_TYPE_MORE = 2;
        private static final int ROW_TYPE_SEPARATOR = 3;
        private static final int ROW_TYPE_COUNT = 4;

        private final Context context;
        private List<WidgetRow> rows = new ArrayList<>();
        private TodoHomeWidgetTheme.Palette palette;

        TodoRemoteViewsFactory(Context context) {
            this.context = context;
            this.palette = TodoHomeWidgetTheme.read(context);
        }

        @Override
        public void onCreate() {
            palette = TodoHomeWidgetTheme.read(context);
            rows = readRows();
        }

        @Override
        public void onDataSetChanged() {
            palette = TodoHomeWidgetTheme.read(context);
            rows = readRows();
        }

        @Override
        public void onDestroy() {
            rows = new ArrayList<>();
        }

        @Override
        public int getCount() {
            return rows.size();
        }

        @Override
        public RemoteViews getViewAt(int position) {
            if (position < 0 || position >= rows.size()) return null;

            WidgetRow row = rows.get(position);
            switch (row.type) {
                case ROW_TYPE_TASK:
                    return taskRow(row);
                case ROW_TYPE_SUBTASK:
                    return subTaskRow(row);
                case ROW_TYPE_MORE:
                    return moreRow(row);
                case ROW_TYPE_SEPARATOR:
                    RemoteViews separator = new RemoteViews(
                            context.getPackageName(),
                            R.layout.todo_home_widget_separator
                    );
                    separator.setInt(
                            R.id.widgetSeparator,
                            "setBackgroundColor",
                            palette.separatorColor
                    );
                    return separator;
                default:
                    return null;
            }
        }

        @Override
        public RemoteViews getLoadingView() {
            return null;
        }

        @Override
        public int getViewTypeCount() {
            return ROW_TYPE_COUNT;
        }

        @Override
        public long getItemId(int position) {
            if (position < 0 || position >= rows.size()) return position;
            return rows.get(position).stableId;
        }

        @Override
        public boolean hasStableIds() {
            return true;
        }

        private RemoteViews taskRow(WidgetRow row) {
            RemoteViews views = new RemoteViews(
                    context.getPackageName(),
                    R.layout.todo_home_widget_task_row
            );
            views.setImageViewResource(
                    R.id.widgetTaskCheckbox,
                    palette.checkboxDrawable
            );
            views.setTextViewText(R.id.widgetTaskTitle, row.title);
            views.setTextColor(R.id.widgetTaskTitle, palette.textColor);
            views.setTextColor(R.id.widgetTaskDueDate, palette.accentColor);
            String dueDateText = formatDueDate(row.dueDateTimeMillis);
            if (dueDateText == null) {
                views.setViewVisibility(R.id.widgetTaskDueDate, View.GONE);
            } else {
                views.setViewVisibility(R.id.widgetTaskDueDate, View.VISIBLE);
                views.setTextViewText(R.id.widgetTaskDueDate, dueDateText);
            }

            Intent fillInIntent = new Intent()
                    .setAction(TodoHomeWidgetProvider.ACTION_MARK_TASK_DONE)
                    .putExtra(TodoHomeWidgetProvider.EXTRA_TASK_ID, row.taskId);
            views.setOnClickFillInIntent(R.id.widgetTaskRow, fillInIntent);
            views.setOnClickFillInIntent(R.id.widgetTaskCheckbox, fillInIntent);
            views.setOnClickFillInIntent(R.id.widgetTaskTitle, fillInIntent);
            views.setOnClickFillInIntent(R.id.widgetTaskDueDate, fillInIntent);
            return views;
        }

        private RemoteViews subTaskRow(WidgetRow row) {
            RemoteViews views = new RemoteViews(
                    context.getPackageName(),
                    R.layout.todo_home_widget_subtask_row
            );
            views.setImageViewResource(
                    R.id.widgetSubTaskCheckbox,
                    palette.checkboxDrawable
            );
            views.setTextViewText(R.id.widgetSubTaskTitle, row.title);
            views.setTextColor(R.id.widgetSubTaskTitle, palette.textColor);
            views.setTextColor(R.id.widgetSubTaskDueDate, palette.accentColor);
            String dueDateText = formatDueDate(row.dueDateTimeMillis);
            if (dueDateText == null) {
                views.setViewVisibility(R.id.widgetSubTaskDueDate, View.GONE);
            } else {
                views.setViewVisibility(R.id.widgetSubTaskDueDate, View.VISIBLE);
                views.setTextViewText(R.id.widgetSubTaskDueDate, dueDateText);
            }

            Intent fillInIntent = new Intent()
                    .setAction(TodoHomeWidgetProvider.ACTION_MARK_SUBTASK_DONE)
                    .putExtra(TodoHomeWidgetProvider.EXTRA_TASK_ID, row.taskId)
                    .putExtra(TodoHomeWidgetProvider.EXTRA_SUBTASK_ID, row.subTaskId);
            views.setOnClickFillInIntent(R.id.widgetSubTaskRow, fillInIntent);
            views.setOnClickFillInIntent(R.id.widgetSubTaskCheckbox, fillInIntent);
            views.setOnClickFillInIntent(R.id.widgetSubTaskTitle, fillInIntent);
            views.setOnClickFillInIntent(R.id.widgetSubTaskDueDate, fillInIntent);
            return views;
        }

        private RemoteViews moreRow(WidgetRow row) {
            RemoteViews views = new RemoteViews(
                    context.getPackageName(),
                    R.layout.todo_home_widget_more_row
            );
            views.setTextViewText(
                    R.id.widgetMoreText,
                    "+ " + row.hiddenCount + " more task ..."
            );
            views.setTextColor(R.id.widgetMoreText, palette.accentColor);
            return views;
        }

        private List<WidgetRow> readRows() {
            File databaseFile = context.getDatabasePath(DATABASE_NAME);
            if (!databaseFile.exists()) return new ArrayList<>();

            SortSettings sortSettings = readSortSettings();
            try (SQLiteDatabase database = SQLiteDatabase.openDatabase(
                    databaseFile.getPath(),
                    null,
                    SQLiteDatabase.OPEN_READONLY
            )) {
                List<TaskItem> tasks = readTasks(database, sortSettings);
                return buildRows(tasks);
            } catch (SQLiteException exception) {
                return new ArrayList<>();
            }
        }

        private SortSettings readSortSettings() {
            File settingsFile = context.getDatabasePath(SETTINGS_DATABASE_NAME);
            if (!settingsFile.exists()) return SortSettings.defaults();

            try (SQLiteDatabase database = SQLiteDatabase.openDatabase(
                    settingsFile.getPath(),
                    null,
                    SQLiteDatabase.OPEN_READONLY
            )) {
                return new SortSettings(
                        readSetting(database, TASK_SORT_OPTION_KEY),
                        readSetting(database, TASK_SORT_DIRECTION_KEY)
                );
            } catch (SQLiteException exception) {
                return SortSettings.defaults();
            }
        }

        private String readSetting(SQLiteDatabase database, String key) {
            try (Cursor cursor = database.rawQuery(
                    "SELECT value FROM settings WHERE key = ? LIMIT 1",
                    new String[]{key}
            )) {
                if (!cursor.moveToFirst()) return null;
                return cursor.getString(0);
            }
        }

        private List<TaskItem> readTasks(SQLiteDatabase database, SortSettings sortSettings) {
            List<TaskItem> tasks = new ArrayList<>();
            boolean hasSubTaskDueDate = hasColumn(database, "subtasks", "dueDateTime");
            try (Cursor cursor = database.rawQuery(
                    "SELECT id, title, dueDateTime FROM tasks "
                            + "WHERE deletedAt IS NULL AND isCompleted = 0 "
                            + "ORDER BY " + sortSettings.orderByClause(),
                    null
            )) {
                while (cursor.moveToNext()) {
                    long taskId = cursor.getLong(0);
                    String title = cursor.getString(1);
                    Long dueDateTimeMillis = cursor.isNull(2) ? null : cursor.getLong(2);
                    tasks.add(new TaskItem(
                            taskId,
                            title,
                            dueDateTimeMillis,
                            readSubTasks(database, taskId, hasSubTaskDueDate)
                    ));
                }
            }
            return tasks;
        }

        private boolean hasColumn(SQLiteDatabase database, String tableName, String columnName) {
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

        private SubTaskPreview readSubTasks(
                SQLiteDatabase database,
                long taskId,
                boolean hasDueDateColumn
        ) {
            List<SubTaskItem> subTasks = new ArrayList<>();
            int totalCount = 0;
            String dueDateColumn = hasDueDateColumn ? "dueDateTime" : "NULL";
            try (Cursor cursor = database.rawQuery(
                    "SELECT id, taskId, title, " + dueDateColumn + " FROM subtasks "
                            + "WHERE taskId = ? AND deletedAt IS NULL AND isCompleted = 0 "
                            + "ORDER BY id ASC",
                    new String[]{String.valueOf(taskId)}
            )) {
                while (cursor.moveToNext()) {
                    totalCount++;
                    if (subTasks.size() >= MAX_VISIBLE_SUBTASKS) continue;

                    subTasks.add(new SubTaskItem(
                            cursor.getLong(0),
                            cursor.getLong(1),
                            cursor.getString(2),
                            cursor.isNull(3) ? null : cursor.getLong(3)
                    ));
                }
            }
            return new SubTaskPreview(subTasks, totalCount - subTasks.size());
        }

        private List<WidgetRow> buildRows(List<TaskItem> tasks) {
            List<WidgetRow> nextRows = new ArrayList<>();
            for (int index = 0; index < tasks.size(); index++) {
                TaskItem task = tasks.get(index);
                nextRows.add(WidgetRow.task(task.id, task.title, task.dueDateTimeMillis));

                for (SubTaskItem subTask : task.subTasks.visibleSubTasks) {
                    nextRows.add(WidgetRow.subTask(
                            subTask.id,
                            subTask.taskId,
                            subTask.title,
                            subTask.dueDateTimeMillis
                    ));
                }

                if (task.subTasks.hiddenCount > 0) {
                    nextRows.add(WidgetRow.more(task.id, task.subTasks.hiddenCount));
                }

                if (index < tasks.size() - 1) {
                    nextRows.add(WidgetRow.separator(task.id));
                }
            }
            return nextRows;
        }

        private String formatDueDate(Long dueDateTimeMillis) {
            if (dueDateTimeMillis == null) return null;

            Calendar dueDate = Calendar.getInstance();
            dueDate.setTimeInMillis(dueDateTimeMillis);
            return SHORT_MONTH_NAMES[dueDate.get(Calendar.MONTH)] + " "
                    + dueDate.get(Calendar.DAY_OF_MONTH);
        }

        private static final class SortSettings {
            final String option;
            final String direction;

            SortSettings(String option, String direction) {
                this.option = option;
                this.direction = direction;
            }

            static SortSettings defaults() {
                return new SortSettings(null, null);
            }

            String orderByClause() {
                boolean descending = SORT_DIRECTION_DESCENDING.equals(direction);
                String selectedDirection = descending ? "DESC" : "ASC";

                if (SORT_OPTION_TITLE.equals(option)) {
                    return "LOWER(title) " + selectedDirection + ", "
                            + "CASE WHEN dueDateTime IS NULL THEN 1 ELSE 0 END ASC, "
                            + "dueDateTime ASC, id ASC";
                }

                if (SORT_OPTION_LAST_MODIFIED.equals(option)) {
                    return "updatedAt " + selectedDirection + ", "
                            + "CASE WHEN dueDateTime IS NULL THEN 1 ELSE 0 END ASC, "
                            + "dueDateTime ASC, id ASC";
                }

                return "CASE WHEN dueDateTime IS NULL THEN 1 ELSE 0 END ASC, "
                        + "dueDateTime " + selectedDirection + ", "
                        + "LOWER(title) ASC, updatedAt DESC, id ASC";
            }
        }
    }

    private static final class TaskItem {
        final long id;
        final String title;
        final Long dueDateTimeMillis;
        final SubTaskPreview subTasks;

        TaskItem(
                long id,
                String title,
                Long dueDateTimeMillis,
                SubTaskPreview subTasks
        ) {
            this.id = id;
            this.title = title;
            this.dueDateTimeMillis = dueDateTimeMillis;
            this.subTasks = subTasks;
        }
    }

    private static final class SubTaskPreview {
        final List<SubTaskItem> visibleSubTasks;
        final int hiddenCount;

        SubTaskPreview(List<SubTaskItem> visibleSubTasks, int hiddenCount) {
            this.visibleSubTasks = visibleSubTasks;
            this.hiddenCount = hiddenCount;
        }
    }

    private static final class SubTaskItem {
        final long id;
        final long taskId;
        final String title;
        final Long dueDateTimeMillis;

        SubTaskItem(long id, long taskId, String title, Long dueDateTimeMillis) {
            this.id = id;
            this.taskId = taskId;
            this.title = title;
            this.dueDateTimeMillis = dueDateTimeMillis;
        }
    }

    private static final class WidgetRow {
        final int type;
        final long stableId;
        final long taskId;
        final long subTaskId;
        final int hiddenCount;
        final String title;
        final Long dueDateTimeMillis;

        private WidgetRow(
                int type,
                long stableId,
                long taskId,
                long subTaskId,
                int hiddenCount,
                String title,
                Long dueDateTimeMillis
        ) {
            this.type = type;
            this.stableId = stableId;
            this.taskId = taskId;
            this.subTaskId = subTaskId;
            this.hiddenCount = hiddenCount;
            this.title = title;
            this.dueDateTimeMillis = dueDateTimeMillis;
        }

        static WidgetRow task(long taskId, String title, Long dueDateTimeMillis) {
            return new WidgetRow(0, taskId * 10L, taskId, 0, 0, title, dueDateTimeMillis);
        }

        static WidgetRow subTask(
                long subTaskId,
                long taskId,
                String title,
                Long dueDateTimeMillis
        ) {
            return new WidgetRow(
                    1,
                    subTaskId * 10L + 1L,
                    taskId,
                    subTaskId,
                    0,
                    title,
                    dueDateTimeMillis
            );
        }

        static WidgetRow more(long taskId, int hiddenCount) {
            return new WidgetRow(2, taskId * 10L + 2L, taskId, 0, hiddenCount, "", null);
        }

        static WidgetRow separator(long taskId) {
            return new WidgetRow(3, taskId * 10L + 3L, taskId, 0, 0, "", null);
        }
    }
}
