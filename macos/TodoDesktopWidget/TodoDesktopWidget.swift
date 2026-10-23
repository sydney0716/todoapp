import AppIntents
import SwiftUI
import WidgetKit

private let widgetModeDefaultsKey = "todo_widget_mode"
private let toggleWidgetKind = "TodoDesktopTasksWidget"
private let todoOnlyWidgetKind = "TodoDesktopTodoOnlyWidget"
private let calendarOnlyWidgetKind = "TodoDesktopCalendarOnlyWidget"

enum TodoDesktopWidgetMode: String {
  case todo
  case calendar

  var next: TodoDesktopWidgetMode {
    switch self {
    case .todo:
      return .calendar
    case .calendar:
      return .todo
    }
  }

  var toggleIconName: String {
    switch self {
    case .todo:
      return "calendar"
    case .calendar:
      return "checklist"
    }
  }
}

struct TodoDesktopWidgetEntry: TimelineEntry {
  let date: Date
  let snapshot: TodoDesktopWidgetSnapshot
  let mode: TodoDesktopWidgetMode
  let showsModeToggle: Bool
}

private struct TodoDesktopVisibleTaskBlock: Identifiable {
  let task: TodoDesktopWidgetTask
  let subTasks: [TodoDesktopWidgetSubTask]

  var id: String {
    task.id
  }
}

enum TodoDesktopWidgetModeSource {
  case saved
  case fixed(TodoDesktopWidgetMode)

  var mode: TodoDesktopWidgetMode {
    switch self {
    case .saved:
      return TodoDesktopWidgetStore.loadMode()
    case let .fixed(mode):
      return mode
    }
  }

  var showsModeToggle: Bool {
    switch self {
    case .saved:
      return true
    case .fixed:
      return false
    }
  }
}

struct TodoDesktopWidgetProvider: TimelineProvider {
  private let modeSource: TodoDesktopWidgetModeSource

  init(modeSource: TodoDesktopWidgetModeSource = .saved) {
    self.modeSource = modeSource
  }

  func placeholder(in context: Context) -> TodoDesktopWidgetEntry {
    entry(date: Date(), snapshot: .preview)
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (TodoDesktopWidgetEntry) -> Void
  ) {
    completion(
      entry(date: Date(), snapshot: TodoDesktopWidgetStore.load())
    )
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<TodoDesktopWidgetEntry>) -> Void
  ) {
    let now = Date()
    let nextRefresh = now.addingTimeInterval(TodoDesktopWidgetSnapshot.refreshInterval)

    // Render the cached snapshot and durable checkbox intents first. All
    // network work belongs to NSURLSession, never this timeline completion.
    completion(Timeline(entries: [entry(date: now, snapshot: TodoDesktopWidgetStore.load())], policy: .after(nextRefresh)))
    if !context.isPreview {
      Task { @MainActor in TodoDesktopWidgetActionStore.scheduleSync() }
    }
  }

  private func entry(
    date: Date,
    snapshot: TodoDesktopWidgetSnapshot
  ) -> TodoDesktopWidgetEntry {
    TodoDesktopWidgetEntry(
      date: date,
      snapshot: snapshot,
      mode: modeSource.mode,
      showsModeToggle: modeSource.showsModeToggle
    )
  }
}

struct ToggleWidgetModeIntent: AppIntent {
  static var title: LocalizedStringResource = "Toggle Widget View"

  @Parameter(title: "Mode")
  var mode: String

  init() {}

  init(mode: TodoDesktopWidgetMode) {
    self.mode = mode.rawValue
  }

  func perform() async throws -> some IntentResult {
    if let nextMode = TodoDesktopWidgetMode(rawValue: mode) {
      TodoDesktopWidgetStore.setMode(nextMode)
      WidgetCenter.shared.reloadTimelines(ofKind: toggleWidgetKind)
    }
    return .result()
  }
}

private enum TodoDesktopWidgetStore {
  static func load() -> TodoDesktopWidgetSnapshot {
    let pending = TodoDesktopWidgetActionStore.pendingActions()
    return (loadFromFile() ?? .empty).applying(pending)
  }

  static func loadMode() -> TodoDesktopWidgetMode {
    guard
      let rawValue = UserDefaults(suiteName: TodoDesktopWidgetFiles.appGroupId)?
        .string(forKey: widgetModeDefaultsKey),
      let mode = TodoDesktopWidgetMode(rawValue: rawValue)
    else {
      return .todo
    }

    return mode
  }

  static func setMode(_ mode: TodoDesktopWidgetMode) {
    guard let defaults = UserDefaults(suiteName: TodoDesktopWidgetFiles.appGroupId) else {
      return
    }

    defaults.set(mode.rawValue, forKey: widgetModeDefaultsKey)
    defaults.synchronize()
  }

  private static func loadFromFile() -> TodoDesktopWidgetSnapshot? {
    guard let snapshotUrl = TodoDesktopWidgetFiles.snapshotURL,
          let data = try? Data(contentsOf: snapshotUrl) else {
      return nil
    }

    return try? JSONDecoder().decode(TodoDesktopWidgetSnapshot.self, from: data)
  }

}

private enum TodoDesktopWidgetTheme {
  static let lightBackground = Color(red: 246 / 255, green: 234 / 255, blue: 216 / 255)
  static let lightSurface = Color(red: 255 / 255, green: 252 / 255, blue: 245 / 255)
  static let lightKey = Color(red: 139 / 255, green: 94 / 255, blue: 52 / 255)
  static let lightSub = Color(red: 45 / 255, green: 42 / 255, blue: 38 / 255)

  static let darkBackground = Color(red: 31 / 255, green: 27 / 255, blue: 23 / 255)
  static let darkKey = Color(red: 214 / 255, green: 176 / 255, blue: 124 / 255)
  static let darkSub = Color(red: 237 / 255, green: 226 / 255, blue: 209 / 255)
}

private struct TodoDesktopCheckboxStyle: ToggleStyle {
  let size: CGFloat
  let lineWidth: CGFloat
  let color: Color
  let partnerCompleted: Bool?
  let isDark: Bool

  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      TodoDesktopCheckbox(
        size: size, lineWidth: lineWidth, color: color,
        isChecked: configuration.isOn && (partnerCompleted ?? true),
        isPartiallyCompleted: partnerCompleted.map { $0 != configuration.isOn } ?? false,
        isDark: isDark
      )
    }
    .buttonStyle(.plain)
  }
}

private struct TodoDesktopCheckbox: View {
  let size: CGFloat
  let lineWidth: CGFloat
  let color: Color
  let isChecked: Bool
  let isPartiallyCompleted: Bool
  let isDark: Bool

  var body: some View {
    let cornerRadius = size / 6
    ZStack(alignment: .topLeading) {
      if isChecked {
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(color)
      }
      if isPartiallyCompleted {
        Rectangle()
          .fill(color)
          .frame(width: size * 0.5, height: size)
      }
      RoundedRectangle(cornerRadius: cornerRadius)
        .strokeBorder(color, lineWidth: lineWidth)
      if isChecked {
        // Match the app's Material check icon (16 points inside an 18-point box).
        Path { path in
          let scale = size / 27
          path.move(to: CGPoint(x: 9 * scale, y: 16.17 * scale))
          path.addLine(to: CGPoint(x: 4.83 * scale, y: 12 * scale))
          path.addLine(to: CGPoint(x: 3.41 * scale, y: 13.41 * scale))
          path.addLine(to: CGPoint(x: 9 * scale, y: 19 * scale))
          path.addLine(to: CGPoint(x: 21 * scale, y: 7 * scale))
          path.addLine(to: CGPoint(x: 19.59 * scale, y: 5.59 * scale))
          path.closeSubpath()
        }
        .fill(isDark ? TodoDesktopWidgetTheme.darkBackground : TodoDesktopWidgetTheme.lightSurface)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    .frame(width: size, height: size)
    .padding(.top, 2)
    .padding(.leading, 2)
    .frame(width: size + 4, height: size + 4, alignment: .topTrailing)
  }
}

struct TodoDesktopWidgetView: View {
  let entry: TodoDesktopWidgetEntry

  @Environment(\.colorScheme) private var systemColorScheme

  var body: some View {
    ZStack(alignment: .topLeading) {
      widgetBackground
        .ignoresSafeArea()

      content
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(widgetBackgroundColor)
    .widgetAccentable(false)
    .tint(widgetAccentColor)
    .environment(\.colorScheme, resolvedColorScheme)
    .widgetURL(URL(string: "personaltodo://open"))
    .containerBackground(for: .widget) {
      widgetBackground
        .ignoresSafeArea()
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 8) {
      header
        .layoutPriority(1)

      if entry.mode == .calendar {
        calendarView
      } else if entry.snapshot.tasks.isEmpty {
        Spacer(minLength: 4)
        Text(noOpenTasksText)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(widgetSecondaryTextColor)
          .padding(.horizontal, todoContentHorizontalInset)
        Spacer()
      } else {
        taskList
      }
    }
    .padding(EdgeInsets(top: 10, leading: 8, bottom: 8, trailing: 8))
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(headerTitle)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(widgetTextColor)
        .lineLimit(1)
      Spacer()
      if entry.showsModeToggle {
        Button(intent: ToggleWidgetModeIntent(mode: entry.mode.next)) {
          Image(systemName: entry.mode.toggleIconName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(widgetTextColor)
            .frame(width: 24, height: 22)
          .background(
            RoundedRectangle(cornerRadius: 6)
              .fill(widgetAccentColor.opacity(isDarkWidget ? 0.18 : 0.12))
          )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(toggleAccessibilityLabel)
      }
    }
  }

  private var taskList: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(visibleTaskBlocks) { block in
        taskBlock(block)
          .transition(.opacity)
      }

      if visibleTaskBlocks.count < sortedTasks.count {
        Text(moreTasksText)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(widgetAccentColor)
      }
    }
    .padding(.horizontal, todoContentHorizontalInset)
    .frame(maxHeight: maxTaskListHeight, alignment: .top)
    .clipped()
    .animation(.easeOut(duration: 0.18), value: visibleTaskBlocks.map(\.id))
  }

  private func taskBlock(_ block: TodoDesktopVisibleTaskBlock) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      taskRow(block.task)

      ForEach(block.subTasks) { subTask in
        subTaskRow(subTask, task: block.task)
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.18), value: block.subTasks.map(\.id))
  }

  private func taskRow(_ task: TodoDesktopWidgetTask) -> some View {
    HStack(alignment: .top, spacing: 7) {
      taskCheckbox(for: task)

      Link(destination: openTaskUrl(for: task)) {
        HStack(alignment: .top) {
          Text(task.title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(widgetTextColor)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

          if let dueText = dueDateText(for: task.dueAtMillis) {
            Text(dueText)
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(widgetAccentColor)
              .lineLimit(1)
              .fixedSize(horizontal: true, vertical: false)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  private func subTaskRow(
    _ subTask: TodoDesktopWidgetSubTask,
    task: TodoDesktopWidgetTask
  ) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Spacer()
        .frame(width: 18)

      subTaskCheckbox(for: subTask, task: task)

      Link(destination: openTaskUrl(for: task)) {
        HStack(alignment: .top) {
          Text(subTask.title)
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(widgetSecondaryTextColor)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

          if let dueText = dueDateText(for: subTask.dueAtMillis) {
            Text(dueText)
              .font(.system(size: 9, weight: .regular))
              .foregroundStyle(widgetAccentColor)
              .lineLimit(1)
              .fixedSize(horizontal: true, vertical: false)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  private func openTaskUrl(for task: TodoDesktopWidgetTask) -> URL {
    if UUID(uuidString: task.id) != nil {
      return URL(string: "personaltodo://open-task?taskSyncId=\(task.id)")!
    }
    guard let id = task.databaseId, id > 0 else { return URL(string: "personaltodo://open")! }
    return URL(string: "personaltodo://open-task?taskId=\(id)")!
  }

  @ViewBuilder
  private func taskCheckbox(for task: TodoDesktopWidgetTask) -> some View {
    if task.databaseId != nil || UUID(uuidString: task.id) != nil {
      Toggle(isOn: task.isDoneByCurrentUser, intent: CompleteTaskIntent(
        taskId: task.databaseId ?? 0, isCompleted: !task.isDoneByCurrentUser,
        taskSyncId: UUID(uuidString: task.id) != nil ? task.id : nil
      )) {
        Text(task.title)
      }
      .toggleStyle(TodoDesktopCheckboxStyle(
        size: 14, lineWidth: 1.8, color: widgetAccentColor,
        partnerCompleted: task.needsBothToComplete
          ? task.isPartiallyDone && !task.isDoneByCurrentUser : nil,
        isDark: isDarkWidget
      ))
    } else {
      checkboxImage(
        size: 14,
        lineWidth: 1.8,
        isPartiallyCompleted: task.isPartiallyDone
      )
    }
  }

  @ViewBuilder
  private func subTaskCheckbox(
    for subTask: TodoDesktopWidgetSubTask,
    task: TodoDesktopWidgetTask
  ) -> some View {
    if (task.databaseId != nil && subTask.databaseId != nil)
        || (UUID(uuidString: task.id) != nil && UUID(uuidString: subTask.id) != nil) {
      Toggle(isOn: false, intent: CompleteSubTaskIntent(
        taskId: task.databaseId ?? 0, subTaskId: subTask.databaseId ?? 0,
        taskSyncId: UUID(uuidString: task.id) != nil ? task.id : nil,
        subTaskSyncId: UUID(uuidString: subTask.id) != nil ? subTask.id : nil
      )) {
        Text(subTask.title)
      }
      .toggleStyle(TodoDesktopCheckboxStyle(
        size: 11, lineWidth: 1.4, color: widgetAccentColor,
        partnerCompleted: nil, isDark: isDarkWidget
      ))
    } else {
      checkboxImage(size: 11, lineWidth: 1.4)
    }
  }

  private func checkboxImage(
    size: CGFloat,
    lineWidth: CGFloat,
    isPartiallyCompleted: Bool = false
  ) -> some View {
    TodoDesktopCheckbox(
      size: size, lineWidth: lineWidth, color: widgetAccentColor,
      isChecked: false, isPartiallyCompleted: isPartiallyCompleted,
      isDark: isDarkWidget
    )
  }

  private var sortedTasks: [TodoDesktopWidgetTask] {
    entry.snapshot.tasks.sorted { first, second in
      switch (first.dueAtMillis, second.dueAtMillis) {
      case let (firstDue?, secondDue?):
        if firstDue != secondDue {
          return firstDue < secondDue
        }
      case (.some, .none):
        return true
      case (.none, .some):
        return false
      case (.none, .none):
        break
      }

      return first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
    }
  }

  private var visibleTaskBlocks: [TodoDesktopVisibleTaskBlock] {
    var remainingRows = maxVisibleContentRows
    var blocks: [TodoDesktopVisibleTaskBlock] = []

    for task in sortedTasks {
      guard remainingRows > 0 else {
        break
      }

      let subTaskLimit = max(0, min(2, remainingRows - 1))
      let subTasks = Array(task.visibleSubTasks.prefix(subTaskLimit))
      blocks.append(TodoDesktopVisibleTaskBlock(task: task, subTasks: subTasks))
      remainingRows -= 1 + subTasks.count
    }

    return blocks
  }

  private var maxVisibleContentRows: Int {
    11
  }

  private var maxTaskListHeight: CGFloat {
    276
  }

  private var todoContentHorizontalInset: CGFloat {
    6
  }

  private var headerTitle: String {
    switch entry.mode {
    case .todo:
      return isKorean ? "할 일" : "Todo"
    case .calendar:
      return monthYearText(for: entry.date)
    }
  }

  private var noOpenTasksText: String {
    isKorean ? "열린 할 일이 없습니다" : "No open tasks"
  }

  private var moreTasksText: String {
    isKorean ? "더 많은 할 일" : "More tasks"
  }

  private var toggleAccessibilityLabel: String {
    switch entry.mode {
    case .todo:
      return isKorean ? "달력 보기" : "Calendar"
    case .calendar:
      return isKorean ? "할 일 보기" : "Todo"
    }
  }

  private var isKorean: Bool {
    entry.snapshot.languageCode == "ko"
  }

  private var resolvedColorScheme: ColorScheme {
    isDarkWidget ? .dark : .light
  }

  private var isDarkWidget: Bool {
    switch entry.snapshot.themeMode?.uppercased() {
    case "DARK":
      return true
    case "FOLLOW_SYSTEM":
      return systemColorScheme == .dark
    default:
      return false
    }
  }

  private var widgetBackgroundColor: Color {
    if isDarkWidget {
      return TodoDesktopWidgetTheme.darkBackground
    }

    return TodoDesktopWidgetTheme.lightBackground
  }

  private var widgetTextColor: Color {
    if isDarkWidget {
      return TodoDesktopWidgetTheme.darkSub
    }

    return TodoDesktopWidgetTheme.lightSub
  }

  private var widgetSecondaryTextColor: Color {
    widgetTextColor.opacity(isDarkWidget ? 0.70 : 0.64)
  }

  private var widgetAccentColor: Color {
    if isDarkWidget {
      return TodoDesktopWidgetTheme.darkKey
    }

    return TodoDesktopWidgetTheme.lightKey
  }

  private var widgetTodayTextColor: Color {
    if isDarkWidget {
      return TodoDesktopWidgetTheme.darkBackground
    }

    return TodoDesktopWidgetTheme.lightSurface
  }

  @ViewBuilder
  private var widgetBackground: some View {
    ZStack {
      widgetBackgroundColor
      paperBackgroundImage
    }
  }

  @ViewBuilder
  private var paperBackgroundImage: some View {
    if !isDarkWidget {
      if #available(macOS 15.0, *) {
        Image("PaperBackground")
          .renderingMode(.original)
          .resizable(resizingMode: .tile)
          .widgetAccentedRenderingMode(.fullColor)
          .opacity(0.52)
      } else {
        Image("PaperBackground")
          .renderingMode(.original)
          .resizable(resizingMode: .tile)
          .opacity(0.52)
      }
    }
  }

  private var calendarView: some View {
    VStack(alignment: .leading, spacing: calendarGridGap) {
      HStack(spacing: 0) {
        ForEach(Array(calendarWeekdayLabels.enumerated()), id: \.offset) { _, weekday in
          Text(weekday)
            .font(.system(size: calendarWeekdayFontSize, weight: .semibold))
            .foregroundStyle(widgetSecondaryTextColor)
            .frame(maxWidth: .infinity)
        }
      }
      .frame(height: calendarWeekdayHeight)

      LazyVGrid(columns: calendarGridColumns, spacing: calendarRowGap) {
        ForEach(Array(calendarCells.enumerated()), id: \.offset) { _, date in
          if let date {
            Link(destination: createTaskUrl(for: date)) {
              calendarDayCell(date)
            }
            .buttonStyle(.plain)
          } else {
            Color.clear
              .frame(height: calendarDaySlotHeight)
          }
        }
      }
    }
    .frame(maxHeight: calendarMaxHeight, alignment: .top)
    .clipped()
  }

  private func calendarDayCell(_ date: Date) -> some View {
    let calendar = Calendar.current
    let day = calendar.component(.day, from: date)
    let isToday = calendar.isDateInToday(date)
    let hasTask = taskDueDates.contains(calendar.startOfDay(for: date))

    return ZStack {
      if isToday {
        Circle()
          .fill(widgetAccentColor)
      } else if hasTask {
        Circle()
          .fill(widgetAccentColor.opacity(isDarkWidget ? 0.18 : 0.14))
      }

      Text("\(day)")
        .font(.system(size: calendarDayFontSize, weight: isToday ? .semibold : .medium))
        .foregroundColor(isToday ? widgetTodayTextColor : widgetTextColor)
    }
    .frame(width: calendarDayCircleSize, height: calendarDayCircleSize)
    .frame(maxWidth: .infinity)
    .frame(height: calendarDaySlotHeight)
  }

  private var calendarCells: [Date?] {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month], from: entry.date)
    guard
      let firstDay = calendar.date(from: components),
      let dayRange = calendar.range(of: .day, in: .month, for: firstDay)
    else {
      return Array(repeating: nil, count: 42)
    }

    var cells: [Date?] = Array(
      repeating: nil,
      count: calendar.component(.weekday, from: firstDay) - 1
    )

    for day in dayRange {
      cells.append(calendar.date(byAdding: .day, value: day - 1, to: firstDay))
    }

    while cells.count % 7 != 0 {
      cells.append(nil)
    }

    return cells
  }

  private var calendarRowCount: Int {
    max(1, calendarCells.count / 7)
  }

  private var taskDueDates: Set<Date> {
    if let calendarDueDates = entry.snapshot.calendarDueDates {
      return Set(
        calendarDueDates.map { dueAtMillis in
          Calendar.current.startOfDay(
            for: Date(timeIntervalSince1970: dueAtMillis / 1000)
          )
        }
      )
    }

    return Set(
      entry.snapshot.tasks.flatMap { task -> [Date] in
        var dates: [Date] = []
        if let dueAtMillis = task.dueAtMillis {
          dates.append(
            Calendar.current.startOfDay(
              for: Date(timeIntervalSince1970: dueAtMillis / 1000)
            )
          )
        }
        dates.append(
          contentsOf: task.visibleSubTasks.compactMap { subTask in
            guard let dueAtMillis = subTask.dueAtMillis else {
              return nil
            }

            return Calendar.current.startOfDay(
              for: Date(timeIntervalSince1970: dueAtMillis / 1000)
            )
          }
        )
        return dates
      }
    )
  }

  private var calendarGridColumns: [GridItem] {
    Array(
      repeating: GridItem(.flexible(minimum: 0), spacing: 0),
      count: 7
    )
  }

  private var calendarWeekdayLabels: [String] {
    if isKorean {
      return ["일", "월", "화", "수", "목", "금", "토"]
    }

    return ["S", "M", "T", "W", "T", "F", "S"]
  }

  private var calendarGridGap: CGFloat {
    8
  }

  private var calendarRowGap: CGFloat {
    7
  }

  private var calendarWeekdayFontSize: CGFloat {
    10
  }

  private var calendarWeekdayHeight: CGFloat {
    14
  }

  private var calendarDayFontSize: CGFloat {
    max(8, min(13, calendarDayCircleSize * 0.44))
  }

  private var calendarDaySlotHeight: CGFloat {
    let rows = CGFloat(calendarRowCount)
    let rowGaps = max(0, rows - 1) * calendarRowGap
    let availableHeight = calendarMaxHeight
      - calendarWeekdayHeight
      - calendarGridGap
      - rowGaps

    return max(12, availableHeight / rows)
  }

  private var calendarDayCircleSize: CGFloat {
    min(30, calendarDaySlotHeight)
  }

  private var calendarMaxHeight: CGFloat {
    282
  }

  private func dueAtMillis(for date: Date) -> Int {
    let startOfDay = Calendar.current.startOfDay(for: date)
    return Int(startOfDay.timeIntervalSince1970 * 1000)
  }

  private func createTaskUrl(for date: Date) -> URL {
    let dueAtMillis = dueAtMillis(for: date)
    var components = URLComponents()
    components.scheme = "personaltodo"
    components.host = "create-task"
    components.queryItems = [
      URLQueryItem(name: "dueAtMillis", value: "\(dueAtMillis)"),
    ]

    return components.url ?? URL(string: "personaltodo://create-task")!
  }

  private func dueDateText(for dueAtMillis: Double?) -> String? {
    guard let dueAtMillis else {
      return nil
    }

    let dueDate = Date(timeIntervalSince1970: dueAtMillis / 1000)
    let calendar = Calendar.current

    if calendar.isDateInToday(dueDate) {
      return isKorean ? "오늘" : "Today"
    }

    if calendar.isDateInTomorrow(dueDate) {
      return isKorean ? "내일" : "Tomorrow"
    }

    if isKorean {
      let month = calendar.component(.month, from: dueDate)
      let day = calendar.component(.day, from: dueDate)
      return "\(month)월 \(day)일"
    }

    return TodoDesktopWidgetDateFormatter.monthDay.string(from: dueDate)
  }

  private func monthYearText(for date: Date) -> String {
    if isKorean {
      let calendar = Calendar.current
      let year = calendar.component(.year, from: date)
      let month = calendar.component(.month, from: date)
      return "\(year)년 \(month)월"
    }

    return TodoDesktopWidgetDateFormatter.monthYear.string(from: date)
  }
}

private enum TodoDesktopWidgetDateFormatter {
  static let monthDay: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter
  }()

  static let monthYear: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM yyyy"
    return formatter
  }()
}

struct TodoDesktopToggleWidget: Widget {
  let kind = toggleWidgetKind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: TodoDesktopWidgetProvider()) { entry in
      TodoDesktopWidgetView(entry: entry)
    }
    .configurationDisplayName("Todo + Calendar")
    .description("Switches between your open tasks and calendar.")
    .supportedFamilies([.systemLarge])
    .containerBackgroundRemovable(false)
    .onBackgroundURLSessionEvents(matching: TodoDesktopWidgetUpload.identifier) { identifier, completion in
      TodoDesktopWidgetUpload.handleEvents(identifier, completion: completion)
    }
  }
}

struct TodoDesktopTodoOnlyWidget: Widget {
  let kind = todoOnlyWidgetKind

  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: kind,
      provider: TodoDesktopWidgetProvider(modeSource: .fixed(.todo))
    ) { entry in
      TodoDesktopWidgetView(entry: entry)
    }
    .configurationDisplayName("Todo Only")
    .description("Shows your open tasks on the desktop.")
    .supportedFamilies([.systemLarge])
    .containerBackgroundRemovable(false)
    .onBackgroundURLSessionEvents(matching: TodoDesktopWidgetUpload.identifier) { identifier, completion in
      TodoDesktopWidgetUpload.handleEvents(identifier, completion: completion)
    }
  }
}

struct TodoDesktopCalendarOnlyWidget: Widget {
  let kind = calendarOnlyWidgetKind

  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: kind,
      provider: TodoDesktopWidgetProvider(modeSource: .fixed(.calendar))
    ) { entry in
      TodoDesktopWidgetView(entry: entry)
    }
    .configurationDisplayName("Calendar Only")
    .description("Shows your task calendar on the desktop.")
    .supportedFamilies([.systemLarge])
    .containerBackgroundRemovable(false)
    .onBackgroundURLSessionEvents(matching: TodoDesktopWidgetUpload.identifier) { identifier, completion in
      TodoDesktopWidgetUpload.handleEvents(identifier, completion: completion)
    }
  }
}

@main
struct TodoDesktopWidgetBundle: WidgetBundle {
  var body: some Widget {
    TodoDesktopToggleWidget()
    TodoDesktopTodoOnlyWidget()
    TodoDesktopCalendarOnlyWidget()
  }
}
