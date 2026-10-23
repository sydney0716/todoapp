import FlutterMacOS
import WidgetKit
final class TodoDesktopWidgetBridge {
  private static let channelName = "com.example.personaltodo/widget_actions"
  private static let actionsFileName = "todo_widget_actions.json"
  private static let widgetKinds = [
    "TodoDesktopTasksWidget",
    "TodoDesktopTodoOnlyWidget",
    "TodoDesktopCalendarOnlyWidget",
  ]
  private static let openNewTaskAction = "open_new_task"
  private static let openAppAction = "open_app"
  private static let openTaskAction = "open_task"
  private static let completeTaskAction = "complete_task"
  private static let completeSubTaskAction = "complete_subtask"
  private static var actionObserver: NSObjectProtocol?
  private static var actionChannel: FlutterMethodChannel?

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: messenger
    )
    actionChannel = channel
    if let observer = actionObserver {
      DistributedNotificationCenter.default().removeObserver(observer)
    }
    actionObserver = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name("com.example.personaltodo.widget-actions"),
      object: nil, queue: .main
    ) { _ in
      channel.invokeMethod("widgetActionsAvailable", arguments: nil)
    }

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "updateWidgetSyncContext":
        do {
          guard let url = TodoDesktopWidgetFiles.contextURL else {
            throw CocoaError(.fileNoSuchFile)
          }
          if let json = call.arguments as? String, let data = json.data(using: .utf8) {
            _ = try JSONDecoder().decode(TodoDesktopWidgetSyncContext.self, from: data)
            if (try? Data(contentsOf: url)) != data {
              try TodoDesktopWidgetFiles.save(data, to: url)
            }
          } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
          }
          result(nil)
        } catch {
          result(FlutterError(code: "widget_sync_context", message: "Could not update widget session.", details: nil))
        }
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
      case "acknowledgeWidgetActions":
        acknowledgeActions(call.arguments as? [String] ?? [])
        result(nil)
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
    actionChannel?.invokeMethod("widgetActionsAvailable", arguments: nil)
  }

  private static func saveSnapshot(_ snapshotJson: String) {
    guard let snapshotUrl = TodoDesktopWidgetFiles.snapshotURL else {
      NSLog("[TodoDesktopWidgetBridge] App Group container is unavailable")
      return
    }

    guard let snapshotData = snapshotJson.data(using: .utf8) else {
      NSLog("[TodoDesktopWidgetBridge] failed to encode snapshot JSON")
      return
    }

    do {
      try TodoDesktopWidgetFiles.save(snapshotData, to: snapshotUrl)
    } catch {
      NSLog("[TodoDesktopWidgetBridge] failed to write snapshot: %@", error.localizedDescription)
    }
  }

  private static func reloadWidget() {
    for kind in widgetKinds {
      WidgetCenter.shared.reloadTimelines(ofKind: kind)
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
    case "open":
      action["type"] = openAppAction
    case "open-task":
      let syncId = queryItems?.first(where: { $0.name == "taskSyncId" })?.value
      guard let syncId, UUID(uuidString: syncId) != nil else {
        guard let taskId = intQueryItem(named: "taskId", in: queryItems), taskId > 0 else {
          return nil
        }
        action["type"] = openTaskAction
        action["taskId"] = taskId
        break
      }
      action["type"] = openTaskAction
      action["taskSyncId"] = syncId
      if let taskId = intQueryItem(named: "taskId", in: queryItems) {
        action["taskId"] = taskId
      }
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

  private static func actionsDirectory() -> URL? {
    guard let directory = TodoDesktopWidgetFiles.actionsURL else { return nil }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      return directory
    } catch { return nil }
  }

  private static func appendPendingActions(_ actions: [[String: Any]]) {
    guard let directory = actionsDirectory() else { return }
    for action in actions {
      guard let id = action["id"] as? String, UUID(uuidString: id) != nil else { continue }
      do {
        let data = try JSONSerialization.data(withJSONObject: action)
        try data.write(to: directory.appendingPathComponent(id + ".json"), options: .atomic)
      } catch { NSLog("[TodoDesktopWidgetBridge] failed to queue action: %@", error.localizedDescription) }
    }
  }

  private static func consumePendingActions() -> [[String: Any]] {
    guard let directory = actionsDirectory() else { return [] }
    // Upgrade old queue files before adopting individual, independently written actions.
    let legacy = directory.deletingLastPathComponent().appendingPathComponent(actionsFileName)
    if let data = try? Data(contentsOf: legacy),
       let actions = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
      appendPendingActions(actions)
      // Remove only when every legacy action has been durably transferred.
      if actions.allSatisfy({ action in
        guard let id = action["id"] as? String else { return false }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(id + ".json").path)
      }) { try? FileManager.default.removeItem(at: legacy) }
    }
    let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    return urls.filter { $0.pathExtension == "json" }.compactMap { url in
      guard let data = try? Data(contentsOf: url) else { return nil }
      return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }.sorted {
      ($0["createdAtMillis"] as? Double ?? 0) < ($1["createdAtMillis"] as? Double ?? 0)
    }
  }

  private static func acknowledgeActions(_ ids: [String]) {
    guard let directory = actionsDirectory() else { return }
    for id in ids where UUID(uuidString: id) != nil {
      try? FileManager.default.removeItem(at: directory.appendingPathComponent(id + ".json"))
    }
    // Drop the pending preview now that the app's snapshot contains the saved state.
    if !ids.isEmpty { reloadWidget() }
  }
}
