import AppIntents
import AppKit
import Foundation
import WidgetKit

// Keep these intents available in both the app and widget targets.
@available(macOS 14.0, *)
struct CompleteTaskIntent: AppIntent {
  static var title: LocalizedStringResource = "Complete Task"
  static var openAppWhenRun = false

  @Parameter(title: "Task ID")
  var taskId: Int

  @Parameter(title: "Task Sync ID")
  var taskSyncId: String?

  @Parameter(title: "Completed", default: true)
  var isCompleted: Bool

  init() {}

  init(taskId: Int, isCompleted: Bool, taskSyncId: String? = nil) {
    self.taskId = taskId
    self.isCompleted = isCompleted
    self.taskSyncId = taskSyncId
  }

  func perform() async throws -> some IntentResult {
    try TodoDesktopWidgetActionStore.enqueue(
      type: "set_task_completion",
      taskId: taskId,
      subTaskId: nil,
      isCompleted: isCompleted,
      taskSyncId: taskSyncId
    )
    WidgetCenter.shared.reloadAllTimelines()
    await TodoDesktopWidgetActionStore.wakeAppInBackground()
    return .result()
  }
}

@available(macOS 14.0, *)
struct CompleteSubTaskIntent: AppIntent {
  static var title: LocalizedStringResource = "Complete Subtask"
  static var openAppWhenRun = false

  @Parameter(title: "Task ID")
  var taskId: Int

  @Parameter(title: "Subtask ID")
  var subTaskId: Int

  @Parameter(title: "Task Sync ID")
  var taskSyncId: String?

  @Parameter(title: "Subtask Sync ID")
  var subTaskSyncId: String?

  init() {}

  init(taskId: Int, subTaskId: Int, taskSyncId: String? = nil, subTaskSyncId: String? = nil) {
    self.taskId = taskId
    self.subTaskId = subTaskId
    self.taskSyncId = taskSyncId
    self.subTaskSyncId = subTaskSyncId
  }

  func perform() async throws -> some IntentResult {
    try TodoDesktopWidgetActionStore.enqueue(
      type: "complete_subtask",
      taskId: taskId,
      subTaskId: subTaskId,
      taskSyncId: taskSyncId,
      subTaskSyncId: subTaskSyncId
    )
    WidgetCenter.shared.reloadAllTimelines()
    await TodoDesktopWidgetActionStore.wakeAppInBackground()
    return .result()
  }
}

enum TodoDesktopWidgetActionStore {
  private static func actionsDirectory() -> URL? {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "V3KLD59MGY.com.example.personaltodo.shared"
    ) else { return nil }
    return container.appendingPathComponent("todo_widget_actions", isDirectory: true)
  }

  static func pendingActions() -> [TodoDesktopWidgetAction] {
    guard let directory = actionsDirectory() else { return [] }
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    )) ?? []
    return urls.filter { $0.pathExtension == "json" }.compactMap { url in
      guard let data = try? Data(contentsOf: url) else { return nil }
      return try? JSONDecoder().decode(TodoDesktopWidgetAction.self, from: data)
    }
  }

  static func enqueue(type: String, taskId: Int, subTaskId: Int?, isCompleted: Bool? = nil,
                      taskSyncId: String? = nil, subTaskSyncId: String? = nil) throws {
    guard let directory = actionsDirectory() else { throw CocoaError(.fileNoSuchFile) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let action = TodoDesktopWidgetAction(
      id: UUID().uuidString,
      type: type,
      taskId: taskId,
      subTaskId: subTaskId,
      isCompleted: isCompleted,
      createdAtMillis: Date().timeIntervalSince1970 * 1000,
      taskSyncId: taskSyncId, subTaskSyncId: subTaskSyncId
    )
    try JSONEncoder().encode(action).write(
      to: directory.appendingPathComponent(action.id + ".json"),
      options: .atomic
    )
    DistributedNotificationCenter.default().postNotificationName(
      Notification.Name("com.example.personaltodo.widget-actions"),
      object: nil, userInfo: nil, deliverImmediately: true
    )
  }

  @MainActor
  static func wakeAppInBackground() {
    guard NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.example.personaltodo"
    ).isEmpty else { return }

    let appUrl = Bundle.main.bundleURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    guard appUrl.pathExtension == "app" else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    NSWorkspace.shared.openApplication(at: appUrl, configuration: configuration) { _, error in
      if let error {
        NSLog("[TodoDesktopWidget] background launch failed: %@", error.localizedDescription)
      }
    }
  }
}
