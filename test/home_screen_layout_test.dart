import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personaltodo/models.dart';
import 'package:personaltodo/screens/home_screen.dart';
import 'package:personaltodo/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('calendar due dates include open subtasks', () {
    final dates = calendarDueDatesForTasks([
      TodoTask(
        title: 'Parent without due date',
        subTasks: [
          SubTask(
            title: 'Subtask due',
            dueDateTime: DateTime(2026, 6, 10, 18),
          ),
          SubTask(
            title: 'Completed subtask due',
            isCompleted: true,
            dueDateTime: DateTime(2026, 6, 11),
          ),
        ],
      ),
      TodoTask(
        title: 'Parent due',
        dueDateTime: DateTime(2026, 6, 12, 9),
      ),
    ]);

    expect(dates, {
      DateTime(2026, 6, 10),
      DateTime(2026, 6, 12),
    });
  });

  testWidgets('calendar header expands inline without render overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var monthExpanded = false;
    var scopeVisibility = SyncVisibility.privateItem;
    DateTime? selectedDate;
    final today = DateTime(2026, 5, 29);
    final dueDates = {DateTime(2026, 5, 29)};

    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: SafeArea(
            child: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    CalendarHeader(
                      today: today,
                      dueDates: dueDates,
                      monthExpanded: monthExpanded,
                      scopeVisibility: scopeVisibility,
                      onToggleMonthExpanded: () {
                        setState(() => monthExpanded = !monthExpanded);
                      },
                      onToggleScopeVisibility: () {
                        setState(() {
                          scopeVisibility =
                              scopeVisibility == SyncVisibility.privateItem
                                  ? SyncVisibility.shared
                                  : SyncVisibility.privateItem;
                        });
                      },
                      onDateSelected: (date) {
                        selectedDate = date;
                      },
                    ),
                    const Expanded(child: SizedBox()),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CalendarHeader), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    expect(
      tester
          .widget<Material>(
            find
                .descendant(
                  of: find.byType(CalendarHeader),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color,
      plannerLightTopPanel,
    );
    final taskDateDecoration = tester
        .widget<Container>(find.byKey(ValueKey<DateTime>(today)))
        .decoration;
    expect(taskDateDecoration, isA<BoxDecoration>());
    expect((taskDateDecoration! as BoxDecoration).shape, BoxShape.circle);

    await tester.tap(find.text('29'));
    await tester.pump();
    expect(selectedDate, DateTime(2026, 5, 29));

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pump();
    expect(find.byIcon(Icons.group_outlined), findsOneWidget);

    await tester.drag(
        find.byKey(const ValueKey('week-pager')), const Offset(-320, 0));
    await tester.pumpAndSettle();
    expect(find.text('June 2026'), findsOneWidget);

    await tester.drag(
        find.byKey(const ValueKey('week-pager')), const Offset(320, 0));
    await tester.pumpAndSettle();
    expect(find.text('May 2026'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('May 2026'), findsOneWidget);
    expect(find.text('Sun'), findsOneWidget);
    expect(find.text('Mon'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Sun')).dx,
      lessThan(tester.getTopLeft(find.text('Mon')).dx),
    );

    await tester.drag(
        find.byKey(const ValueKey('month-pager')), const Offset(-320, 0));
    await tester.pumpAndSettle();
    expect(find.text('June 2026'), findsOneWidget);

    await tester.drag(
        find.byKey(const ValueKey('month-pager')), const Offset(320, 0));
    await tester.pumpAndSettle();
    expect(find.text('May 2026'), findsOneWidget);
  });

  testWidgets('calendar header uses Korean locale labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        locale: const Locale('ko'),
        supportedLocales: const [Locale('en'), Locale('ko')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: CalendarHeader(
            today: DateTime(2026, 5, 29),
            dueDates: const {},
            monthExpanded: false,
            onToggleMonthExpanded: () {},
          ),
        ),
      ),
    );

    expect(find.text('2026년 5월'), findsOneWidget);
    expect(find.text('일'), findsOneWidget);
    expect(find.text('월'), findsOneWidget);
    expect(
      tester
          .widget<Container>(
            find.byKey(ValueKey<DateTime>(DateTime(2026, 5, 29))),
          )
          .decoration,
      isNull,
    );
  });

  testWidgets('header menu places completed between trash and settings',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: CalendarHeader(
            today: DateTime(2026, 5, 29),
            dueDates: const {},
            monthExpanded: false,
            onToggleMonthExpanded: () {},
            onMenuSelected: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final trashTop = tester.getTopLeft(find.text('Trash')).dy;
    final completedTop = tester.getTopLeft(find.text('Completed')).dy;
    final settingsTop = tester.getTopLeft(find.text('Settings')).dy;

    expect(completedTop, greaterThan(trashTop));
    expect(completedTop, lessThan(settingsTop));
  });
}
