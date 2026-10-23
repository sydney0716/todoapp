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
    await TodoDesktopWidgetActionStore.scheduleSync(force: true)
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
    await TodoDesktopWidgetActionStore.scheduleSync(force: true)
    return .result()
  }
}

enum TodoDesktopWidgetActionStore {
  static func pendingActions() -> [TodoDesktopWidgetAction] {
    guard let directory = TodoDesktopWidgetFiles.actionsURL else { return [] }
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
    guard let directory = TodoDesktopWidgetFiles.actionsURL else { throw CocoaError(.fileNoSuchFile) }
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
  static func scheduleSync(force: Bool = false) {
    guard NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.example.personaltodo"
    ).isEmpty else { return }
    TodoDesktopWidgetUpload.shared.schedule(force: force)
  }
}

// NSURLSession owns the transfer after the intent returns. WidgetKit reconnects
// this delegate if the extension is suspended; the main app is never launched.
final class TodoDesktopWidgetUpload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  static let identifier = "com.example.personaltodo.widget-actions.background"
  static let shared = TodoDesktopWidgetUpload()

  private struct Job: Codable {
    let id: String
    let context: Data
    let snapshot: Data?
    let actionIds: Set<String>
    let queuedActionIds: Set<String>
  }

  private var preparing = false
  private var completions: [() -> Void] = []
  private var directory: URL? { TodoDesktopWidgetFiles.directory }
  private var jobURL: URL? { directory?.appendingPathComponent("todo_widget_upload.json") }
  private var bodyURL: URL? { directory?.appendingPathComponent("todo_widget_upload_body.json") }
  private var responseURL: URL? { directory?.appendingPathComponent("todo_widget_upload_response.json") }
  private lazy var session: URLSession = {
    let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
    configuration.sharedContainerIdentifier = TodoDesktopWidgetFiles.appGroupId
    configuration.sessionSendsLaunchEvents = true
    configuration.isDiscretionary = false
    configuration.timeoutIntervalForResource = 120
    return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
  }()

  static func handleEvents(_ identifier: String, completion: @escaping () -> Void) {
    DispatchQueue.main.async {
      shared.completions.append(completion)
      _ = shared.session
    }
  }

  func schedule(force: Bool) {
    DispatchQueue.main.async {
      guard !self.preparing else { return }
      self.preparing = true
      self.session.getAllTasks { tasks in
        DispatchQueue.main.async {
          defer { self.preparing = false }
          guard tasks.allSatisfy({ $0.state == .completed }) else { return }
          self.start(force: force)
        }
      }
    }
  }

  private func start(force: Bool) {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.example.personaltodo").isEmpty,
          let contextURL = TodoDesktopWidgetFiles.contextURL,
          let snapshotURL = TodoDesktopWidgetFiles.snapshotURL,
          let contextData = try? Data(contentsOf: contextURL),
          let context = try? JSONDecoder().decode(TodoDesktopWidgetSyncContext.self, from: contextData),
          let bodyURL, let jobURL, let responseURL,
          let defaults = UserDefaults(suiteName: TodoDesktopWidgetFiles.appGroupId) else { return }
    let now = Date()
    let retryKey = "todo_widget_last_action_sync"
    let actions = TodoDesktopWidgetActionStore.pendingActions().filter {
      ["set_task_completion", "complete_subtask"].contains($0.type)
    }
    let previousData = try? Data(contentsOf: snapshotURL)
    let snapshot = previousData.flatMap {
      try? JSONDecoder().decode(TodoDesktopWidgetSnapshot.self, from: $0)
    } ?? .empty
    let lastAttempt = defaults.object(forKey: retryKey) as? Date
    if !force && !snapshot.needsBackgroundRefresh(
      at: now, lastAttempt: lastAttempt, hasPendingActions: !actions.isEmpty
    ) {
      return
    }
    do {
      let upload = try TodoDesktopWidgetSyncClient().upload(context: context, actions: actions)
      let job = Job(id: UUID().uuidString, context: contextData, snapshot: previousData,
                    actionIds: upload.actionIds, queuedActionIds: Set(actions.map(\.id)))
      try TodoDesktopWidgetFiles.save(upload.body, to: bodyURL)
      try TodoDesktopWidgetFiles.save(try JSONEncoder().encode(job), to: jobURL)
      try? FileManager.default.removeItem(at: responseURL)
      defaults.set(now, forKey: retryKey)
      defaults.synchronize()
      let task = session.uploadTask(with: upload.request, fromFile: bodyURL)
      task.taskDescription = job.id
      task.resume()
    } catch {
      // The original intent files remain available for the next retry.
    }
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard let url = responseURL, let jobURL,
          let jobData = try? Data(contentsOf: jobURL),
          let job = try? JSONDecoder().decode(Job.self, from: jobData),
          job.id == dataTask.taskDescription else { return }
    do {
      if FileManager.default.fileExists(atPath: url.path) {
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.seekToEnd()
        try file.write(contentsOf: data)
      } else { try TodoDesktopWidgetFiles.save(data, to: url) }
    } catch {
      // A missing/partial response cannot acknowledge durable checkbox actions.
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let jobURL, let bodyURL, let responseURL,
          let jobData = try? Data(contentsOf: jobURL),
          let job = try? JSONDecoder().decode(Job.self, from: jobData),
          job.id == task.taskDescription else { return }
    var retryRemaining = false
    defer {
      for url in [jobURL, bodyURL, responseURL] { try? FileManager.default.removeItem(at: url) }
      WidgetCenter.shared.reloadAllTimelines()
      let pending = TodoDesktopWidgetActionStore.pendingActions().filter {
        ["set_task_completion", "complete_subtask"].contains($0.type)
      }
      let newClicks = !Set(pending.map(\.id)).isSubset(of: job.queuedActionIds)
      if retryRemaining || newClicks { schedule(force: true) }
    }
    guard error == nil, let response = task.response as? HTTPURLResponse,
          (200..<300).contains(response.statusCode),
          let data = try? Data(contentsOf: responseURL),
          let contextURL = TodoDesktopWidgetFiles.contextURL,
          let snapshotURL = TodoDesktopWidgetFiles.snapshotURL,
          (try? Data(contentsOf: contextURL)) == job.context,
          let context = try? JSONDecoder().decode(TodoDesktopWidgetSyncContext.self, from: job.context)
    else { return }
    do {
      let previous = job.snapshot.flatMap {
        try? JSONDecoder().decode(TodoDesktopWidgetSnapshot.self, from: $0)
      } ?? .empty
      let result = try TodoDesktopWidgetSyncClient().uploaded(data, context: context, previous: previous)
      guard (try? Data(contentsOf: snapshotURL)) == job.snapshot else {
        retryRemaining = true
        return
      }
      try TodoDesktopWidgetFiles.save(try JSONEncoder().encode(result.snapshot), to: snapshotURL)
      let acknowledged = result.acknowledged(from: job.actionIds)
      if let actions = TodoDesktopWidgetFiles.actionsURL {
        for id in acknowledged {
          try? FileManager.default.removeItem(at: actions.appendingPathComponent(id + ".json"))
        }
      }
      retryRemaining = !acknowledged.isEmpty
        && !TodoDesktopWidgetActionStore.pendingActions().isEmpty
    } catch {
      // Keep the immediate checked state and retry later, without opening the app.
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    let handlers = completions
    completions.removeAll()
    for completion in handlers { completion() }
  }
}
