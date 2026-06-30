import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/features/devices/presentation/controllers/device_connection_controller.dart';

class DeviceConnectPage extends ConsumerStatefulWidget {
  const DeviceConnectPage({super.key});

  @override
  ConsumerState<DeviceConnectPage> createState() => _DeviceConnectPageState();
}

class _DeviceConnectPageState extends ConsumerState<DeviceConnectPage> {
  final _connectingSides = <DeviceSide>{};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceConnectionControllerProvider);
    final controller = ref.read(deviceConnectionControllerProvider.notifier);

    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              sliver: SliverList.list(
                children: [
                  const _DeviceHeader(),
                  const SizedBox(height: AppSpacing.md),
                  _BleStatusPanel(state: state),
                  const SizedBox(height: AppSpacing.xl),
                  _DeviceCard(
                    device: state.leftDevice,
                    isConnecting: _connectingSides.contains(DeviceSide.left),
                    onConnect: () => _connectDevice(
                      context: context,
                      ref: ref,
                      side: DeviceSide.left,
                    ),
                    onDisconnect: () => controller.disconnect(DeviceSide.left),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connectDevice({
    required BuildContext context,
    required WidgetRef ref,
    required DeviceSide side,
  }) async {
    if (_connectingSides.contains(side)) return;
    setState(() => _connectingSides.add(side));

    final controller = ref.read(deviceConnectionControllerProvider.notifier);
    DeviceConnectAttempt result;
    try {
      result = await controller.connectPreferredDevice(side);
    } finally {
      if (mounted) {
        setState(() => _connectingSides.remove(side));
      }
    }

    if (!mounted || !context.mounted) return;
    if (!result.needsSelection) return;

    await _showDeviceSelectionDialog(context: context, ref: ref, side: side);
  }

  Future<void> _showDeviceSelectionDialog({
    required BuildContext context,
    required WidgetRef ref,
    required DeviceSide side,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(deviceConnectionControllerProvider);

            return AlertDialog(
              title: const Text('Select EMG Device'),
              content: SizedBox(
                width: 360,
                child: _DeviceSelectionList(
                  state: state,
                  onSelect: (device) async {
                    final connected = await ref
                        .read(deviceConnectionControllerProvider.notifier)
                        .connectDiscoveredDevice(side, device);
                    if (connected && dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: state.isScanning
                      ? null
                      : () => ref
                            .read(deviceConnectionControllerProvider.notifier)
                            .scanDevices(),
                  child: const Text('Scan Again'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _DeviceHeader extends StatelessWidget {
  const _DeviceHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Devices', style: AppTypography.pageTitle),
        SizedBox(height: AppSpacing.xs),
        Text('Connect EMG sensors', style: AppTypography.label),
      ],
    );
  }
}

class _DeviceSelectionList extends StatelessWidget {
  const _DeviceSelectionList({required this.state, required this.onSelect});

  final DeviceConnectionState state;
  final Future<void> Function(DiscoveredBleDevice device) onSelect;

  @override
  Widget build(BuildContext context) {
    if (state.scanError != null) {
      return Text(
        state.scanError!,
        style: AppTypography.label.copyWith(color: AppColors.red),
      );
    }

    if (state.discoveredDevices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            if (state.isScanning) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Text(
                state.isScanning
                    ? 'Scanning for nearby BLE devices...'
                    : 'No BLE devices found. Try again.',
                style: AppTypography.label,
              ),
            ),
          ],
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: state.discoveredDevices.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final device = state.discoveredDevices[index];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              device.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('${device.id} | ${device.rssi} dBm'),
            onTap: () => onSelect(device),
          );
        },
      ),
    );
  }
}

class _BleStatusPanel extends StatelessWidget {
  const _BleStatusPanel({required this.state});

  final DeviceConnectionState state;

  @override
  Widget build(BuildContext context) {
    final statusText = state.bleSupported
        ? 'Bluetooth ${state.adapterState.name}'
        : 'Bluetooth LE not supported';
    final detailText =
        state.scanError ??
        (state.discoveredDevices.isEmpty
            ? 'Tap Connect on a device slot to scan nearby BLE devices.'
            : '${state.discoveredDevices.length} BLE device(s) found.');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bluetooth_rounded,
                  color: state.canScan ? AppColors.selection : AppColors.muted,
                  size: 19,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    statusText,
                    style: AppTypography.cardTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              detailText,
              style: AppTypography.label.copyWith(
                color: state.scanError == null
                    ? AppColors.muted
                    : AppColors.red,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (state.discoveredDevices.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              ...state.discoveredDevices
                  .take(3)
                  .map(
                    (device) => Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        '${device.name}  ${device.rssi} dBm',
                        style: AppTypography.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.isConnecting,
    required this.onConnect,
    required this.onDisconnect,
  });

  final EmgDeviceConnection device;
  final bool isConnecting;
  final Future<void> Function() onConnect;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final statusColor = device.connected || isConnecting
        ? AppColors.selection
        : AppColors.red;
    final statusLabel = isConnecting ? 'Connecting...' : device.statusLabel;

    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        side: BorderSide(color: AppColors.secondary.withValues(alpha: 0.28)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        onTap: device.connected
            ? () {
                onDisconnect();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DeviceIcon(connected: device.connected),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EMG Device',
                          style: AppTypography.sectionTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          device.displayName,
                          style: AppTypography.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _StatusBadge(label: statusLabel, color: statusColor),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: _DeviceMetric(
                      icon: Icons.network_cell_rounded,
                      label: 'Signal',
                      value: device.signalLabel,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (isConnecting) return;
                    if (device.connected) {
                      onDisconnect();
                    } else {
                      onConnect();
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: device.connected
                        ? AppColors.red
                        : AppColors.primary,
                    side: BorderSide(
                      color: device.connected
                          ? AppColors.red
                          : AppColors.primary,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.controlRadius,
                      ),
                    ),
                  ),
                  icon: isConnecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          device.connected
                              ? Icons.link_off_rounded
                              : Icons.link_rounded,
                          size: 18,
                        ),
                  label: Text(
                    isConnecting
                        ? 'Connecting...'
                        : device.connected
                        ? 'Disconnect'
                        : 'Connect',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceIcon extends StatelessWidget {
  const _DeviceIcon({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: connected
            ? AppColors.selection.withValues(alpha: 0.12)
            : AppColors.surface,
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Icon(
        Icons.sensors_rounded,
        color: connected ? AppColors.selection : AppColors.muted,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTypography.label.copyWith(
          color: AppColors.secondary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _DeviceMetric extends StatelessWidget {
  const _DeviceMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.muted, size: 17),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                label,
                style: AppTypography.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              value,
              style: AppTypography.cardTitle.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
