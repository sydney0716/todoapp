import 'settings_controller.dart';

const _englishMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _englishShortMonthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatMonthYear(
  DateTime date, {
  AppLanguage language = AppLanguage.english,
}) {
  if (language == AppLanguage.korean) return '${date.year}년 ${date.month}월';
  return '${_englishMonthNames[date.month - 1]} ${date.year}';
}

String formatEditorDueDate(
  DateTime date, {
  AppLanguage language = AppLanguage.english,
}) {
  if (language == AppLanguage.korean) {
    return '${date.year}년 ${date.month}월 ${date.day}일';
  }
  return '${_englishShortMonthNames[date.month - 1]} ${date.day}, ${date.year}';
}

String formatListDueDate(
  DateTime date, {
  AppLanguage language = AppLanguage.english,
}) {
  if (language == AppLanguage.korean) return '${date.month}월 ${date.day}일';
  return '${_englishShortMonthNames[date.month - 1]} ${date.day}';
}

String formatDueDateStatus(
  DateTime date, {
  DateTime? today,
  AppLanguage language = AppLanguage.english,
}) {
  final days = dueDateDayDelta(date, today: today);
  if (days == 0) return language == AppLanguage.korean ? '오늘' : 'Today';
  if (days == 1) return language == AppLanguage.korean ? '내일' : 'Tomorrow';
  if (days > 1) return 'D-$days';
  return 'D+${days.abs()}';
}

int dueDateDayDelta(DateTime date, {DateTime? today}) {
  final currentDate = today ?? DateTime.now();
  final normalizedDate = DateTime(date.year, date.month, date.day);
  final normalizedToday = DateTime(
    currentDate.year,
    currentDate.month,
    currentDate.day,
  );
  return normalizedDate.difference(normalizedToday).inDays;
}

String formatTimeOfDay(
  DateTime date,
  AppTimeFormat timeFormat, {
  AppLanguage language = AppLanguage.english,
}) {
  final minute = date.minute.toString().padLeft(2, '0');

  switch (timeFormat) {
    case AppTimeFormat.twentyFourHour:
      return '${date.hour.toString().padLeft(2, '0')}:$minute';
    case AppTimeFormat.amPm:
      if (language == AppLanguage.korean) {
        final period = date.hour >= 12 ? '오후' : '오전';
        final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
        return '$period $hour:$minute';
      }
      final period = date.hour >= 12 ? 'PM' : 'AM';
      final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
      return '$hour:$minute $period';
  }
}
