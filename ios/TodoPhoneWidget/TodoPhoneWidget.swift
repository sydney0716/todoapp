import SwiftUI
import WidgetKit

struct TodoPhoneWidgetEntry: TimelineEntry {
  let date: Date
  let snapshot: TodoPhoneWidgetSnapshot
}

struct TodoPhoneWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> TodoPhoneWidgetEntry {
    TodoPhoneWidgetEntry(date: Date(), snapshot: .empty)
  }

  func getSnapshot(in context: Context, completion: @escaping (TodoPhoneWidgetEntry) -> Void) {
    completion(TodoPhoneWidgetEntry(date: Date(), snapshot: TodoPhoneWidgetStore.load()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<TodoPhoneWidgetEntry>) -> Void) {
    let entry = TodoPhoneWidgetEntry(date: Date(), snapshot: TodoPhoneWidgetStore.load())
    completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(7200))))
  }
}

struct TodoPhoneWidgetView: View {
  let entry: TodoPhoneWidgetEntry
  @Environment(\.widgetFamily) private var family
  @Environment(\.colorScheme) private var systemScheme

  private var korean: Bool { entry.snapshot.languageCode == "ko" }
  private var dark: Bool {
    let mode = entry.snapshot.themeMode
    return mode == "DARK" || (mode == "FOLLOW_SYSTEM" && systemScheme == .dark)
  }
  private var accent: Color {
    dark ? Color(red: 214 / 255, green: 176 / 255, blue: 124 / 255)
      : Color(red: 139 / 255, green: 94 / 255, blue: 52 / 255)
  }
  private var background: Color {
    dark ? Color(red: 31 / 255, green: 27 / 255, blue: 23 / 255)
      : Color(red: 246 / 255, green: 234 / 255, blue: 216 / 255)
  }
  private var limit: Int { family == .systemLarge ? 7 : 3 }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Link(destination: URL(string: "personaltodo://open")!) {
        Text(korean ? "할 일" : "Todo")
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(dark ? .white : .primary)
      }
      if entry.snapshot.tasks.isEmpty {
        Text(korean ? "열린 할 일이 없습니다" : "No open tasks")
          .font(.system(size: 13))
          .foregroundColor(.secondary)
      } else {
        ForEach(Array(entry.snapshot.tasks.prefix(limit))) { task in
          HStack(alignment: .top, spacing: 8) {
            if #available(iOS 17, *), let taskId = task.databaseId {
              Toggle(isOn: task.isCompletedByCurrentUser ?? false,
                     intent: CompletePhoneTaskIntent(taskId: taskId, completed: !(task.isCompletedByCurrentUser ?? false))) {
                Text(task.title)
              }
              .toggleStyle(PhoneTaskCheckboxStyle(
                accent: accent,
                taskTitle: task.title,
                background: dark ? background : Color(red: 1, green: 252 / 255, blue: 245 / 255),
                partnerDone: (task.requiresBothSharedCompletion ?? false)
                  ? ((task.isPartiallyCompleted ?? false) && !(task.isCompletedByCurrentUser ?? false)) : nil
              ))
            } else {
              Link(destination: URL(string: "personaltodo://open")!) {
                Image(systemName: "square").foregroundColor(accent)
              }
            }
            Text(task.title)
              .font(.system(size: 14))
              .lineLimit(1)
              .foregroundColor(dark ? .white : .primary)
          }
        }
        if entry.snapshot.openTaskCount > limit {
          Text(korean ? "더 많은 할 일" : "More tasks")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .modifier(PhoneWidgetBackground(color: background))
    .environment(\.colorScheme, dark ? .dark : .light)
    .widgetURL(URL(string: "personaltodo://open"))
  }
}

private struct PhoneTaskCheckboxStyle: ToggleStyle {
  let accent: Color
  let taskTitle: String
  let background: Color
  let partnerDone: Bool?

  func makeBody(configuration: Configuration) -> some View {
    let checked = configuration.isOn && (partnerDone ?? true)
    let partial = partnerDone.map { $0 != configuration.isOn } ?? false
    Button { configuration.isOn.toggle() } label: {
      ZStack(alignment: .leading) {
        if checked { RoundedRectangle(cornerRadius: 3).fill(accent) }
        if partial { Rectangle().fill(accent).frame(width: 9) }
        RoundedRectangle(cornerRadius: 3).strokeBorder(accent, lineWidth: 1.5)
        if checked {
          Path { path in
            let scale: CGFloat = 18 / 27
            path.move(to: CGPoint(x: 9 * scale, y: 16.17 * scale))
            for point in [(4.83, 12.0), (3.41, 13.41), (9.0, 19.0), (21.0, 7.0), (19.59, 5.59)] {
              path.addLine(to: CGPoint(x: point.0 * scale, y: point.1 * scale))
            }
            path.closeSubpath()
          }.fill(background)
        }
      }
      .frame(width: 18, height: 18)
      .clipShape(RoundedRectangle(cornerRadius: 3))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(taskTitle)
  }
}

private struct PhoneWidgetBackground: ViewModifier {
  let color: Color
  func body(content: Content) -> some View {
    if #available(iOS 17, *) {
      content.containerBackground(color, for: .widget)
    } else {
      content.padding().background(color)
    }
  }
}

@main
struct TodoPhoneWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "TodoPhoneTasksWidget", provider: TodoPhoneWidgetProvider()) { entry in
      TodoPhoneWidgetView(entry: entry)
    }
    .configurationDisplayName("PersonalTodo")
    .description("Your tasks")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
