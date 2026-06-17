import 'package:flutter_test/flutter_test.dart';
import 'package:personaltodo/date_formatting.dart';
import 'package:personaltodo/settings_controller.dart';

void main() {
  test('formats due dates without year and with relative status', () {
    final today = DateTime(2026, 5, 31);

    expect(formatListDueDate(DateTime(2026, 5, 31)), 'May 31');
    expect(formatListDueDate(DateTime(2026, 6, 1)), 'Jun 1');
    expect(
      formatDueDateStatus(DateTime(2026, 5, 31), today: today),
      'Today',
    );
    expect(
      formatDueDateStatus(DateTime(2026, 6, 1), today: today),
      'Tomorrow',
    );
    expect(
      formatDueDateStatus(DateTime(2026, 6, 3), today: today),
      'D-3',
    );
    expect(
      formatDueDateStatus(DateTime(2026, 5, 28), today: today),
      'D+3',
    );
  });

  test('formats Korean due dates and relative status', () {
    final today = DateTime(2026, 5, 31);

    expect(
      formatMonthYear(DateTime(2026, 5, 31), language: AppLanguage.korean),
      '2026년 5월',
    );
    expect(
      formatListDueDate(
        DateTime(2026, 5, 31),
        language: AppLanguage.korean,
      ),
      '5월 31일',
    );
    expect(
      formatDueDateStatus(
        DateTime(2026, 5, 31),
        today: today,
        language: AppLanguage.korean,
      ),
      '오늘',
    );
    expect(
      formatDueDateStatus(
        DateTime(2026, 6, 1),
        today: today,
        language: AppLanguage.korean,
      ),
      '내일',
    );
  });
}
