import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_theme.dart';
import 'package:myemg/features/training/presentation/pages/training_page.dart';

class MyEmgApp extends StatelessWidget {
  const MyEmgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyEMG',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const TrainingPage(),
    );
  }
}
