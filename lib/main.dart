import 'package:flutter/material.dart';

import 'theme.dart';

void main() {
  runApp(const WorkoutTrackerApp());
}

class WorkoutTrackerApp extends StatelessWidget {
  const WorkoutTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Workout Tracker',
      debugShowCheckedModeBanner: false,
      // Dark only, permanently — no light palette exists.
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const _Placeholder(),
    );
  }
}

/// Stands in until the session screen exists.
class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workout Tracker')),
      body: const Center(
        child: Text('No screens yet.', style: TextStyle(color: AppColors.textSecondary)),
      ),
    );
  }
}
