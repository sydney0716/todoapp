import Foundation

struct TodoPhoneWidgetTask: Codable, Identifiable {
  let id: String
  let databaseId: Int?
  let title: String
  let requiresBothSharedCompletion: Bool?
  var isPartiallyCompleted: Bool?
  var isCompletedByCurrentUser: Bool?
}

struct TodoPhoneWidgetSnapshot: Codable {
  let languageCode: String?
  let themeMode: String?
  var openTaskCount: Int
  var tasks: [TodoPhoneWidgetTask]

  static let empty = TodoPhoneWidgetSnapshot(
    languageCode: "ko", themeMode: "LIGHT", openTaskCount: 0, tasks: []
  )

  func completing(taskId: Int, completed: Bool) -> TodoPhoneWidgetSnapshot {
    var copy = self
    copy.tasks = tasks.compactMap { original in
      guard original.databaseId == taskId else { return original }
      var task = original
      let both = task.requiresBothSharedCompletion ?? false
      let partnerDone = (task.isPartiallyCompleted ?? false) &&
        !(task.isCompletedByCurrentUser ?? false)
      if completed && (!both || partnerDone) {
        copy.openTaskCount = max(0, copy.openTaskCount - 1)
        return nil
      }
      task.isCompletedByCurrentUser = completed
      task.isPartiallyCompleted = both && (completed || partnerDone)
      return task
    }
    return copy
  }
}

enum TodoPhoneWidgetStore {
  static let appGroupId = "group.com.example.personaltodo.shared"
  private static let snapshotKey = "todo_widget_snapshot"

  static func enqueue(taskId: Int, completed: Bool, actionId: String) throws {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupId
    ) else { throw CocoaError(.fileNoSuchFile) }
    let directory = container.appendingPathComponent("todo_widget_actions", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: [
      "id": actionId, "taskId": taskId, "completed": completed,
      "createdAtMillis": Date().timeIntervalSince1970 * 1000,
    ])
    try data.write(to: directory.appendingPathComponent(actionId + ".json"), options: .atomic)
    UserDefaults(suiteName: appGroupId)?.set(directory.path, forKey: "todo_widget_action_directory")
  }

  static func load() -> TodoPhoneWidgetSnapshot {
    guard let json = UserDefaults(suiteName: appGroupId)?.string(forKey: snapshotKey),
      let data = json.data(using: .utf8),
      let snapshot = try? JSONDecoder().decode(TodoPhoneWidgetSnapshot.self, from: data)
    else { return .empty }
    return snapshot
  }

  @discardableResult
  static func predictCompletion(taskId: Int, completed: Bool) -> Bool {
    let previous = load()
    let snapshot = previous.completing(taskId: taskId, completed: completed)
    guard let data = try? JSONEncoder().encode(snapshot),
      let json = String(data: data, encoding: .utf8) else { return false }
    UserDefaults(suiteName: appGroupId)?.set(json, forKey: snapshotKey)
    return previous.tasks.contains { $0.databaseId == taskId }
      && !snapshot.tasks.contains { $0.databaseId == taskId }
  }
}
