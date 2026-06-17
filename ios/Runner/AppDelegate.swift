import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let taskNotificationsChannel = "com.example.personaltodo/task_notifications"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      registerTaskNotificationChannel(binaryMessenger: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func registerTaskNotificationChannel(binaryMessenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(
      name: taskNotificationsChannel,
      binaryMessenger: binaryMessenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "scheduleTaskReminder":
        guard let arguments = call.arguments as? [String: Any] else {
          result(FlutterError(code: "invalid_arguments", message: "Missing notification arguments.", details: nil))
          return
        }
        self.scheduleTaskReminder(arguments)
        result(nil)
      case "cancelTaskReminder":
        guard let arguments = call.arguments as? [String: Any] else {
          result(FlutterError(code: "invalid_arguments", message: "Missing notification arguments.", details: nil))
          return
        }
        self.cancelTaskReminder(notificationId: self.intArgument(arguments, "notificationId"))
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func scheduleTaskReminder(_ arguments: [String: Any]) {
    let notificationId = intArgument(arguments, "notificationId")
    let triggerAtMillis = doubleArgument(arguments, "triggerAtMillis")
    guard notificationId > 0 else {
      return
    }

    let triggerDate = Date(timeIntervalSince1970: triggerAtMillis / 1000)
    guard triggerDate > Date() else {
      cancelTaskReminder(notificationId: notificationId)
      return
    }

    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

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
    center.add(request)
  }

  private func cancelTaskReminder(notificationId: Int) {
    guard notificationId > 0 else {
      return
    }
    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: [notificationIdentifier(notificationId)]
    )
  }

  private func notificationIdentifier(_ notificationId: Int) -> String {
    "task-\(notificationId)"
  }

  private func intArgument(_ arguments: [String: Any], _ key: String) -> Int {
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

  private func doubleArgument(_ arguments: [String: Any], _ key: String) -> Double {
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

  private func stringArgument(_ arguments: [String: Any], _ key: String) -> String {
    arguments[key] as? String ?? ""
  }
}
