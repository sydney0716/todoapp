import Flutter
import UIKit
import home_widget
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
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
        TaskNotificationBridge.register(with: registrar.messenger(), background: true)
      }
    }
    if #available(iOS 17, *) {
      HomeWidgetBackgroundWorker.setPluginRegistrantCallback { registry in
        GeneratedPluginRegistrant.register(with: registry)
        if let registrar = registry.registrar(forPlugin: "TaskNotifications") {
          TaskNotificationBridge.register(with: registrar.messenger(), background: true)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    TaskNotificationBridge.register(with: engineBridge.applicationRegistrar.messenger())
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

}
