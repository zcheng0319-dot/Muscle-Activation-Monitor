import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_colors.dart';

class AmbientBackground extends StatelessWidget {
  const AmbientBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: AppColors.surface, child: child);
  }
}
