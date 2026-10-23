import Foundation
import UserNotifications
#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

enum TaskNotificationBridge {
  private static let channelName = "com.example.personaltodo/task_notifications"

  static func register(with binaryMessenger: FlutterBinaryMessenger, background: Bool = false) {
    FlutterMethodChannel(
      name: channelName,
      binaryMessenger: binaryMessenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "scheduleTaskReminder":
        guard let arguments = call.arguments as? [String: Any] else {
          result(FlutterError(code: "invalid_arguments", message: "Missing notification arguments.", details: nil))
          return
        }
        self.scheduleTaskReminder(arguments, background: background, result: result)
      case "cancelTaskReminder":
        guard let arguments = call.arguments as? [String: Any] else {
          result(FlutterError(code: "invalid_arguments", message: "Missing notification arguments.", details: nil))
          return
        }
        self.cancelTaskReminder(notificationId: self.intArgument(arguments, "notificationId"))
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

  private static func scheduleTaskReminder(_ arguments: [String: Any], background: Bool, result: @escaping FlutterResult) {
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
    let request = UNNotificationRequest(
      identifier: notificationIdentifier(notificationId),
      content: content,
      trigger: trigger
    )
    center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier(notificationId)])
    let schedule: (Bool, Error?) -> Void = { granted, error in
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
    if background {
      center.getNotificationSettings { settings in
        #if os(iOS)
        let allowed: Set<UNAuthorizationStatus> = [.authorized, .provisional, .ephemeral]
        #else
        let allowed: Set<UNAuthorizationStatus> = [.authorized, .provisional]
        #endif
        schedule(allowed.contains(settings.authorizationStatus), nil)
      }
    } else {
      center.requestAuthorization(options: [.alert, .sound, .badge], completionHandler: schedule)
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
