package com.example.personaltodo;

import android.content.Context;
import android.content.res.Configuration;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteException;
import android.graphics.Color;

import java.io.File;

final class TodoHomeWidgetTheme {
    private static final String SETTINGS_DATABASE_NAME = "personal_todo_settings.db";
    private static final String THEME_MODE_KEY = "theme_mode";
    private static final String THEME_DARK = "DARK";
    private static final String THEME_FOLLOW_SYSTEM = "FOLLOW_SYSTEM";

    private TodoHomeWidgetTheme() {
    }

    static Palette read(Context context) {
        return paletteFor(context, readThemeMode(context));
    }

    private static Palette paletteFor(Context context, String themeMode) {
        if (shouldUseDark(context, themeMode)) return Palette.dark();
        return Palette.light();
    }

    private static boolean shouldUseDark(Context context, String themeMode) {
        if (THEME_DARK.equals(themeMode)) return true;
        if (!THEME_FOLLOW_SYSTEM.equals(themeMode)) return false;

        int nightMode = context.getResources().getConfiguration().uiMode
                & Configuration.UI_MODE_NIGHT_MASK;
        return nightMode == Configuration.UI_MODE_NIGHT_YES;
    }

    private static String readThemeMode(Context context) {
        File settingsFile = context.getDatabasePath(SETTINGS_DATABASE_NAME);
        if (!settingsFile.exists()) return null;

        try (SQLiteDatabase database = SQLiteDatabase.openDatabase(
                settingsFile.getPath(),
                null,
                SQLiteDatabase.OPEN_READONLY
        )) {
            try (Cursor cursor = database.rawQuery(
                    "SELECT value FROM settings WHERE key = ? LIMIT 1",
                    new String[]{THEME_MODE_KEY}
            )) {
                if (!cursor.moveToFirst()) return null;
                return cursor.getString(0);
            }
        } catch (SQLiteException exception) {
            return null;
        }
    }

    static final class Palette {
        final int backgroundDrawable;
        final int buttonBackgroundDrawable;
        final int checkboxDrawable;
        final int textColor;
        final int accentColor;
        final int buttonTextColor;
        final int separatorColor;

        private Palette(
                int backgroundDrawable,
                int buttonBackgroundDrawable,
                int checkboxDrawable,
                int textColor,
                int accentColor,
                int buttonTextColor,
                int separatorColor
        ) {
            this.backgroundDrawable = backgroundDrawable;
            this.buttonBackgroundDrawable = buttonBackgroundDrawable;
            this.checkboxDrawable = checkboxDrawable;
            this.textColor = textColor;
            this.accentColor = accentColor;
            this.buttonTextColor = buttonTextColor;
            this.separatorColor = separatorColor;
        }

        static Palette light() {
            return new Palette(
                    R.drawable.todo_home_widget_background,
                    R.drawable.todo_home_widget_button_background,
                    R.drawable.todo_home_widget_checkbox_unchecked,
                    Color.rgb(45, 42, 38),
                    Color.rgb(139, 94, 52),
                    Color.rgb(255, 252, 245),
                    Color.argb(0x33, 0x8B, 0x5E, 0x34)
            );
        }

        static Palette dark() {
            return new Palette(
                    R.drawable.todo_home_widget_background_dark,
                    R.drawable.todo_home_widget_button_background_dark,
                    R.drawable.todo_home_widget_checkbox_unchecked_dark,
                    Color.rgb(237, 226, 209),
                    Color.rgb(214, 176, 124),
                    Color.rgb(31, 27, 23),
                    Color.rgb(74, 62, 50)
            );
        }
    }
}
