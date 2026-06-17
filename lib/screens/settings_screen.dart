import 'dart:async';

import 'package:flutter/material.dart';

import '../app_strings.dart';
import '../models.dart';
import '../settings_controller.dart';
import 'shared/paper_background.dart';

const _transparentSwitchOverlay = WidgetStatePropertyAll<Color?>(
  Colors.transparent,
);

WidgetStateProperty<Color?> _settingsSwitchThumbColor(ColorScheme colors) {
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.disabled)) {
      return states.contains(WidgetState.selected)
          ? colors.surface
          : colors.onSurface.withValues(alpha: 0.38);
    }
    return states.contains(WidgetState.selected)
        ? colors.onPrimary
        : colors.outline;
  });
}

WidgetStateProperty<Color?> _settingsSwitchTrackColor(ColorScheme colors) {
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.disabled)) {
      return states.contains(WidgetState.selected)
          ? colors.onSurface.withValues(alpha: 0.12)
          : colors.surfaceContainerHighest.withValues(alpha: 0.12);
    }
    return states.contains(WidgetState.selected)
        ? colors.primary
        : colors.surfaceContainerHighest;
  });
}

WidgetStateProperty<Color?> _settingsSwitchTrackOutlineColor(
  ColorScheme colors,
) {
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.selected)) return Colors.transparent;
    if (states.contains(WidgetState.disabled)) {
      return colors.onSurface.withValues(alpha: 0.12);
    }
    return colors.outline;
  });
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
  });

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        final strings = AppStrings.of(context);

        return Scaffold(
          appBar: AppBar(title: Text(strings.settings)),
          body: PaperBackground(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _SettingsSelectionRow<AppThemeMode>(
                  title: strings.theme,
                  menuKey: const ValueKey('theme-mode-menu'),
                  values: AppThemeMode.values,
                  selected: settings.themeMode,
                  labelBuilder: strings.themeModeLabel,
                  onSelected: (mode) {
                    unawaited(settings.setThemeMode(mode));
                  },
                ),
                const _SettingsDivider(),
                _SettingsSelectionRow<AppLanguage>(
                  title: strings.languageLabel,
                  menuKey: const ValueKey('language-menu'),
                  values: AppLanguage.values,
                  selected: settings.language,
                  labelBuilder: strings.appLanguageLabel,
                  onSelected: (language) {
                    unawaited(settings.setLanguage(language));
                  },
                ),
                const _SettingsDivider(),
                _SettingsSelectionRow<CompletedTaskRetentionPolicy>(
                  title: strings.completedTaskRetention,
                  menuKey: const ValueKey('completed-retention-menu'),
                  values: CompletedTaskRetentionPolicy.values,
                  selected: settings.completedTaskRetentionPolicy,
                  labelBuilder: strings.completedTaskRetentionPolicyLabel,
                  onSelected: (policy) {
                    unawaited(
                      settings.setCompletedTaskRetentionPolicy(policy),
                    );
                  },
                ),
                const _SettingsDivider(),
                _TimeFormatToggle(
                  value: settings.timeFormat == AppTimeFormat.twentyFourHour,
                  example: strings.timeFormatExample(settings.timeFormat),
                  onChanged: (value) {
                    final timeFormat = value
                        ? AppTimeFormat.twentyFourHour
                        : AppTimeFormat.amPm;
                    unawaited(settings.setTimeFormat(timeFormat));
                  },
                ),
                const _SettingsDivider(),
                _SettingsToggle(
                  title: strings.showCompletedTasks,
                  value: settings.showCompletedTasks,
                  onChanged: (value) {
                    unawaited(settings.setShowCompletedTasks(value));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TimeFormatToggle extends StatelessWidget {
  const _TimeFormatToggle({
    required this.value,
    required this.example,
    required this.onChanged,
  });

  final bool value;
  final String example;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);

    return _SettingsSwitchRow(
      title: strings.useTwentyFourHourTime,
      subtitle: Text(
        example,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _SettingsSelectionRow<T> extends StatelessWidget {
  const _SettingsSelectionRow({
    required this.title,
    required this.menuKey,
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
  });

  final String title;
  final Key menuKey;
  final List<T> values;
  final T selected;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  labelBuilder(selected),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<T>(
            key: menuKey,
            tooltip: title,
            initialValue: selected,
            icon: const Icon(Icons.keyboard_arrow_down),
            onSelected: onSelected,
            itemBuilder: (context) => [
              for (final value in values)
                PopupMenuItem(
                  value: value,
                  child: Row(
                    children: [
                      Expanded(child: Text(labelBuilder(value))),
                      if (value == selected) const Icon(Icons.check),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _SettingsToggle extends StatelessWidget {
  const _SettingsToggle({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingsSwitchRow(
      title: title,
      value: value,
      onChanged: onChanged,
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyLarge),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    subtitle!,
                  ],
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              thumbColor: _settingsSwitchThumbColor(colors),
              trackColor: _settingsSwitchTrackColor(colors),
              trackOutlineColor: _settingsSwitchTrackOutlineColor(colors),
              overlayColor: _transparentSwitchOverlay,
            ),
          ],
        ),
      ),
    );
  }
}
