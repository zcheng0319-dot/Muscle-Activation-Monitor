import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_theme.dart';
import 'package:myemg/features/comparison/presentation/pages/comparison_page.dart';
import 'package:myemg/features/comparison/presentation/controllers/comparison_controller.dart';
import 'package:myemg/features/devices/presentation/pages/device_connect_page.dart';

class MyEmgApp extends StatelessWidget {
  const MyEmgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyEMG',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AppShell(),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  static const _compareIndex = 1;

  int _selectedIndex = _compareIndex;
  late final AppLifecycleListener _appLifecycleListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appLifecycleListener = AppLifecycleListener(
      onPause: () => _handleBackgroundLifecycle(),
      onHide: () => _handleBackgroundLifecycle(),
      onDetach: () => _handleBackgroundLifecycle(),
    );
  }

  @override
  void dispose() {
    _appLifecycleListener.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached) {
      return;
    }
    _handleBackgroundLifecycle();
  }

  @override
  Widget build(BuildContext context) {
    final comparisonPhase = ref.watch(
      comparisonControllerProvider.select((state) => state.phase),
    );
    final comparisonActive = _isActiveComparisonPhase(comparisonPhase);

    return PopScope<Object?>(
      canPop: !comparisonActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && comparisonActive) {
          _abortActiveComparison('system_back');
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            const DeviceConnectPage(),
            ComparisonPage(onOpenDevices: () => _selectTab(0)),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.sidebar,
            border: Border(top: BorderSide(color: AppColors.border)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1A0F172A),
                blurRadius: 18,
                spreadRadius: -8,
                offset: Offset(0, -8),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: NavigationBar(
                selectedIndex: _selectedIndex,
                height: 58,
                backgroundColor: AppColors.card,
                indicatorColor: AppColors.primary.withValues(alpha: 0.12),
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                onDestinationSelected: _selectTab,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_rounded),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Devices',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.compare_arrows_rounded),
                    selectedIcon: Icon(Icons.compare_arrows_rounded),
                    label: 'Compare',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectTab(int index) {
    if (index == _selectedIndex) return;
    if (_selectedIndex == _compareIndex && index != _compareIndex) {
      _abortActiveComparison('left_compare_page');
    }
    setState(() => _selectedIndex = index);
  }

  void _abortActiveComparison(String reason) {
    final controller = ref.read(comparisonControllerProvider.notifier);
    final phase = ref.read(comparisonControllerProvider).phase;
    if (_isActiveComparisonPhase(phase)) controller.abort(reason);
  }

  void _handleBackgroundLifecycle() {
    _abortActiveComparison('app_backgrounded');
    if (mounted) {
      setState(() {});
    }
  }

  bool _isActiveComparisonPhase(ComparisonPhase phase) {
    return switch (phase) {
      ComparisonPhase.calibrating ||
      ComparisonPhase.ready ||
      ComparisonPhase.recording ||
      ComparisonPhase.review ||
      ComparisonPhase.betweenActions => true,
      _ => false,
    };
  }
}
