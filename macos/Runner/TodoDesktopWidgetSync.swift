import Foundation

// The extension only updates its display cache. The app's database and upload
// queue remain owned by Flutter, including any edits made while offline.
struct TodoDesktopWidgetSyncContext: Codable {
  struct LocalTask: Codable {
    let task: TodoDesktopWidgetTask
    let isPending: Bool
    let isHidden: Bool
    let subTaskDatabaseIds: [String: Int]
  }

  let apiBaseUrl: String
  let refreshToken: String
  let deviceId: String
  let localTasks: [LocalTask]
}

enum TodoDesktopWidgetFiles {
  static var directory: URL? {
    FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "V3KLD59MGY.com.example.personaltodo.shared"
    )
  }

  static var contextURL: URL? {
    directory?.appendingPathComponent("todo_widget_sync_context.json")
  }

  static var snapshotURL: URL? {
    directory?.appendingPathComponent("todo_widget_snapshot.json")
  }

  static func save(_ data: Data, to url: URL) throws {
    // Credentials stay in the sandboxed App Group, never in a widget timeline.
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}

struct TodoDesktopWidgetSyncClient {
  let session: URLSession

  init(session: URLSession? = nil) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 8
    configuration.timeoutIntervalForResource = 20
    self.session = session ?? URLSession(configuration: configuration)
  }

  private struct Auth: Decodable {
    let accessToken: String
    let userId: String
  }

  private struct Bootstrap: Decodable {
    let tasks: [RemoteTask]
  }

  private struct RemoteSubTask: Decodable {
    let id: String
    let title: String
    let isCompleted: Bool
    let deletedAt: String?
    let dueAt: String?
    let position: Int
  }

  private struct RemoteTask: Decodable {
    let id: String
    let title: String
    let isCompleted: Bool
    let deletedAt: String?
    let dueAt: String?
    let visibility: String
    let sharedCompletionMode: String
    let completedByUserIds: [String]
    let subtasks: [RemoteSubTask]
  }

  func fetch(
    context: TodoDesktopWidgetSyncContext,
    previous: TodoDesktopWidgetSnapshot,
    now: Date = Date()
  ) async throws -> TodoDesktopWidgetSnapshot {
    // Access tokens last less than the refresh interval. Renew directly using
    // the existing device session; this does not rotate its refresh token.
    let auth: Auth = try await request(
      "/auth/refresh", context: context,
      body: ["refresh_token": context.refreshToken, "device_id": context.deviceId]
    )
    let bootstrap: Bootstrap = try await request(
      "/sync/bootstrap", context: context, accessToken: auth.accessToken
    )
    var locals: [String: TodoDesktopWidgetSyncContext.LocalTask] = [:]
    for local in context.localTasks { locals[local.task.id] = local }
    var tasks: [String: TodoDesktopWidgetTask] = [:]
    for remote in bootstrap.tasks where !remote.isCompleted && remote.deletedAt == nil {
      let local = locals[remote.id]
      let both = remote.visibility == "shared" && remote.sharedCompletionMode == "both"
      tasks[remote.id] = TodoDesktopWidgetTask(
        id: remote.id, databaseId: local?.task.databaseId, title: remote.title,
        requiresBothSharedCompletion: both,
        isPartiallyCompleted: both && !remote.completedByUserIds.isEmpty,
        isCompletedByCurrentUser: remote.completedByUserIds.contains(auth.userId),
        dueAtMillis: try millis(remote.dueAt),
        subTasks: try remote.subtasks
          .filter { !$0.isCompleted && $0.deletedAt == nil }
          .sorted { $0.position == $1.position ? $0.id < $1.id : $0.position < $1.position }
          .map { child in
            TodoDesktopWidgetSubTask(
              id: child.id, databaseId: local?.subTaskDatabaseIds[child.id], title: child.title,
              dueAtMillis: try millis(child.dueAt)
            )
          }
      )
    }
    // Never replace local unsent edits with an older server copy, or resurrect
    // a locally completed/deleted task while its upload is still pending.
    for local in context.localTasks where local.isPending {
      tasks[local.task.id] = local.isHidden ? nil : local.task
    }
    let sorted = tasks.values.sorted { first, second in
      switch (first.dueAtMillis, second.dueAtMillis) {
      case let (a?, b?) where a != b: return a < b
      case (.some, .none): return true
      case (.none, .some): return false
      default: return first.title.lowercased() < second.title.lowercased()
      }
    }
    let calendar = Calendar.current
    let dates = Set(sorted.flatMap { task in
      ([task.dueAtMillis] + task.visibleSubTasks.map(\.dueAtMillis)).compactMap { millis -> Double? in
        guard let millis else { return nil }
        return calendar.startOfDay(for: Date(timeIntervalSince1970: millis / 1000))
          .timeIntervalSince1970 * 1000
      }
    })
    let visible = sorted.prefix(8).map { task in
      var task = task
      task.subTasks = Array(task.visibleSubTasks.prefix(2))
      return task
    }
    return TodoDesktopWidgetSnapshot(
      updatedAtMillis: now.timeIntervalSince1970 * 1000,
      languageCode: previous.languageCode, themeMode: previous.themeMode,
      openTaskCount: sorted.count, calendarDueDates: dates.sorted(), tasks: visible
    )
  }

  private func request<T: Decodable>(
    _ path: String, context: TodoDesktopWidgetSyncContext,
    accessToken: String? = nil, body: [String: String]? = nil
  ) async throws -> T {
    guard var components = URLComponents(string: context.apiBaseUrl),
          components.scheme == "https", components.host != nil,
          components.user == nil, components.password == nil else { throw URLError(.badURL) }
    components.path = "/" + (components.path.split(separator: "/") + path.split(separator: "/")).joined(separator: "/")
    components.query = nil
    components.fragment = nil
    guard let url = components.url else { throw URLError(.badURL) }
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let accessToken { request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization") }
    if let body {
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(body)
    }
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse,
          (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: data)
  }

  private func millis(_ value: String?) throws -> Double? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date.timeIntervalSince1970 * 1000 }
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = formatter.date(from: value) else { throw URLError(.cannotParseResponse) }
    return date.timeIntervalSince1970 * 1000
  }
}
