import 'package:flutter/material.dart';
import '../services/book_service.dart';
import '../theme/app_theme.dart';
import 'lesson_screen.dart';

class ChapterListScreen extends StatelessWidget {
  final String subject;

  const ChapterListScreen({super.key, required this.subject});

  @override
  Widget build(BuildContext context) {
    final chapters = BookService.instance.getChaptersForSubject(subject);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(subject),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: chapters.length,
        itemBuilder: (context, index) {
          final chapter = chapters[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blueGrey.shade800
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    "${index + 1}",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppTheme.primaryBlue,
                    ),
                  ),
                ),
              ),
              title: Text(
                chapter,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: const Text("Tap to view lessons"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        LessonScreen(chapterTitle: chapter, subject: subject),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
