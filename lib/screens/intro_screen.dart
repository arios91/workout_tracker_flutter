import 'package:flutter/material.dart';

import '../db/database.dart';
import '../theme.dart';

/// Stands in until the session screen exists.
class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key, required this.db});

  // Owned by main.dart; this screen must not close it.
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
