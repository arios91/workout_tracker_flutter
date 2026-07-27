import 'package:flutter/material.dart';

import 'db/database.dart';
import 'theme.dart';

void main() {
  runApp(const WorkoutTrackerApp());
}

class WorkoutTrackerApp extends StatefulWidget {
  const WorkoutTrackerApp({super.key});

  @override
  State<WorkoutTrackerApp> createState() => _WorkoutTrackerAppState();
}

class _WorkoutTrackerAppState extends State<WorkoutTrackerApp> {
  // Held here rather than built in build(): a new instance would open another
  // connection on every rebuild.
  late final AppDatabase _db = AppDatabase();

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Workout Tracker',
      debugShowCheckedModeBanner: false,
      // Dark only, permanently — no light palette exists.
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: _DbCheckScreen(db: _db),
    );
  }
}

/// Stands in until the session screen exists.
class _DbCheckScreen extends StatelessWidget {
  const _DbCheckScreen({required this.db});

  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workout Tracker')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Database',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<({String name, int rows})>>(
                  future: db.tableCounts(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return SingleChildScrollView(
                        child: Text(
                          '${snapshot.error}',
                          style: const TextStyle(color: AppColors.textPrimary),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return ListView.separated(
                      itemCount: snapshot.data!.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, i) {
                        final table = snapshot.data![i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                table.name,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                '${table.rows}',
                                style: AppText.notation.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
