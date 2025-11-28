import 'package:flutter/material.dart';
import '../services/quiz_service.dart';
import '../theme/app_theme.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Your Progress")),
      body: FutureBuilder<Map<String, dynamic>>(
        future: QuizService.instance.getStats(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final stats = snapshot.data ?? {'total': 0, 'correct': 0};
          final total = stats['total'] as int;
          final correct = stats['correct'] as int;
          final percentage = total == 0 ? 0.0 : (correct / total * 100);

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          const Text(
                            "Overall Performance",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 150,
                                height: 150,
                                child: CircularProgressIndicator(
                                  value: total == 0 ? 0 : correct / total,
                                  strokeWidth: 12,
                                  backgroundColor: Colors.grey.withOpacity(0.2),
                                  color: AppTheme.cyanAccent,
                                ),
                              ),
                              Column(
                                children: [
                                  Text(
                                    "${percentage.toStringAsFixed(1)}%",
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Text("Accuracy"),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _StatItem(
                                label: "Quizzes Taken",
                                value: "$total",
                                icon: Icons.quiz,
                                color: Colors.orange,
                              ),
                              _StatItem(
                                label: "Correct Answers",
                                value: "$correct",
                                icon: Icons.check_circle,
                                color: Colors.green,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Recent Activity",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<List<QuizResult>>(
                    future: QuizService.instance.getHistory(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(child: Text("No recent activity"));
                      }
                      final history = snapshot.data!;
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: history.length,
                        itemBuilder: (context, index) {
                          final item = history[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(
                                item.isCorrect
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                color: item.isCorrect
                                    ? Colors.green
                                    : Colors.red,
                              ),
                              title: Text(
                                item.question,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                "${item.subject} • ${item.chapter}",
                              ),
                              trailing: Text(
                                item.isCorrect ? "+10 XP" : "0 XP",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}
