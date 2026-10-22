import Flutter
import UIKit
import UserNotifications
import home_widget
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let taskNotificationsChannel = "com.example.personaltodo/task_notifications"
  private var backgroundSyncTasks: Set<Int> = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.example.personaltodo.widget_refresh",
      earliestBeginInSeconds: 7200
    )
    WorkmanagerPlugin.registerLaunchHandlers()
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
      if let registrar = registry.registrar(forPlugin: "TaskNotifications") {
        AppDelegate.registerTaskNotificationChannel(binaryMessenger: registrar.messenger(), background: true)
      }
    }
    if #available(iOS 17, *) {
      HomeWidgetBackgroundWorker.setPluginRegistrantCallback { registry in
        GeneratedPluginRegistrant.register(with: registry)
        if let registrar = registry.registrar(forPlugin: "TaskNotifications") {
          AppDelegate.registerTaskNotificationChannel(binaryMessenger: registrar.messenger(), background: true)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    Self.registerTaskNotificationChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
    registerBackgroundSyncChannel(binaryMessenger: engineBridge.applicationRegistrar.messenger())
  }

  private func registerBackgroundSyncChannel(binaryMessenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(
      name: "com.example.personaltodo/background_sync",
      binaryMessenger: binaryMessenger
    ).setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "begin":
        var identifier = UIBackgroundTaskIdentifier.invalid
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Save Todo Changes") {
          self.endBackgroundSync(identifier)
        }
        if identifier == .invalid {
          result(nil)
        } else {
          self.backgroundSyncTasks.insert(identifier.rawValue)
          result(identifier.rawValue)
        }
      case "end":
        if let rawValue = call.arguments as? Int {
          self.endBackgroundSync(UIBackgroundTaskIdentifier(rawValue: rawValue))
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func endBackgroundSync(_ identifier: UIBackgroundTaskIdentifier) {
    guard backgroundSyncTasks.remove(identifier.rawValue) != nil else { return }
    UIApplication.shared.endBackgroundTask(identifier)
  }

  private static func registerTaskNotificationChannel(binaryMessenger: FlutterBinaryMessenger, background: Bool = false) {
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
        schedule([.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus), nil)
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
