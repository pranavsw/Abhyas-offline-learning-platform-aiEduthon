import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/book_service.dart';
import 'chapter_list_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "ABHYAS",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppTheme.cyanAccent
                          : AppTheme.primaryBlue,
                    ),
                  ),
                  const Text(
                    "Hi, Student",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              const Text(
                "Your Subjects",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              const SizedBox(height: 20),
              Expanded(
                child: FutureBuilder<List<String>>(
                  future: Future.value(
                    BookService.instance.getAvailableSubjects(),
                  ), // In case we want to make it async later
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final subjects = snapshot.data!;
                    if (subjects.isEmpty) {
                      return const Center(child: Text("No subjects available"));
                    }

                    return GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 1.1,
                          ),
                      itemCount: subjects.length,
                      itemBuilder: (context, index) {
                        final subject = subjects[index];
                        return _SubjectCard(
                          title: subject,
                          icon: _getIconForSubject(subject),
                          gradient: _getGradientForSubject(subject),
                          onTap: () => _navigateToChapters(context, subject),
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

  IconData _getIconForSubject(String subject) {
    switch (subject.toLowerCase()) {
      case 'science':
        return Icons.science;
      case 'math':
        return Icons.calculate;
      case 'history':
        return Icons.history_edu;
      case 'geography':
        return Icons.public;
      case 'english':
        return Icons.menu_book;
      case 'computers':
        return Icons.computer;
      default:
        return Icons.book;
    }
  }

  Gradient _getGradientForSubject(String subject) {
    switch (subject.toLowerCase()) {
      case 'science':
        return const LinearGradient(
          colors: [Color(0xFF4A90E2), Color(0xFF50E3C2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'math':
        return const LinearGradient(
          colors: [Color(0xFFF5A623), Color(0xFFFF8C00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'history':
        return const LinearGradient(
          colors: [Color(0xFF8B7355), Color(0xFFD4AF37)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'geography':
        return const LinearGradient(
          colors: [Color(0xFF27AE60), Color(0xFF1ABC9C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'english':
        return const LinearGradient(
          colors: [Color(0xFF9B59B6), Color(0xFF8E44AD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'computers':
        return const LinearGradient(
          colors: [Color(0xFF5A6978), Color(0xFF4A90E2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      default:
        return const LinearGradient(
          colors: [Color(0xFF607D8B), Color(0xFF90A4AE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  void _navigateToChapters(BuildContext context, String subject) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChapterListScreen(subject: subject)),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;

  const _SubjectCard({
    required this.title,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: Colors.white),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
