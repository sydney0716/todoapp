import 'package:flutter/material.dart';

import '../../app_strings.dart';
import '../../models.dart';

class SyncVisibilityIcon extends StatelessWidget {
  const SyncVisibilityIcon({
    super.key,
    required this.visibility,
    this.size = 16,
    this.showTooltip = true,
  });

  final SyncVisibility visibility;
  final double size;
  final bool showTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final isShared = visibility == SyncVisibility.shared;
    final icon = Icon(
      isShared ? Icons.group_outlined : Icons.person_outline,
      size: size,
      color: theme.colorScheme.onSurfaceVariant,
    );

    if (!showTooltip) return icon;
    return Tooltip(
      message: isShared ? strings.sharedLabel : strings.personalLabel,
      child: icon,
    );
  }
}
