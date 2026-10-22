import Foundation

private final class WidgetSyncProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (Int, Data))!
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, data) = try Self.handler(request)
      let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                     headerFields: ["Content-Type": "application/json"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}

@main
struct NativeWidgetSyncTest {
  static func main() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [WidgetSyncProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let client = TodoDesktopWidgetSyncClient(session: session)
    let previous = TodoDesktopWidgetSnapshot(
      updatedAtMillis: 1, languageCode: "ko", themeMode: "DARK", openTaskCount: 0,
      calendarDueDates: [], tasks: []
    )
    let me = "00000000-0000-4000-8000-000000000001"
    let partner = "00000000-0000-4000-8000-000000000002"
    var remote: [[String: Any]] = [
      record("existing", title: "Updated elsewhere"), record("edited", title: "Older server text"),
      record("hidden", title: "Completed locally"), record("both", title: "Shared task", both: true, users: [partner]),
      record("new", title: "New remote task"), record("deleted", title: "Deleted remotely", deleted: true),
    ]
    remote[0]["subtasks"] = (1...3).map { index in
      ["id": "child-\(index)", "title": "Child \(index)", "is_completed": false,
       "position": index, "due_at": "2026-10-\(20 + index)T10:00:00.123456Z"] as [String: Any]
    }
    let context = TodoDesktopWidgetSyncContext(
      apiBaseUrl: "https://widget.example.test/api/", refreshToken: "fixture-refresh", deviceId: "fixture-device",
      localTasks: [
        local("existing", title: "Old local text", pending: false, databaseId: 11,
              children: ["child-1": 21]),
        local("edited", title: "My offline edit", pending: true),
        local("hidden", title: "Completed locally", pending: true, hidden: true),
        local("local-new", title: "Offline new task", pending: true),
        local("removed", title: "Purged on server", pending: false),
      ]
    )
    var requests: [String] = []
    WidgetSyncProtocol.handler = { request in
      requests.append(request.url!.path)
      if request.url!.path == "/api/auth/refresh" {
        expect(request.httpMethod == "POST", "Renew the existing device session")
        return (200, try JSONSerialization.data(withJSONObject: ["access_token": "fixture-access", "user_id": me]))
      }
      expect(request.url!.path == "/api/sync/bootstrap" && request.httpMethod == "GET",
             "Refresh must only read tasks, never push changes or launch the app")
      expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access",
             "Task reads must use the renewed access token")
      return (200, try JSONSerialization.data(withJSONObject: ["cursor": "12", "tasks": remote]))
    }
    let now = Date(timeIntervalSince1970: 10_000)
    let snapshot = try await client.fetch(context: context, previous: previous, now: now)
    expect(requests == ["/api/auth/refresh", "/api/sync/bootstrap"], "Two bounded requests per refresh")
    expect(snapshot.openTaskCount == 5, "Hide server deletions and preserve pending local creations")
    expect(snapshot.tasks.first { $0.id == "existing" }?.title == "Updated elsewhere", "Show remote edits")
    expect(snapshot.tasks.first { $0.id == "edited" }?.title == "My offline edit", "Keep unsent local edits")
    expect(!snapshot.tasks.contains { $0.id == "hidden" || $0.id == "deleted" || $0.id == "removed" },
           "Never resurrect local completion, deletion or server purges")
    let existing = snapshot.tasks.first { $0.id == "existing" }!
    expect(existing.databaseId == 11 && existing.visibleSubTasks.first?.databaseId == 21,
           "Keep existing local task and child IDs for actions")
    expect(existing.visibleSubTasks.count == 2 && snapshot.calendarDueDates?.count == 3,
           "Calendar must include due dates beyond the two displayed children")
    expect(snapshot.tasks.first { $0.id == "new" }?.databaseId == nil,
           "New remote tasks must not borrow another task's database ID")
    let both = snapshot.tasks.first { $0.id == "both" }!
    expect(both.needsBothToComplete && both.isPartiallyDone && !both.isDoneByCurrentUser,
           "Preserve which partner completed a shared Both task")
    expect(snapshot.languageCode == "ko" && snapshot.themeMode == "DARK"
           && snapshot.updatedAtMillis == now.timeIntervalSince1970 * 1000,
           "Preserve preferences and timestamp successful fetches")

    remote = (1...12).map { record("many-\($0)", title: String(format: "%02d", $0)) }
    let many = try await client.fetch(context: context, previous: previous)
    expect(many.openTaskCount == 14 && many.tasks.count == 8, "Bound the display while counting all open tasks")

    WidgetSyncProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
    do {
      _ = try await client.fetch(context: context, previous: snapshot)
      fatalError("Offline refresh should fail so the provider keeps its saved snapshot")
    } catch is URLError {}
    WidgetSyncProtocol.handler = { _ in (401, Data()) }
    do {
      _ = try await client.fetch(context: context, previous: snapshot)
      fatalError("Expired sessions must not replace the cache with an empty widget")
    } catch is URLError {}
    print("Native widget direct-sync checks passed")
  }

  static func record(_ id: String, title: String, both: Bool = false,
                     users: [String] = [], deleted: Bool = false) -> [String: Any] {
    var record: [String: Any] = ["id": id, "title": title, "is_completed": false,
      "visibility": both ? "shared" : "private", "shared_completion_mode": both ? "both" : "single",
      "completed_by_user_ids": users, "subtasks": []]
    if deleted { record["deleted_at"] = "2026-10-21T00:00:00Z" }
    return record
  }

  static func local(_ id: String, title: String, pending: Bool, hidden: Bool = false,
                    databaseId: Int? = nil, children: [String: Int] = [:]) -> TodoDesktopWidgetSyncContext.LocalTask {
    .init(task: .init(id: id, databaseId: databaseId, title: title,
                     requiresBothSharedCompletion: false, isPartiallyCompleted: false,
                     isCompletedByCurrentUser: false, dueAtMillis: nil, subTasks: []),
          isPending: pending, isHidden: hidden, subTaskDatabaseIds: children)
  }

  static func expect(_ condition: Bool, _ message: String) { precondition(condition, message) }
}
