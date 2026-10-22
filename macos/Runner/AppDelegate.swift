import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func application(_ application: NSApplication, open urls: [URL]) {
    TodoDesktopWidgetBridge.handleOpenUrls(urls)
    if urls.contains(where: {
      $0.scheme == "personaltodo" && ["open", "open-task", "create-task"].contains($0.host ?? "")
    }) {
      application.activate(ignoringOtherApps: true)
      mainFlutterWindow?.deminiaturize(nil)
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
