import Foundation

struct TodoDesktopWidgetSubTask: Codable, Identifiable {
  let id: String
  let databaseId: Int?
  let title: String
  let dueAtMillis: Double?
}

struct TodoDesktopWidgetTask: Codable, Identifiable {
  let id: String
  let databaseId: Int?
  let title: String
  let requiresBothSharedCompletion: Bool?
  var isPartiallyCompleted: Bool?
  var isCompletedByCurrentUser: Bool?
  let dueAtMillis: Double?
  var subTasks: [TodoDesktopWidgetSubTask]?

  var visibleSubTasks: [TodoDesktopWidgetSubTask] {
    subTasks ?? []
  }

  var needsBothToComplete: Bool {
    requiresBothSharedCompletion ?? false
  }

  var isPartiallyDone: Bool {
    isPartiallyCompleted ?? false
  }

  var isDoneByCurrentUser: Bool {
    isCompletedByCurrentUser ?? isPartiallyDone
  }
}

struct TodoDesktopWidgetSnapshot: Codable {
  let updatedAtMillis: Double?
  let languageCode: String?
  let themeMode: String?
  var openTaskCount: Int
  let calendarDueDates: [Double]?
  var tasks: [TodoDesktopWidgetTask]

  static let empty = TodoDesktopWidgetSnapshot(
    updatedAtMillis: nil,
    languageCode: nil,
    themeMode: nil,
    openTaskCount: 0,
    calendarDueDates: nil,
    tasks: []
  )

  static let preview = TodoDesktopWidgetSnapshot(
    updatedAtMillis: nil,
    languageCode: "ko",
    themeMode: "LIGHT",
    openTaskCount: 3,
    calendarDueDates: [
      Date().timeIntervalSince1970 * 1000,
      Date().addingTimeInterval(86400).timeIntervalSince1970 * 1000,
    ],
    tasks: [
      TodoDesktopWidgetTask(
        id: "preview-1",
        databaseId: 1,
        title: "Reply to apartment email",
        requiresBothSharedCompletion: false,
        isPartiallyCompleted: false,
        isCompletedByCurrentUser: false,
        dueAtMillis: Date().timeIntervalSince1970 * 1000,
        subTasks: [
          TodoDesktopWidgetSubTask(
            id: "preview-subtask-1",
            databaseId: 11,
            title: "Send confirmation reply",
            dueAtMillis: nil
          ),
        ]
      ),
      TodoDesktopWidgetTask(
        id: "preview-2",
        databaseId: 2,
        title: "Review today's tasks",
        requiresBothSharedCompletion: false,
        isPartiallyCompleted: false,
        isCompletedByCurrentUser: false,
        dueAtMillis: Date().addingTimeInterval(86400).timeIntervalSince1970 * 1000,
        subTasks: []
      ),
    ]
  )
}

struct TodoDesktopWidgetAction: Codable {
  let id: String
  let type: String
  let taskId: Int
  let subTaskId: Int?
  let isCompleted: Bool?
  let createdAtMillis: Double
}

extension TodoDesktopWidgetSnapshot {
  // Preview durable, unacknowledged changes without overwriting the app's snapshot.
  func applying(_ actions: [TodoDesktopWidgetAction]) -> TodoDesktopWidgetSnapshot {
    var completionStates: [Int: Bool] = [:]
    var completedSubTasks: [Int: Set<Int>] = [:]
    for action in actions.sorted(by: { $0.createdAtMillis < $1.createdAtMillis }) {
      if action.type == "set_task_completion", let completed = action.isCompleted {
        completionStates[action.taskId] = completed
      } else if action.type == "complete_subtask", let subTaskId = action.subTaskId {
        completedSubTasks[action.taskId, default: []].insert(subTaskId)
      }
    }

    var snapshot = self
    var removedCount = 0
    snapshot.tasks = tasks.compactMap { original in
      var task = original
      if let taskId = task.databaseId, let completed = completionStates[taskId] {
        if task.needsBothToComplete {
          let partnerCompleted = task.isPartiallyDone && !task.isDoneByCurrentUser
          if completed && partnerCompleted {
            removedCount += 1
            return nil
          }
          task.isCompletedByCurrentUser = completed
          task.isPartiallyCompleted = completed || partnerCompleted
        } else if completed {
          removedCount += 1
          return nil
        }
      }
      if let taskId = task.databaseId, let children = completedSubTasks[taskId] {
        task.subTasks = task.visibleSubTasks.filter { child in
          guard let id = child.databaseId else { return true }
          return !children.contains(id)
        }
      }
      return task
    }
    snapshot.openTaskCount = max(0, openTaskCount - removedCount)
    return snapshot
  }
}
