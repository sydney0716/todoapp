import 'package:flutter/material.dart';

class SwipeDeleteBackground extends StatelessWidget {
  const SwipeDeleteBackground({
    super.key,
    this.borderRadius,
    this.icon = Icons.delete_outline,
    this.rightPadding = 20,
  });

  final BorderRadius? borderRadius;
  final IconData icon;
  final double rightPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: borderRadius,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: EdgeInsets.only(right: rightPadding),
          child: Icon(
            icon,
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}
