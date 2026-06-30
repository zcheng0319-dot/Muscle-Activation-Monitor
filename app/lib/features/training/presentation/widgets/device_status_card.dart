import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/features/devices/presentation/controllers/device_connection_controller.dart';
import 'package:myemg/shared/widgets/dashboard_card.dart';

class DeviceStatusCard extends ConsumerWidget {
  const DeviceStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(deviceConnectionControllerProvider);
    final device = deviceState.leftDevice;
    final title = device.connected ? 'EMG connected' : 'No EMG connected';
    final detail = '${device.displayName} — ${device.statusLabel}';
    final iconColor = device.connected ? AppColors.selection : AppColors.red;

    return DashboardCard(
      child: Row(
        children: [
          Icon(Icons.sensors_rounded, color: iconColor, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  detail,
                  style: AppTypography.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
