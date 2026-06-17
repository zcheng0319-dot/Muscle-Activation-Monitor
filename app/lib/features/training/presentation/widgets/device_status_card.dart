import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/shared/widgets/dashboard_card.dart';

class DeviceStatusCard extends StatelessWidget {
  const DeviceStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const DashboardCard(
      child: Row(
        children: [
          Icon(Icons.sensors_rounded, color: AppColors.selection, size: 20),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Both EMG devices connected',
                  style: AppTypography.cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: AppSpacing.xs),
                Text(
                  'Signal stable | Demo data | 100 Hz',
                  style: AppTypography.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.battery_5_bar_rounded, color: AppColors.muted, size: 19),
          SizedBox(width: AppSpacing.xs),
          Text('83%', style: AppTypography.label),
        ],
      ),
    );
  }
}
