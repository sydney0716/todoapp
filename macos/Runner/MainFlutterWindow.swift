import Cocoa
import FlutterMacOS
import UserNotifications

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    TodoDesktopWidgetBridge.register(with: flutterViewController.engine.binaryMessenger)
    TaskNotificationBridge.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

private enum TaskNotificationBridge {
  private static let channelName = "com.example.personaltodo/task_notifications"

  static func register(with binaryMessenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(
      name: channelName,
      binaryMessenger: binaryMessenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "scheduleTaskReminder":
        guard let arguments = call.arguments as? [String: Any] else {
          result(
            FlutterError(
              code: "invalid_arguments",
              message: "Missing notification arguments.",
              details: nil
            )
          )
          return
        }
        scheduleTaskReminder(arguments, result: result)
      case "cancelTaskReminder":
        guard let arguments = call.arguments as? [String: Any] else {
          result(
            FlutterError(
              code: "invalid_arguments",
              message: "Missing notification arguments.",
              details: nil
            )
          )
          return
        }
        cancelTaskReminder(notificationId: intArgument(arguments, "notificationId"))
        result(nil)
      case "getScheduledTaskReminderIds":
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
          let ids = requests.compactMap { request -> Int? in
            guard request.identifier.hasPrefix("task-") else { return nil }
            return Int(request.identifier.dropFirst(5))
          }
          DispatchQueue.main.async { result(ids) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func scheduleTaskReminder(_ arguments: [String: Any], result: @escaping FlutterResult) {
    let notificationId = intArgument(arguments, "notificationId")
    let triggerAtMillis = doubleArgument(arguments, "triggerAtMillis")
    guard notificationId > 0 else {
      result(FlutterError(code: "invalid_arguments", message: "Invalid reminder ID.", details: nil))
      return
    }

    let triggerDate = Date(timeIntervalSince1970: triggerAtMillis / 1000)
    guard triggerDate > Date() else {
      cancelTaskReminder(notificationId: notificationId)
      result(nil)
      return
    }

    let center = UNUserNotificationCenter.current()

    let content = UNMutableNotificationContent()
    content.title = stringArgument(arguments, "title")
    content.body = stringArgument(arguments, "body")
    content.sound = .default

    let interval = max(1, triggerDate.timeIntervalSinceNow)
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
    let identifier = notificationIdentifier(notificationId)
    let request = UNNotificationRequest(
      identifier: identifier,
      content: content,
      trigger: trigger
    )
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      guard granted && error == nil else {
        DispatchQueue.main.async {
          result(FlutterError(code: "notifications_denied", message: error?.localizedDescription ?? "Enable notifications for Personal Todo in system settings.", details: nil))
        }
        return
      }
      center.add(request) { error in
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "notification_failed", message: error.localizedDescription, details: nil))
          } else { result(nil) }
        }
      }
    }
  }

  private static func cancelTaskReminder(notificationId: Int) {
    guard notificationId > 0 else {
      return
    }
    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: [notificationIdentifier(notificationId)]
    )
  }

  private static func notificationIdentifier(_ notificationId: Int) -> String {
    "task-\(notificationId)"
  }

  private static func intArgument(_ arguments: [String: Any], _ key: String) -> Int {
    if let value = arguments[key] as? Int {
      return value
    }
    if let value = arguments[key] as? NSNumber {
      return value.intValue
    }
    if let value = arguments[key] as? String {
      return Int(value) ?? 0
    }
    return 0
  }

  private static func doubleArgument(_ arguments: [String: Any], _ key: String) -> Double {
    if let value = arguments[key] as? Double {
      return value
    }
    if let value = arguments[key] as? NSNumber {
      return value.doubleValue
    }
    if let value = arguments[key] as? String {
      return Double(value) ?? 0
    }
    return 0
  }

  private static func stringArgument(_ arguments: [String: Any], _ key: String) -> String {
    arguments[key] as? String ?? ""
  }
}
