import 'package:flutter/material.dart';
import '../services/book_service.dart';
import '../theme/app_theme.dart';
import 'quiz_screen.dart';

class LessonScreen extends StatefulWidget {
  final String chapterTitle;
  final String subject;

  const LessonScreen({
    super.key,
    required this.chapterTitle,
    required this.subject,
  });

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  late List<Map<String, dynamic>> _topics;

  @override
  void initState() {
    super.initState();
    _topics = BookService.instance.getTopicsForChapter(
      widget.chapterTitle,
      widget.subject,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chapterTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up_rounded),
            onPressed: () {
              // Placeholder for Read Aloud
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Read Aloud feature coming soon!"),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            onPressed: () {
              // Placeholder for AI Summarize
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("AI Summarize feature coming soon!"),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _topics.isEmpty
                ? const Center(child: Text("No content available."))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _topics.length,
                    separatorBuilder: (ctx, i) => const Divider(height: 32),
                    itemBuilder: (context, index) {
                      final topic = _topics[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            topic['topic'] ?? "Topic ${index + 1}",
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.cyanAccent,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            topic['content'] ?? "",
                            style: const TextStyle(fontSize: 16, height: 1.6),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QuizScreen(
                        chapterTitle: widget.chapterTitle,
                        subject: widget.subject,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cyanAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.quiz_rounded),
                    SizedBox(width: 8),
                    Text(
                      "Take a Question",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
