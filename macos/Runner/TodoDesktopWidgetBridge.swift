import FlutterMacOS
import WidgetKit
import os.log

private let todoDesktopWidgetLogger = OSLog(
  subsystem: "com.example.personaltodo",
  category: "TodoDesktopWidgetBridge"
)

final class TodoDesktopWidgetBridge {
  private static let channelName = "com.example.personaltodo/widget_actions"
  private static let appGroupId = "V3KLD59MGY.com.example.personaltodo.shared"
  private static let snapshotKey = "todo_widget_snapshot"
  private static let snapshotFileName = "todo_widget_snapshot.json"
  private static let actionsFileName = "todo_widget_actions.json"
  private static let widgetKinds = [
    "TodoDesktopTasksWidget",
    "TodoDesktopTodoOnlyWidget",
    "TodoDesktopCalendarOnlyWidget",
  ]
  private static let openNewTaskAction = "open_new_task"
  private static let completeTaskAction = "complete_task"
  private static let completeSubTaskAction = "complete_subtask"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: messenger
    )

    NSLog("[TodoDesktopWidgetBridge] registered on channel: %@", channelName)

    channel.setMethodCallHandler { call, result in
      if call.method != "consumePendingWidgetActions" {
        NSLog("[TodoDesktopWidgetBridge] received method call: %@", call.method)
      }

      switch call.method {
      case "updateWidgetSnapshot":
        guard let snapshotJson = call.arguments as? String else {
          result(
            FlutterError(
              code: "invalid_snapshot",
              message: "Expected a JSON widget snapshot.",
              details: nil
            )
          )
          return
        }
        saveSnapshot(snapshotJson)
        reloadWidget()
        result(nil)
      case "reloadWidget":
        reloadWidget()
        result(nil)
      case "consumePendingWidgetActions":
        result(consumePendingActions())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func handleOpenUrls(_ urls: [URL]) {
    let actions = urls.compactMap(actionFromUrl)
    guard !actions.isEmpty else {
      return
    }

    appendPendingActions(actions)
  }

  private static func saveSnapshot(_ snapshotJson: String) {
    if let defaults = UserDefaults(suiteName: appGroupId) {
      defaults.set(snapshotJson, forKey: snapshotKey)
      defaults.synchronize()
    } else {
      NSLog("[TodoDesktopWidgetBridge] UserDefaults suite is unavailable: %@", appGroupId)
    }

    guard let containerUrl = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupId
    ) else {
      NSLog("[TodoDesktopWidgetBridge] App Group container is unavailable: %@", appGroupId)
      return
    }

    guard let snapshotData = snapshotJson.data(using: .utf8) else {
      NSLog("[TodoDesktopWidgetBridge] failed to encode snapshot JSON")
      return
    }

    let snapshotUrl = containerUrl.appendingPathComponent(
      snapshotFileName,
      isDirectory: false
    )

    do {
      try snapshotData.write(to: snapshotUrl, options: .atomic)
      NSLog("[TodoDesktopWidgetBridge] wrote snapshot to %@ (%d bytes)", snapshotUrl.path, snapshotData.count)
    } catch {
      NSLog("[TodoDesktopWidgetBridge] failed to write snapshot: %@", error.localizedDescription)
    }
  }

  private static func reloadWidget() {
    if #available(macOS 11.0, *) {
      for kind in widgetKinds {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
      }
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  private static func actionFromUrl(_ url: URL) -> [String: Any]? {
    guard url.scheme == "personaltodo" else {
      return nil
    }

    var action: [String: Any] = [
      "id": UUID().uuidString,
      "createdAtMillis": Int64(Date().timeIntervalSince1970 * 1000),
    ]

    let queryItems = URLComponents(
      url: url,
      resolvingAgainstBaseURL: false
    )?.queryItems

    let command = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    switch command {
    case "create-task":
      action["type"] = openNewTaskAction
      if
        let dueAtMillisText = queryItems?.first(where: { $0.name == "dueAtMillis" })?.value,
        let dueAtMillis = Int64(dueAtMillisText)
      {
        action["dueAtMillis"] = dueAtMillis
      }
    case "complete-task":
      guard let taskId = intQueryItem(named: "taskId", in: queryItems) else {
        return nil
      }
      action["type"] = completeTaskAction
      action["taskId"] = taskId
    case "complete-subtask":
      guard
        let taskId = intQueryItem(named: "taskId", in: queryItems),
        let subTaskId = intQueryItem(named: "subTaskId", in: queryItems)
      else {
        return nil
      }
      action["type"] = completeSubTaskAction
      action["taskId"] = taskId
      action["subTaskId"] = subTaskId
    default:
      return nil
    }

    return action
  }

  private static func intQueryItem(
    named name: String,
    in queryItems: [URLQueryItem]?
  ) -> Int? {
    guard
      let text = queryItems?.first(where: { $0.name == name })?.value,
      let value = Int(text)
    else {
      return nil
    }

    return value
  }

  private static func appendPendingActions(_ actions: [[String: Any]]) {
    guard let actionsUrl = pendingActionsUrl() else {
      return
    }

    let existingActions = readPendingActions(from: actionsUrl)
    let nextActions = existingActions + actions

    do {
      let data = try JSONSerialization.data(withJSONObject: nextActions)
      try data.write(to: actionsUrl, options: .atomic)
      NSLog("[TodoDesktopWidgetBridge] queued %d URL action(s)", actions.count)
    } catch {
      NSLog("[TodoDesktopWidgetBridge] failed to queue URL actions: %@", error.localizedDescription)
    }
  }

  private static func consumePendingActions() -> [[String: Any]] {
    guard let actionsUrl = pendingActionsUrl() else {
      return []
    }

    guard FileManager.default.fileExists(atPath: actionsUrl.path) else {
      return []
    }

    let actions = readPendingActions(from: actionsUrl)

    do {
      try FileManager.default.removeItem(at: actionsUrl)
    } catch {
      let nsError = error as NSError
      if nsError.domain != NSCocoaErrorDomain || nsError.code != NSFileNoSuchFileError {
        NSLog("[TodoDesktopWidgetBridge] failed to remove pending actions: %@", error.localizedDescription)
      }
    }

    return actions
  }

  private static func pendingActionsUrl() -> URL? {
    guard let containerUrl = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupId
    ) else {
      return nil
    }

    return containerUrl.appendingPathComponent(
      actionsFileName,
      isDirectory: false
    )
  }

  private static func readPendingActions(from url: URL) -> [[String: Any]] {
    guard let data = try? Data(contentsOf: url) else {
      return []
    }

    return (
      try? JSONSerialization.jsonObject(with: data)
    ) as? [[String: Any]] ?? []
  }
}
