import Foundation

@main
struct NativeWidgetSyncTest {
  static func main() throws {
    try fileChecks()
    let client = TodoDesktopWidgetSyncClient()
    let previous = TodoDesktopWidgetSnapshot(
      updatedAtMillis: 1, languageCode: "ko", themeMode: "DARK", openTaskCount: 0,
      calendarDueDates: [], tasks: []
    )
    let me = "00000000-0000-4000-8000-000000000001"
    let partner = "00000000-0000-4000-8000-000000000002"
    var remote: [[String: Any]] = [
      record("existing", title: "Updated elsewhere"), record("edited", title: "Older server text"),
      record("hidden", title: "Completed locally"), record("both", title: "Shared task", both: true, users: [partner]),
      record("new", title: "New remote task"), record("deleted", title: "Deleted remotely", deleted: true),
    ]
    remote[0]["subtasks"] = (1...3).map { index in
      ["id": "child-\(index)", "title": "Child \(index)", "is_completed": false,
       "position": index, "due_at": "2026-10-\(20 + index)T10:00:00.123456Z"] as [String: Any]
    }
    let context = TodoDesktopWidgetSyncContext(
      apiBaseUrl: "https://widget.example.test/api/", refreshToken: "fixture-refresh", deviceId: "fixture-device",
      localTasks: [
        local("existing", title: "Old local text", pending: false, databaseId: 11,
              children: ["child-1": 21]),
        local("edited", title: "My offline edit", pending: true),
        local("hidden", title: "Completed locally", pending: true, hidden: true),
        local("local-new", title: "Offline new task", pending: true),
        local("removed", title: "Purged on server", pending: false),
      ]
    )
    func project(_ records: [[String: Any]]) throws -> TodoDesktopWidgetSnapshot {
      let data = try JSONSerialization.data(withJSONObject: [
        "user_id": me, "tasks": records, "acknowledged_action_ids": [],
      ])
      return try client.uploaded(data, context: context, previous: previous,
        now: Date(timeIntervalSince1970: 10_000)).snapshot
    }
    let now = Date(timeIntervalSince1970: 10_000)
    let snapshot = try project(remote)
    expect(snapshot.openTaskCount == 5, "Hide server deletions and preserve pending local creations")
    expect(snapshot.tasks.first { $0.id == "existing" }?.title == "Updated elsewhere", "Show remote edits")
    expect(snapshot.tasks.first { $0.id == "edited" }?.title == "My offline edit", "Keep unsent local edits")
    expect(!snapshot.tasks.contains { $0.id == "hidden" || $0.id == "deleted" || $0.id == "removed" },
           "Never resurrect local completion, deletion or server purges")
    let existing = snapshot.tasks.first { $0.id == "existing" }!
    expect(existing.databaseId == 11 && existing.visibleSubTasks.first?.databaseId == 21,
           "Keep existing local task and child IDs for actions")
    expect(existing.visibleSubTasks.count == 2 && snapshot.calendarDueDates?.count == 3,
           "Calendar must include due dates beyond the two displayed children")
    expect(snapshot.tasks.first { $0.id == "new" }?.databaseId == nil,
           "New remote tasks must not borrow another task's database ID")
    let both = snapshot.tasks.first { $0.id == "both" }!
    expect(both.needsBothToComplete && both.isPartiallyDone && !both.isDoneByCurrentUser,
           "Preserve which partner completed a shared Both task")
    expect(snapshot.languageCode == "ko" && snapshot.themeMode == "DARK"
           && snapshot.updatedAtMillis == now.timeIntervalSince1970 * 1000,
           "Preserve preferences and timestamp successful fetches")

    remote = (1...12).map { record("many-\($0)", title: String(format: "%02d", $0)) }
    let many = try project(remote)
    expect(many.openTaskCount == 14 && many.tasks.count == 8, "Bound the display while counting all open tasks")

    try completionChecks(client: client, previous: snapshot)

    print("Native widget direct-sync checks passed")
  }

  static func completionChecks(client: TodoDesktopWidgetSyncClient, previous: TodoDesktopWidgetSnapshot) throws {
    let taskId = "20000000-0000-4000-8000-000000000001"
    let childId = "30000000-0000-4000-8000-000000000001"
    let deviceId = "10000000-0000-4000-8000-000000000001"
    let firstId = "40000000-0000-4000-8000-000000000001"
    let secondId = "40000000-0000-4000-8000-000000000002"
    let childActionId = "40000000-0000-4000-8000-000000000003"
    let me = "00000000-0000-4000-8000-000000000001"
    let context = TodoDesktopWidgetSyncContext(
      apiBaseUrl: "https://widget.example.test", refreshToken: "fixture-refresh", deviceId: deviceId,
      localTasks: [local(taskId, title: "Task", pending: false, databaseId: 11, children: [childId: 21])]
    )
    let actions: [TodoDesktopWidgetAction] = [
      .init(id: firstId, type: "set_task_completion", taskId: 11, subTaskId: nil,
            isCompleted: true, createdAtMillis: 1, taskSyncId: taskId),
      .init(id: childActionId, type: "complete_subtask", taskId: 11, subTaskId: 21,
            isCompleted: nil, createdAtMillis: 3, taskSyncId: taskId, subTaskSyncId: childId),
      .init(id: secondId, type: "set_task_completion", taskId: 11, subTaskId: nil,
            isCompleted: false, createdAtMillis: 2, taskSyncId: taskId),
    ]
    let upload = try client.upload(context: context, actions: actions)
    expect(upload.request.url!.path == "/sync/widget-actions" && upload.request.httpMethod == "POST",
           "Use a single system-managed background upload")
    expect(upload.request.httpBody == nil, "Background upload body must be handed to URLSession as a durable file")
    let body = try JSONSerialization.jsonObject(with: upload.body) as! [String: Any]
    expect(body["device_id"] as? String == deviceId && body["refresh_token"] as? String == "fixture-refresh",
           "Authenticate the existing device session without waiting for an access-token renewal")
    let changes = body["actions"] as! [[String: Any]]
    expect(changes.map { $0["id"] as! String } == [firstId, secondId, childActionId],
           "Preserve click order when checking and unchecking rapidly")
    expect(changes[1]["is_completed"] as? Bool == false && changes[2]["subtask_sync_id"] as? String == childId,
           "Preserve desired state and child identity")
    expect(upload.actionIds == [firstId, secondId, childActionId], "Only acknowledge IDs actually uploaded")
    let pendingContext = TodoDesktopWidgetSyncContext(
      apiBaseUrl: context.apiBaseUrl, refreshToken: context.refreshToken, deviceId: context.deviceId,
      localTasks: [local(taskId, title: "Unsent local edit", pending: true, databaseId: 11)]
    )
    let deferred = try client.upload(context: pendingContext, actions: actions)
    let deferredBody = try JSONSerialization.jsonObject(with: deferred.body) as! [String: Any]
    expect((deferredBody["actions"] as! [[String: Any]]).isEmpty && deferred.actionIds.isEmpty,
           "Leave unsent database edits and their checkbox intent for the app's durable queue")
    let refresh = try client.upload(context: context, actions: [])
    let refreshBody = try JSONSerialization.jsonObject(with: refresh.body) as! [String: Any]
    expect((refreshBody["actions"] as! [[String: Any]]).isEmpty && refresh.actionIds.isEmpty,
           "Periodic refresh uses the same background transport without blocking a timeline")
    var completed = record(taskId, title: "Task")
    completed["is_completed"] = true
    let response = try JSONSerialization.data(withJSONObject: [
      "user_id": me, "tasks": [completed], "acknowledged_action_ids": [firstId],
    ])
    let result = try client.uploaded(response, context: context, previous: previous)
    expect(result.snapshot.tasks.isEmpty && result.acknowledgedActionIds == [firstId],
           "A confirmed response removes the task before its optimistic action is deleted")
    let upper = "ABCDEF00-0000-4000-8000-000000000001"
    let canonical = TodoDesktopWidgetSyncClient.Result(snapshot: result.snapshot,
      acknowledgedActionIds: [upper.lowercased(), "another-id"])
    expect(canonical.acknowledged(from: [upper, "not-uploaded"]) == [upper],
           "Server UUID normalization must still remove the original uppercase intent filename")
    var both = record(taskId, title: "Shared", both: true, users: [me])
    both["is_completed"] = false
    let halfResponse = try JSONSerialization.data(withJSONObject: [
      "user_id": me, "tasks": [both], "acknowledged_action_ids": [firstId],
    ])
    let half = try client.uploaded(halfResponse, context: context, previous: previous)
    expect(half.snapshot.tasks.count == 1 && half.snapshot.tasks[0].isPartiallyDone
           && half.snapshot.tasks[0].isDoneByCurrentUser, "Keep Both tasks visible until the partner completes them")
    do {
      _ = try client.uploaded(Data("{}".utf8), context: context, previous: previous)
      fatalError("An invalid response cannot acknowledge a pending checkbox")
    } catch is DecodingError {}
  }

  static func record(_ id: String, title: String, both: Bool = false,
                     users: [String] = [], deleted: Bool = false) -> [String: Any] {
    var record: [String: Any] = ["id": id, "title": title, "is_completed": false,
      "visibility": both ? "shared" : "private", "shared_completion_mode": both ? "both" : "single",
      "completed_by_user_ids": users, "subtasks": []]
    if deleted { record["deleted_at"] = "2026-10-21T00:00:00Z" }
    return record
  }

  static func fileChecks() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("snapshot.json")
    let first = Data("{\"tasks\":[]}".utf8)
    try TodoDesktopWidgetFiles.save(first, to: file)
    expect(try Data(contentsOf: file) == first, "Shared widget files must round-trip exactly")
    let second = Data("{\"tasks\":[{\"id\":\"test\"}]}".utf8)
    try TodoDesktopWidgetFiles.save(second, to: file)
    expect(try Data(contentsOf: file) == second, "Atomic replacement must expose the complete new snapshot")
    let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber
    expect(permissions.intValue == 0o600, "Private widget files must remain readable only by their owner")
  }

  static func local(_ id: String, title: String, pending: Bool, hidden: Bool = false,
                    databaseId: Int? = nil, children: [String: Int] = [:]) -> TodoDesktopWidgetSyncContext.LocalTask {
    .init(task: .init(id: id, databaseId: databaseId, title: title,
                     requiresBothSharedCompletion: false, isPartiallyCompleted: false,
                     isCompletedByCurrentUser: false, dueAtMillis: nil, subTasks: []),
          isPending: pending, isHidden: hidden, subTaskDatabaseIds: children)
  }

  static func expect(_ condition: Bool, _ message: String) { precondition(condition, message) }
}
