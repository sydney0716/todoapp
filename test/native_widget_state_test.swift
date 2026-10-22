import Foundation

// Run with TodoDesktopWidgetState.swift; these checks never access app data.
@main
struct NativeWidgetStateTest {
  static func main() {
    let single = task(1)
    let source = snapshot([single], count: 5)
    let now = Date(timeIntervalSince1970: 10_000)
    expect(source.needsBackgroundRefresh(at: now, lastAttempt: nil),
           "A missing snapshot must request a background refresh")
    expect(!source.needsBackgroundRefresh(at: now, lastAttempt: now.addingTimeInterval(-60)),
           "Timeline reloads must not repeatedly wake the app while offline")
    expect(source.needsBackgroundRefresh(at: now, lastAttempt: now.addingTimeInterval(-7200)),
           "Background refresh must become eligible after two hours")
    let fresh = TodoDesktopWidgetSnapshot(
      updatedAtMillis: now.timeIntervalSince1970 * 1000,
      languageCode: nil, themeMode: nil, openTaskCount: 0, calendarDueDates: nil, tasks: []
    )
    expect(!fresh.needsBackgroundRefresh(at: now, lastAttempt: nil),
           "A recent app snapshot must not wake the app")
    expect(fresh.needsBackgroundRefresh(at: now.addingTimeInterval(7200), lastAttempt: nil),
           "An old app snapshot must fetch changes even when the app was closed")
    let check = action(1, completed: true)
    let checked = source.applying([check, check])
    expect(checked.tasks.isEmpty && checked.openTaskCount == 4,
           "Repeated checks must remove one task and count it once")
    expect(source.tasks.count == 1 && source.openTaskCount == 5,
           "Prediction must leave the original snapshot unchanged")
    expect(source.applying([action(1, completed: false, time: 2), check]).tasks.count == 1,
           "The newest desired state must win even when queue files are unordered")

    let both = snapshot([task(2, both: true)])
    let ownCheck = action(2, completed: true)
    let halfDone = both.applying([ownCheck])
    expect(halfDone.tasks.count == 1 && halfDone.tasks[0].isPartiallyDone
           && halfDone.tasks[0].isDoneByCurrentUser,
           "A Both task must remain visible until the partner also completes it")
    expect(halfDone.applying([ownCheck]).tasks.count == 1,
           "An already reflected action must not infer partner completion")
    expect(!halfDone.applying([action(2, completed: false)]).tasks[0].isPartiallyDone,
           "Unchecking your own half must clear partial completion")

    let partnerDone = snapshot([task(2, both: true, partial: true)])
    expect(partnerDone.applying([ownCheck]).tasks.isEmpty,
           "Checking a partner-completed Both task must remove it")
    let partnerOnly = partnerDone.applying([action(2, completed: false)]).tasks[0]
    expect(partnerOnly.isPartiallyDone && !partnerOnly.isDoneByCurrentUser,
           "Unchecking must preserve the partner's completion")

    let children = [11, 12].map {
      TodoDesktopWidgetSubTask(id: String($0), databaseId: $0, title: "Child", dueAtMillis: nil)
    }
    let childAction = TodoDesktopWidgetAction(
      id: "child", type: "complete_subtask", taskId: 3, subTaskId: 11,
      isCompleted: nil, createdAtMillis: 1
    )
    let parent = snapshot([task(3, children: children)])
    let childCompleted = parent.applying([childAction, childAction])
    expect(childCompleted.tasks[0].visibleSubTasks.map(\.databaseId) == [12]
           && childCompleted.openTaskCount == 1,
           "Completing a child must remove only that child, preserving the parent")

    let remote = TodoDesktopWidgetTask(
      id: "remote-task", databaseId: nil, title: "New on server",
      requiresBothSharedCompletion: false, isPartiallyCompleted: false,
      isCompletedByCurrentUser: false, dueAtMillis: nil,
      subTasks: [.init(id: "remote-child", databaseId: nil, title: "New child", dueAtMillis: nil)]
    )
    let remoteSource = snapshot([remote])
    let remoteCheck = TodoDesktopWidgetAction(
      id: "remote-check", type: "set_task_completion", taskId: 0, subTaskId: nil,
      isCompleted: true, createdAtMillis: 1, taskSyncId: remote.id
    )
    expect(remoteSource.applying([remoteCheck]).tasks.isEmpty,
           "Checking a newly fetched task must update the widget before it has a local ID")
    let remoteChildCheck = TodoDesktopWidgetAction(
      id: "remote-child-check", type: "complete_subtask", taskId: 0, subTaskId: 0,
      isCompleted: nil, createdAtMillis: 1, taskSyncId: remote.id, subTaskSyncId: "remote-child"
    )
    expect(remoteSource.applying([remoteChildCheck]).tasks[0].visibleSubTasks.isEmpty,
           "A newly fetched child must be completable using its stable sync ID")
    let encoded = try! JSONEncoder().encode(remoteCheck)
    expect(try! JSONDecoder().decode(TodoDesktopWidgetAction.self, from: encoded).taskSyncId == remote.id,
           "Stable IDs must survive the durable action queue")
    print("Native widget state checks passed")
  }

  static func task(_ id: Int, both: Bool = false, partial: Bool = false,
                   children: [TodoDesktopWidgetSubTask] = []) -> TodoDesktopWidgetTask {
    TodoDesktopWidgetTask(
      id: String(id), databaseId: id, title: "Task", requiresBothSharedCompletion: both,
      isPartiallyCompleted: partial, isCompletedByCurrentUser: false,
      dueAtMillis: nil, subTasks: children
    )
  }

  static func snapshot(_ tasks: [TodoDesktopWidgetTask], count: Int? = nil)
    -> TodoDesktopWidgetSnapshot {
    TodoDesktopWidgetSnapshot(
      updatedAtMillis: nil, languageCode: "ko", themeMode: "LIGHT",
      openTaskCount: count ?? tasks.count, calendarDueDates: [], tasks: tasks
    )
  }

  static func action(_ id: Int, completed: Bool, time: Double = 1) -> TodoDesktopWidgetAction {
    TodoDesktopWidgetAction(
      id: "\(id)-\(time)", type: "set_task_completion", taskId: id,
      subTaskId: nil, isCompleted: completed, createdAtMillis: time
    )
  }

  static func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
  }
}
