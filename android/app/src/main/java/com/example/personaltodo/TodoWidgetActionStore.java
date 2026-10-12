package com.example.personaltodo;

import android.content.Context;
import android.util.AtomicFile;

import es.antonborri.home_widget.HomeWidgetPlugin;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/** Pending widget edits also supply the display while Flutter saves them. */
final class TodoWidgetActionStore {
    private static File directory(Context context) {
        return context.getDatabasePath("todo_widget_actions");
    }

    static void enqueue(Context context, long taskId, long subTaskId,
                        boolean completed, String userId) throws IOException, JSONException {
        File directory = directory(context);
        if (!directory.isDirectory() && !directory.mkdirs()) {
            throw new IOException("Could not create widget action directory");
        }
        String id = UUID.randomUUID().toString();
        JSONObject action = new JSONObject()
                .put("id", id)
                .put("taskId", taskId)
                .put("completed", completed)
                .put("userId", userId)
                .put("createdAtMillis", System.currentTimeMillis());
        if (subTaskId > 0) action.put("subTaskId", subTaskId);
        File temporary = new File(directory, id + ".tmp");
        AtomicFile file = new AtomicFile(temporary);
        FileOutputStream stream = file.startWrite();
        try {
            stream.write(action.toString().getBytes(StandardCharsets.UTF_8));
            file.finishWrite(stream);
        } catch (IOException error) {
            file.failWrite(stream);
            throw error;
        }
        // Publish only complete JSON, including on older Android releases.
        if (!temporary.renameTo(new File(directory, id + ".json"))) {
            throw new IOException("Could not publish widget action");
        }
        HomeWidgetPlugin.Companion.getData(context).edit()
                .putString("todo_widget_action_directory", directory.getAbsolutePath()).commit();
    }

    static PendingActions read(Context context, String userId) {
        PendingActions pending = new PendingActions();
        File[] files = directory(context).listFiles((dir, name) -> name.endsWith(".json"));
        if (files == null) return pending;
        List<JSONObject> actions = new ArrayList<>();
        for (File file : files) {
            try {
                JSONObject action = new JSONObject(new String(
                        Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8));
                if (userId.equals(action.optString("userId"))
                        && action.optLong("taskId") > 0
                        && action.opt("completed") instanceof Boolean) {
                    actions.add(action);
                }
            } catch (IOException | JSONException ignored) {
                // Another engine may have consumed the file already.
            }
        }
        actions.sort(Comparator.comparingLong(action -> action.optLong("createdAtMillis")));
        for (JSONObject action : actions) {
            long subTaskId = action.optLong("subTaskId");
            if (subTaskId > 0 && action.optBoolean("completed")) {
                pending.subTaskIds.add(subTaskId);
            } else if (subTaskId == 0) {
                pending.taskCompletions.put(action.optLong("taskId"), action.optBoolean("completed"));
            }
        }
        return pending;
    }

    static final class PendingActions {
        final Map<Long, Boolean> taskCompletions = new HashMap<>();
        final Set<Long> subTaskIds = new HashSet<>();
    }
}
