import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_theme.dart';
import 'package:myemg/features/devices/presentation/pages/device_connect_page.dart';
import 'package:myemg/features/training/presentation/pages/training_page.dart';

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

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _trainingIndex = 1;

  int _selectedIndex = _trainingIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [DeviceConnectPage(), TrainingPage()],
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
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_rounded),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Devices',
                ),
                NavigationDestination(
                  icon: Icon(Icons.fitness_center_rounded),
                  selectedIcon: Icon(Icons.fitness_center_rounded),
                  label: 'Training',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
