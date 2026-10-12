import AppIntents
import Foundation
import WidgetKit
import UserNotifications
import home_widget

@available(iOS 17, *)
struct CompletePhoneTaskIntent: AppIntent {
  static var title: LocalizedStringResource = "Complete Task"
  static var openAppWhenRun = false

  @Parameter(title: "Task ID") var taskId: Int
  @Parameter(title: "Completed", default: true) var completed: Bool

  init() {}

  init(taskId: Int, completed: Bool) {
    self.taskId = taskId
    self.completed = completed
  }

  func perform() async throws -> some IntentResult {
    let actionId = UUID().uuidString
    try TodoPhoneWidgetStore.enqueue(taskId: taskId, completed: completed, actionId: actionId)
    if TodoPhoneWidgetStore.predictCompletion(taskId: taskId, completed: completed) {
      // The background Flutter engine has no window notification channel.
      UNUserNotificationCenter.current().removePendingNotificationRequests(
        withIdentifiers: ["task-\(taskId)"]
      )
    }
    WidgetCenter.shared.reloadTimelines(ofKind: "TodoPhoneTasksWidget")
    var components = URLComponents()
    components.scheme = "personaltodo"
    components.host = "complete-task"
    components.queryItems = [
      URLQueryItem(name: "taskId", value: String(taskId)),
      URLQueryItem(name: "completed", value: String(completed)),
      URLQueryItem(name: "actionId", value: actionId),
    ]
    await HomeWidgetBackgroundWorker.run(
      url: components.url, appGroup: TodoPhoneWidgetStore.appGroupId
    )
    return .result()
  }
}

@available(iOS 17, *)
@available(iOSApplicationExtension, unavailable)
extension CompletePhoneTaskIntent: ForegroundContinuableIntent {}
