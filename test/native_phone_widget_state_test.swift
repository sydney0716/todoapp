import Foundation

@main
struct PhoneWidgetStateTest {
  static func main() {
    let single = task(1)
    let snapshot = TodoPhoneWidgetSnapshot(languageCode: "ko", themeMode: "LIGHT", openTaskCount: 4, tasks: [single])
    let completed = snapshot.completing(taskId: 1, completed: true)
    assert(completed.tasks.isEmpty && completed.openTaskCount == 3)
    assert(completed.completing(taskId: 1, completed: true).openTaskCount == 3)
    assert(snapshot.tasks.count == 1)

    let both = TodoPhoneWidgetSnapshot(languageCode: "en", themeMode: "DARK", openTaskCount: 1, tasks: [task(2, both: true)])
    let half = both.completing(taskId: 2, completed: true)
    assert(half.tasks.count == 1 && half.tasks[0].isPartiallyCompleted == true)
    assert(half.completing(taskId: 2, completed: true).tasks.count == 1)
    assert(half.completing(taskId: 2, completed: false).tasks[0].isPartiallyCompleted == false)

    let partner = TodoPhoneWidgetSnapshot(languageCode: "ko", themeMode: "LIGHT", openTaskCount: 1, tasks: [task(3, both: true, partial: true)])
    assert(partner.completing(taskId: 3, completed: true).tasks.isEmpty)
    print("iPhone widget state checks passed.")
  }

  static func task(_ id: Int, both: Bool = false, partial: Bool = false) -> TodoPhoneWidgetTask {
    TodoPhoneWidgetTask(id: String(id), databaseId: id, title: "Task", requiresBothSharedCompletion: both,
                        isPartiallyCompleted: partial, isCompletedByCurrentUser: false)
  }
}
