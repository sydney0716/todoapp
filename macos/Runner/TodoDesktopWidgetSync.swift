import Foundation

// The extension owns its display cache and durable checkbox actions. Flutter
// still owns the app database and its separate queue of local edits.
struct TodoDesktopWidgetSyncContext: Codable {
  struct LocalTask: Codable {
    let task: TodoDesktopWidgetTask
    let isPending: Bool
    let isHidden: Bool
    let subTaskDatabaseIds: [String: Int]
  }

  let apiBaseUrl: String
  let refreshToken: String
  let deviceId: String
  let localTasks: [LocalTask]
}

enum TodoDesktopWidgetFiles {
  static let appGroupId = "V3KLD59MGY.com.example.personaltodo.shared"

  static var directory: URL? {
    FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupId
    )
  }

  static var contextURL: URL? {
    directory?.appendingPathComponent("todo_widget_sync_context.json")
  }

  static var snapshotURL: URL? {
    directory?.appendingPathComponent("todo_widget_snapshot.json")
  }

  static var actionsURL: URL? {
    directory?.appendingPathComponent("todo_widget_actions", isDirectory: true)
  }

  static func save(_ data: Data, to url: URL) throws {
    // Credentials stay in the sandboxed App Group, never in a widget timeline.
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}

struct TodoDesktopWidgetSyncClient {
  struct Result {
    let snapshot: TodoDesktopWidgetSnapshot
    let acknowledgedActionIds: Set<String>

    func acknowledged(from uploadedIds: Set<String>) -> Set<String> {
      let canonical = Set(acknowledgedActionIds.map { $0.lowercased() })
      return Set(uploadedIds.filter { canonical.contains($0.lowercased()) })
    }
  }

  private struct RemoteSubTask: Decodable {
    let id: String
    let title: String
    let isCompleted: Bool
    let deletedAt: String?
    let dueAt: String?
    let position: Int
  }

  private struct RemoteTask: Decodable {
    let id: String
    let title: String
    let isCompleted: Bool
    let deletedAt: String?
    let dueAt: String?
    let visibility: String
    let sharedCompletionMode: String
    let completedByUserIds: [String]
    let subtasks: [RemoteSubTask]
  }

  private func snapshot(
    _ remoteTasks: [RemoteTask], userId: String,
    context: TodoDesktopWidgetSyncContext, previous: TodoDesktopWidgetSnapshot, now: Date
  ) throws -> TodoDesktopWidgetSnapshot {
    var locals: [String: TodoDesktopWidgetSyncContext.LocalTask] = [:]
    for local in context.localTasks { locals[local.task.id] = local }
    var tasks: [String: TodoDesktopWidgetTask] = [:]
    for remote in remoteTasks where !remote.isCompleted && remote.deletedAt == nil {
      let local = locals[remote.id]
      let both = remote.visibility == "shared" && remote.sharedCompletionMode == "both"
      tasks[remote.id] = TodoDesktopWidgetTask(
        id: remote.id, databaseId: local?.task.databaseId, title: remote.title,
        requiresBothSharedCompletion: both,
        isPartiallyCompleted: both && !remote.completedByUserIds.isEmpty,
        isCompletedByCurrentUser: remote.completedByUserIds.contains(userId),
        dueAtMillis: try millis(remote.dueAt),
        subTasks: try remote.subtasks
          .filter { !$0.isCompleted && $0.deletedAt == nil }
          .sorted { $0.position == $1.position ? $0.id < $1.id : $0.position < $1.position }
          .map { child in
            TodoDesktopWidgetSubTask(
              id: child.id, databaseId: local?.subTaskDatabaseIds[child.id], title: child.title,
              dueAtMillis: try millis(child.dueAt)
            )
          }
      )
    }
    // Never replace local unsent edits with an older server copy, or resurrect
    // a locally completed/deleted task while its upload is still pending.
    for local in context.localTasks where local.isPending {
      tasks[local.task.id] = local.isHidden ? nil : local.task
    }
    let sorted = tasks.values.sorted { first, second in
      switch (first.dueAtMillis, second.dueAtMillis) {
      case let (a?, b?) where a != b: return a < b
      case (.some, .none): return true
      case (.none, .some): return false
      default: return first.title.lowercased() < second.title.lowercased()
      }
    }
    let calendar = Calendar.current
    let dates = Set(sorted.flatMap { task in
      ([task.dueAtMillis] + task.visibleSubTasks.map(\.dueAtMillis)).compactMap { millis -> Double? in
        guard let millis else { return nil }
        return calendar.startOfDay(for: Date(timeIntervalSince1970: millis / 1000))
          .timeIntervalSince1970 * 1000
      }
    })
    let visible = sorted.prefix(8).map { task in
      var task = task
      task.subTasks = Array(task.visibleSubTasks.prefix(2))
      return task
    }
    let snapshot = TodoDesktopWidgetSnapshot(
      updatedAtMillis: now.timeIntervalSince1970 * 1000,
      languageCode: previous.languageCode, themeMode: previous.themeMode,
      openTaskCount: sorted.count, calendarDueDates: dates.sorted(), tasks: visible
    )
    return snapshot
  }

  struct Upload {
    let request: URLRequest
    let body: Data
    let actionIds: Set<String>
  }

  private struct ActionResponse: Decodable {
    let userId: String
    let tasks: [RemoteTask]
    let acknowledgedActionIds: [String]
  }

  func upload(
    context: TodoDesktopWidgetSyncContext, actions: [TodoDesktopWidgetAction]
  ) throws -> Upload {
    var changes: [[String: Any]] = []
    var ids: Set<String> = []
    for action in actions.sorted(by: { $0.createdAtMillis < $1.createdAtMillis }) {
      guard ["set_task_completion", "complete_subtask"].contains(action.type) else { continue }
      let local = context.localTasks.first { local in
        if let id = action.taskSyncId { return local.task.id == id }
        return local.task.databaseId == action.taskId
      }
      // Leave unsent app edits in its own durable queue. The app can consume
      // these checkbox intents when manually opened, without losing either edit.
      guard local?.isPending != true,
            let taskId = action.taskSyncId ?? local?.task.id else { continue }
      var change: [String: Any] = ["id": action.id, "task_sync_id": taskId]
      if action.type == "complete_subtask" {
        guard let childId = action.subTaskSyncId
          ?? local?.subTaskDatabaseIds.first(where: { $0.value == action.subTaskId })?.key else { continue }
        change["subtask_sync_id"] = childId
        change["is_completed"] = true
      } else {
        guard let completed = action.isCompleted else { continue }
        change["is_completed"] = completed
      }
      changes.append(change)
      ids.insert(action.id)
      if changes.count == 100 { break }
    }
    let body = try JSONSerialization.data(withJSONObject: [
      "device_id": context.deviceId, "refresh_token": context.refreshToken, "actions": changes,
    ])
    var request = try urlRequest("/sync/widget-actions", context: context)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    return Upload(request: request, body: body, actionIds: ids)
  }

  func uploaded(
    _ data: Data, context: TodoDesktopWidgetSyncContext,
    previous: TodoDesktopWidgetSnapshot, now: Date = Date()
  ) throws -> Result {
    let response: ActionResponse = try decode(data)
    return Result(
      snapshot: try snapshot(response.tasks, userId: response.userId, context: context, previous: previous, now: now),
      acknowledgedActionIds: Set(response.acknowledgedActionIds)
    )
  }

  private func decode<T: Decodable>(_ data: Data) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: data)
  }

  private func urlRequest(_ path: String, context: TodoDesktopWidgetSyncContext) throws -> URLRequest {
    guard var components = URLComponents(string: context.apiBaseUrl),
          components.scheme == "https", components.host != nil,
          components.user == nil, components.password == nil else { throw URLError(.badURL) }
    components.path = "/" + (components.path.split(separator: "/") + path.split(separator: "/")).joined(separator: "/")
    components.query = nil
    components.fragment = nil
    guard let url = components.url else { throw URLError(.badURL) }
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  private func millis(_ value: String?) throws -> Double? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date.timeIntervalSince1970 * 1000 }
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = formatter.date(from: value) else { throw URLError(.cannotParseResponse) }
    return date.timeIntervalSince1970 * 1000
  }
}
