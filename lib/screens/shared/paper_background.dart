import 'package:flutter/material.dart';

class PaperBackground extends StatelessWidget {
  const PaperBackground({
    super.key,
    required this.child,
    this.textureOpacity,
  });

  static const textureAsset = 'assets/textures/paper_background_v2.png';
  static const defaultLightTextureOpacity = 0.52;

  final Widget child;
  final double? textureOpacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (theme.brightness == Brightness.dark) {
      return ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: child,
      );
    }

    final opacity = textureOpacity ?? defaultLightTextureOpacity;

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: opacity,
                child: Image.asset(
                  textureAsset,
                  repeat: ImageRepeat.repeat,
                  fit: BoxFit.none,
                  alignment: Alignment.topLeft,
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
