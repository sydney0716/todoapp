import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personaltodo/models.dart';
import 'package:personaltodo/screens/settings_screen.dart';
import 'package:personaltodo/settings_controller.dart';
import 'package:personaltodo/settings_store.dart';
import 'package:personaltodo/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('settings selections show current value with folded selectors',
      (tester) async {
    final settings = SettingsController(store: _MemorySettingsStore());
    await settings.init();
    addTearDown(settings.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: SettingsScreen(
          settings: settings,
        ),
      ),
    );

    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Light Mode'), findsOneWidget);
    expect(find.byKey(const ValueKey('theme-mode-menu')), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Korean'), findsOneWidget);
    expect(find.byKey(const ValueKey('language-menu')), findsOneWidget);
    expect(find.text('Completed task retention'), findsOneWidget);
    expect(find.text('1 month'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('completed-retention-menu')), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(SettingsScreen)))
          .appBarTheme
          .backgroundColor,
      plannerLightTopPanel,
    );

    await tester.tap(find.byKey(const ValueKey('theme-mode-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark Mode'));
    await tester.pumpAndSettle();

    expect(settings.themeMode, AppThemeMode.dark);
    expect(find.text('Dark Mode'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(settings.language, AppLanguage.english);
    expect(find.text('English'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('completed-retention-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6 months'));
    await tester.pumpAndSettle();

    expect(
      settings.completedTaskRetentionPolicy,
      CompletedTaskRetentionPolicy.sixMonths,
    );
    expect(find.text('6 months'), findsOneWidget);
  });

  testWidgets('time format setting is a trailing toggle with examples',
      (tester) async {
    final settings = SettingsController(store: _MemorySettingsStore());
    await settings.init();
    addTearDown(settings.close);

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
        home: SettingsScreen(
          settings: settings,
        ),
      ),
    );

    expect(find.text('24시간 형식 사용'), findsOneWidget);
    expect(find.text('오후 1시'), findsOneWidget);
    expect(find.text('13:00'), findsNothing);

    final retentionTop = tester.getTopLeft(find.text('완료된 할 일 보관 기간')).dy;
    final timeTop = tester.getTopLeft(find.text('24시간 형식 사용')).dy;
    final completedTop = tester.getTopLeft(find.text('완료된 할 일 표시')).dy;
    expect(timeTop, greaterThan(retentionTop));
    expect(timeTop, lessThan(completedTop));

    final timeSwitchRight = tester.getTopRight(find.byType(Switch).at(0)).dx;
    final completedSwitchRight =
        tester.getTopRight(find.byType(Switch).at(1)).dx;
    final titleRight = tester.getTopRight(find.text('24시간 형식 사용')).dx;
    expect(timeSwitchRight, greaterThan(titleRight));
    expect(timeSwitchRight, closeTo(completedSwitchRight, 1));

    final timeSwitch = tester.widget<Switch>(find.byType(Switch).at(0));
    final completedSwitch = tester.widget<Switch>(find.byType(Switch).at(1));
    expect(find.byType(SwitchListTile), findsNothing);
    expect(
      timeSwitch.overlayColor?.resolve({WidgetState.hovered}),
      Colors.transparent,
    );
    expect(
      completedSwitch.overlayColor?.resolve({WidgetState.hovered}),
      Colors.transparent,
    );
    expect(
      timeSwitch.thumbColor?.resolve({WidgetState.hovered}),
      timeSwitch.thumbColor?.resolve({}),
    );
    expect(
      timeSwitch.thumbColor?.resolve({
        WidgetState.selected,
        WidgetState.hovered,
      }),
      timeSwitch.thumbColor?.resolve({WidgetState.selected}),
    );
    expect(
      completedSwitch.thumbColor?.resolve({WidgetState.hovered}),
      completedSwitch.thumbColor?.resolve({}),
    );
    expect(
      completedSwitch.thumbColor?.resolve({
        WidgetState.selected,
        WidgetState.hovered,
      }),
      completedSwitch.thumbColor?.resolve({WidgetState.selected}),
    );
    expect(
      timeSwitch.trackColor?.resolve({WidgetState.hovered}),
      timeSwitch.trackColor?.resolve({}),
    );
    expect(
      timeSwitch.trackColor?.resolve({
        WidgetState.selected,
        WidgetState.hovered,
      }),
      timeSwitch.trackColor?.resolve({WidgetState.selected}),
    );

    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(settings.timeFormat, AppTimeFormat.twentyFourHour);
    expect(find.text('오후 1시'), findsNothing);
    expect(find.text('13:00'), findsOneWidget);
  });
}

class _MemorySettingsStore extends SettingsStore {
  final _values = <String, String>{};

  @override
  Future<void> init() async {}

  @override
  Future<void> close() async {}

  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);

  @override
  Future<bool?> getBool(String key) async {
    final value = _values[key];
    if (value == null) return null;
    return value == 'true';
  }

  @override
  Future<int?> getInt(String key) async {
    final value = _values[key];
    if (value == null) return null;
    return int.tryParse(value);
  }

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> setBool(String key, bool value) async {
    _values[key] = value.toString();
  }

  @override
  Future<void> setInt(String key, int value) async {
    _values[key] = value.toString();
  }

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }
}
