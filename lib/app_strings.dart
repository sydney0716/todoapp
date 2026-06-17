import 'package:flutter/widgets.dart';

import 'models.dart';
import 'settings_controller.dart';

class AppStrings {
  const AppStrings._(this.language);

  final AppLanguage language;

  static AppStrings of(BuildContext context) {
    return forLanguage(languageOf(context));
  }

  static AppStrings forLanguage(AppLanguage language) {
    return AppStrings._(language);
  }

  static AppLanguage languageOf(BuildContext context) {
    return AppLanguage.fromStoredValue(
      Localizations.localeOf(context).languageCode,
    );
  }

  bool get _ko => language == AppLanguage.korean;

  String get appTitle => _ko ? '할 일 앱' : 'Todo App';
  String get settings => _ko ? '설정' : 'Settings';
  String get cancel => _ko ? '취소' : 'Cancel';
  String get save => _ko ? '저장' : 'Save';
  String get delete => _ko ? '삭제' : 'Delete';
  String get move => _ko ? '이동' : 'Move';
  String get undo => _ko ? '취소' : 'Undo';
  String get custom => _ko ? '직접 설정' : 'Custom';

  String get theme => _ko ? '테마' : 'Theme';
  String get timeFormat => _ko ? '시간 형식' : 'Time format';
  String get useTwentyFourHourTime => _ko ? '24시간 형식 사용' : 'Use 24-hour time';
  String get languageLabel => _ko ? '언어' : 'Language';
  String get completedTaskRetention =>
      _ko ? '완료된 할 일 보관 기간' : 'Completed task retention';
  String get showCompletedTasks => _ko ? '완료된 할 일 표시' : 'Show completed tasks';
  String get serverConnection => _ko ? '서버 연결' : 'Server connection';
  String get status => _ko ? '상태' : 'Status';
  String get lastBootstrap => _ko ? '마지막 초기 동기화' : 'Last bootstrap';
  String get password => _ko ? '비밀번호' : 'Password';
  String get login => _ko ? '로그인' : 'Log in';
  String get loginFailed => _ko ? '로그인할 수 없습니다.' : 'Unable to log in.';
  String get verifying => _ko ? '확인 중' : 'Verifying';
  String get verifyConnection => _ko ? '연결 확인' : 'Verify connection';
  String get syncing => _ko ? '동기화 중' : 'Syncing';
  String get syncNow => _ko ? '동기화' : 'Sync now';
  String get syncingNow => _ko ? '동기화 중...' : 'Syncing...';
  String get passwordRequired => _ko ? '비밀번호를 입력하세요.' : 'Password is required.';
  String get unexpectedServerResponse =>
      _ko ? '예상하지 못한 서버 응답입니다.' : 'Unexpected server response.';
  String get unableToReachServer =>
      _ko ? '서버에 연결할 수 없습니다.' : 'Unable to reach server.';
  String get reconnectToServer =>
      _ko ? '서버에 다시 연결하세요.' : 'Reconnect to the server.';
  String get unableToSyncNow =>
      _ko ? '지금은 동기화할 수 없습니다.' : 'Unable to sync right now.';

  String get newTask => _ko ? '할  일 추가' : 'New Task';
  String get noVisibleTasks => _ko ? '할 일 없음' : 'No visible tasks';
  String get noTasksYet => _ko ? '할  일 없음' : 'No tasks yet';
  String get completedTasksHidden => _ko
      ? '설정에서 완료된 할 일을 숨기고 있습니다.'
      : 'Completed tasks are hidden in Settings.';
  String get addTaskEmptyMessage => _ko
      ? '할 일을 추가하면 달력과 목록에 표시됩니다.'
      : 'Add a task to start filling the calendar and list.';
  String get noCategory => _ko ? '카테고리 없음' : 'No category';
  String get newCategory => _ko ? '새 카테고리' : 'New category';
  String get categoryName => _ko ? '카테고리 이름' : 'Category name';
  String get done => _ko ? '완료' : 'Done';
  String get completed => _ko ? '완료됨' : 'Completed';
  String get select => _ko ? '선택' : 'Select';
  String get sort => _ko ? '정렬' : 'Sort';
  String get trash => _ko ? '휴지통' : 'Trash';
  String get trashcan => _ko ? '휴지통' : 'Trashcan';
  String get showPersonalOnly => _ko ? '개인 항목만 보기' : 'Show personal only';
  String get showPersonalAndShared =>
      _ko ? '개인/공유 항목 보기' : 'Show personal and shared';
  String get openMenu => _ko ? '메뉴 열기' : 'Open menu';

  String get saving => _ko ? '저장 중...' : 'Saving...';
  String get saveTask => _ko ? '할 일 저장' : 'Save Task';
  String get saveChanges => _ko ? '변경사항 저장' : 'Save Changes';
  String get deleteTask => _ko ? '할 일 삭제' : 'Delete task';
  String get title => _ko ? '제목' : 'Title';
  String get addDetails => _ko ? '세부 내용 추가' : 'Add details';
  String get dueDate => _ko ? '마감일' : 'Due date';
  String get time => _ko ? '시간' : 'Time';
  String get addTime => _ko ? '시간 추가' : 'Add time';
  String get chooseDueDateBeforeAlarm => _ko
      ? '알람을 추가하려면 먼저 마감일을 선택하세요.'
      : 'Choose a due date before adding alarm.';
  String get titleRequired => _ko ? '제목을 입력하세요.' : 'Title is required.';
  String get selectCategory => _ko ? '카테고리 선택' : 'Select category';
  String get customMinutes => _ko ? '사용자 지정 분' : 'Custom minutes';
  String get customHours => _ko ? '사용자 지정 시간' : 'Custom hours';
  String get startOfDayAlarm => _ko ? '하루 시작 알람' : 'Start of day alarm';
  String get privateLabel => _ko ? '개인' : 'Private';
  String get sharedLabel => _ko ? '공유' : 'Shared';
  String get personalLabel => _ko ? '개인' : 'Personal';
  String get bothLabel => _ko ? '모두' : 'Both';
  String get markDone => _ko ? '완료로 표시' : 'Mark done';
  String get markNotDone => _ko ? '미완료로 표시' : 'Mark not done';
  String get subtask => _ko ? '하위 할 일' : 'Subtask';
  String get subtaskOptions => _ko ? '하위 할 일 옵션' : 'Subtask options';
  String get setDueDate => _ko ? '마감일 설정' : 'Set due date';
  String get changeDueDate => _ko ? '마감일 변경' : 'Change due date';
  String get clearDueDate => _ko ? '마감일 지우기' : 'Clear due date';
  String get addSubtask => _ko ? '하위 할 일 추가' : 'Add subtask';

  String get emptyTrash => _ko ? '휴지통 비우기' : 'Empty trash';
  String get emptyTrashTitle => _ko ? '휴지통을 비울까요?' : 'Empty Trashcan?';
  String get emptyTrashMessage => _ko
      ? '휴지통의 항목을 영구 삭제합니다.'
      : 'This permanently deletes synced items currently in Trashcan.';
  String get deletePermanentlyTitle =>
      _ko ? '영구 삭제할까요?' : 'Delete permanently?';
  String get syncBeforePermanentDelete => _ko
      ? '동기화 후 영구 삭제할 수 있습니다.'
      : 'This item can be permanently deleted after it syncs.';
  String get restore => _ko ? '복원' : 'Restore';
  String get deletePermanently => _ko ? '영구 삭제' : 'Delete permanently';
  String get waitingForSync => _ko ? '동기화 대기 중' : 'Waiting for sync';
  String get noCompletedTasks => _ko ? '완료된 할 일이 없습니다' : 'No completed tasks';

  String appLanguageLabel(AppLanguage value) {
    switch (value) {
      case AppLanguage.korean:
        return _ko ? '한국어' : 'Korean';
      case AppLanguage.english:
        return _ko ? '영어' : 'English';
    }
  }

  String themeModeLabel(AppThemeMode value) {
    switch (value) {
      case AppThemeMode.dark:
        return _ko ? '다크 모드' : 'Dark Mode';
      case AppThemeMode.light:
        return _ko ? '라이트 모드' : 'Light Mode';
      case AppThemeMode.followSystem:
        return _ko ? '시스템 설정' : 'Follow system';
    }
  }

  String timeFormatLabel(AppTimeFormat value) {
    switch (value) {
      case AppTimeFormat.twentyFourHour:
        return _ko ? '24시간' : '24 hour';
      case AppTimeFormat.amPm:
        return _ko ? '오전/오후' : 'AM/PM';
    }
  }

  String timeFormatExample(AppTimeFormat value) {
    switch (value) {
      case AppTimeFormat.twentyFourHour:
        return '13:00';
      case AppTimeFormat.amPm:
        return _ko ? '오후 1시' : 'PM 1:00';
    }
  }

  String completedTaskRetentionPolicyLabel(
    CompletedTaskRetentionPolicy value,
  ) {
    switch (value) {
      case CompletedTaskRetentionPolicy.oneMonth:
        return _ko ? '1개월' : '1 month';
      case CompletedTaskRetentionPolicy.sixMonths:
        return _ko ? '6개월' : '6 months';
      case CompletedTaskRetentionPolicy.twelveMonths:
        return _ko ? '12개월' : '12 months';
    }
  }

  String taskSortOptionLabel(TaskSortOption value) {
    switch (value) {
      case TaskSortOption.dueDate:
        return _ko ? '마감일' : 'Due date';
      case TaskSortOption.title:
        return _ko ? '제목' : 'Title';
      case TaskSortOption.lastModified:
        return _ko ? '최근 수정' : 'Last modified';
    }
  }

  String taskSortDirectionLabel(TaskSortDirection value) {
    switch (value) {
      case TaskSortDirection.ascending:
        return _ko ? '오름차순' : 'Ascending order';
      case TaskSortDirection.descending:
        return _ko ? '내림차순' : 'Descending order';
    }
  }

  String serverConnectionStatusLabel(ServerConnectionStatus value) {
    switch (value) {
      case ServerConnectionStatus.notConnected:
        return _ko ? '아직 연결되지 않음' : 'Not connected yet';
      case ServerConnectionStatus.connected:
        return _ko ? '연결됨' : 'Connected';
      case ServerConnectionStatus.failed:
        return _ko ? '연결 실패' : 'Connection failed';
    }
  }

  String reminderOptionLabel(TaskReminderOption value) {
    switch (value) {
      case TaskReminderOption.none:
        return _ko ? '알람 없음' : 'no alarm';
      case TaskReminderOption.atStart:
        return _ko ? '시작 시' : 'start';
      case TaskReminderOption.beforeMinutes:
        return reminderMinutes(5);
      case TaskReminderOption.beforeHours:
        return reminderHours(1);
      case TaskReminderOption.startOfDay:
        return _ko ? '하루 시작' : 'start of day';
    }
  }

  String connectedBootstrapMessage(int count) {
    if (_ko) return '연결되었습니다. 할 일 $count개를 가져왔습니다.';
    return 'Connected. Bootstrap returned $count ${_tasks(count)}.';
  }

  String syncResultMessage({
    required int pushed,
    required int pulled,
    required int failed,
  }) {
    if (failed > 0) {
      if (_ko) return '동기화 실패 $failed개.';
      return '$failed sync ${failed == 1 ? 'item' : 'items'} failed.';
    }
    if (pushed > 0 || pulled > 0) {
      if (_ko) return '동기화 완료. 보낸 항목 $pushed개, 받은 항목 $pulled개.';
      return 'Sync completed. Sent $pushed, received $pulled.';
    }
    if (_ko) return '동기화 완료. 변경 없음.';
    return 'Sync completed. No changes.';
  }

  String completedOn(String date) {
    if (_ko) return '$date 완료됨';
    return 'Completed $date';
  }

  String lastBootstrapValue({
    required int taskCount,
    required String cursor,
  }) {
    if (_ko) return '할 일 $taskCount개, 커서 $cursor';
    return '$taskCount ${_tasks(taskCount)}, cursor $cursor';
  }

  String selectedTasksMarkedDone(int count) {
    if (_ko) return '할 일 $count개를 완료로 표시했습니다';
    return '$count ${_tasks(count)} marked done';
  }

  String selectedTasksMovedToCategory(int count, String category) {
    final target = category.isEmpty ? noCategory : category;
    if (_ko) return '할 일 $count개를 이동했습니다: $target';
    return '$count ${_tasks(count)} moved to $target';
  }

  String tasksMovedToTrash(int count) {
    if (_ko) return '할 일 $count개를 휴지통으로 이동했습니다';
    return '$count ${_tasks(count)} moved to Trashcan';
  }

  String taskMovedToTrash(String title) {
    if (_ko) return '"$title" 휴지통으로 이동했습니다';
    return '"$title" moved to Trashcan';
  }

  String hiddenSubtasks(int count) {
    if (_ko) return '+ $count개 더 보기';
    return '+ $count more ${_tasks(count)}';
  }

  String reminderMinutes(int minutes) {
    if (_ko) return '$minutes분 전';
    return 'before $minutes min';
  }

  String reminderHours(int hours) {
    if (_ko) return '$hours시간 전';
    return 'before $hours ${hours == 1 ? 'hour' : 'hours'}';
  }

  String minuteValue(int minutes) {
    if (_ko) return '$minutes분';
    return '$minutes min';
  }

  String hourValue(int hours) {
    if (_ko) return '$hours시간';
    return hours == 1 ? '1 hour' : '$hours hours';
  }

  String startOfDayWithTime(String time) {
    if (_ko) return '하루 시작 $time';
    return 'start of day $time';
  }

  String noDeletedItems(String label) {
    if (_ko) return '삭제된 $label이 없습니다';
    return 'No deleted $label';
  }

  String get tasksLabel => _ko ? '할 일' : 'tasks';

  String trashSubtitle({
    required DateTime? deletedAt,
    required DateTime? purgeAfter,
    required String Function(DateTime date) formatDate,
  }) {
    final deletedText = deletedAt == null
        ? (_ko ? '삭제됨' : 'Deleted')
        : (_ko
            ? '${formatDate(deletedAt)} 삭제됨'
            : 'Deleted ${formatDate(deletedAt)}');
    final purgeText = purgeAfter == null
        ? (_ko ? '자동 삭제 없음' : 'auto-delete never')
        : (_ko
            ? '${formatDate(purgeAfter)} 자동 삭제'
            : 'auto-delete ${formatDate(purgeAfter)}');
    return '$deletedText, $purgeText';
  }

  String permanentDeleteMessage(String title) {
    if (_ko) return '"$title"은(는) 삭제 후 복원할 수 없습니다.';
    return '"$title" cannot be restored after this.';
  }

  String _tasks(int count) => count == 1 ? 'task' : 'tasks';
}
