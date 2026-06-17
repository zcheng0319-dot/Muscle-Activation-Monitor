import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_colors.dart';

abstract final class AppTypography {
  static const pageTitle = TextStyle(
    color: AppColors.secondary,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );

  static const sectionTitle = TextStyle(
    color: AppColors.secondary,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const cardTitle = TextStyle(
    color: AppColors.secondary,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  static const metric = TextStyle(
    color: AppColors.secondary,
    fontSize: 30,
    fontWeight: FontWeight.w600,
  );

  static const body = TextStyle(
    color: AppColors.secondary,
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  static const label = TextStyle(
    color: AppColors.secondary,
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );
}
