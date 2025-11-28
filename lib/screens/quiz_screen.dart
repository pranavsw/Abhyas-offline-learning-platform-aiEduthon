import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import '../services/book_service.dart';
import '../services/quiz_service.dart';
import '../theme/app_theme.dart';

class QuizScreen extends StatefulWidget {
  final String chapterTitle;
  final String subject;

  const QuizScreen({
    super.key,
    required this.chapterTitle,
    required this.subject,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _questionData;
  String? _selectedOption;
  bool _isAnswerRevealed = false;
  String? _error;
  InferenceChat? _chatSession;
  int _score = 0;
  int _totalQuestions = 0;

  @override
  void initState() {
    super.initState();
    _generateNewQuestion();
  }

  @override
  void dispose() {
    _chatSession = null;
    super.dispose();
  }

  Future<void> _generateNewQuestion() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _selectedOption = null;
      _isAnswerRevealed = false;
      _questionData = null;
    });

    try {
      // 1. Get Context using Subject + Chapter
      String context = BookService.instance.getRandomContextForChapter(
        widget.chapterTitle,
        widget.subject,
      );

      if (context.isEmpty) throw "No content available for this chapter.";

      // Always create a fresh session for quiz to avoid context pollution
      // and ensure we don't reuse the global model state if possible (though FlutterGemma is singleton-ish)
      // The user requested "dont use existing model instance...".
      // We can't easily spawn a new isolate here without more work, but creating a new chat session
      // is the standard way to reset context.
      _chatSession = null;
      final model = await FlutterGemma.getActiveModel(
        preferredBackend: PreferredBackend.cpu,
      );
      _chatSession = await model.createChat();

      final randomId = Random().nextInt(10000);
      String prompt =
          """Context:
$context

Task ID: $randomId
Task: Generate 1 UNIQUE multiple-choice question, its correct answer, and 3 related but wrong options based on the text provided.
Output strictly in JSON format:
{
  "question": "Question text",
  "answer": "The correct answer here",
  "distractors": ["Wrong option 1", "Wrong option 2", "Wrong option 3"]
}
Do not add any other text.""";

      await _chatSession!.addQueryChunk(
        Message.text(text: prompt, isUser: true),
      );

      String response = "";
      int tokenCount = 0;

      await for (final event in _chatSession!.generateChatResponseAsync()) {
        if (event is TextResponse) {
          String t = event.token;
          if (t.contains('<bos>') || t.contains('<eos>')) continue;
          response += t;
          if (++tokenCount > 300) break;
        }
      }

      // Parsing
      Map<String, dynamic> data;
      try {
        String jsonStr = response.replaceAll(RegExp(r'```json|```'), '').trim();
        int start = jsonStr.indexOf('{');
        int end = jsonStr.lastIndexOf('}');
        if (start == -1 || end == -1) throw "Invalid JSON";
        jsonStr = jsonStr.substring(start, end + 1);
        data = jsonDecode(jsonStr);
      } catch (e) {
        throw "Failed to parse AI response";
      }

      String question = data['question'] ?? "Question error";
      String correctAnswer = data['answer'] ?? "Answer error";
      List<String> options = List<String>.from(data['distractors'] ?? []);

      options = [correctAnswer, ...options.take(3)];
      options.shuffle();

      if (mounted) {
        setState(() {
          _questionData = {
            'question': question,
            'options': options,
            'correct_answer': correctAnswer,
          };
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Failed to generate. Please retry.";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleAnswer(String option) async {
    setState(() {
      _selectedOption = option;
      _isAnswerRevealed = true;
    });

    bool isCorrect = option == _questionData!['correct_answer'];
    if (isCorrect) _score++;
    _totalQuestions++;

    // Save Result
    await QuizService.instance.saveResult(
      QuizResult(
        subject: widget.subject,
        chapter: widget.chapterTitle,
        question: _questionData!['question'],
        options: List<String>.from(_questionData!['options']),
        correctAnswer: _questionData!['correct_answer'],
        selectedAnswer: option,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isCorrect: isCorrect,
        synced: false, // Default
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Quiz: ${widget.chapterTitle}")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _generateNewQuestion,
                    child: const Text("Retry"),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      _questionData!['question'],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ...(_questionData!['options'] as List).map((option) {
                    bool isSelected = _selectedOption == option;
                    bool isCorrect = option == _questionData!['correct_answer'];
                    Color tileColor = Theme.of(context).cardColor;
                    Color borderColor = Colors.transparent;

                    if (_isAnswerRevealed) {
                      if (isCorrect) {
                        tileColor = Colors.green.withOpacity(0.2);
                        borderColor = Colors.green;
                      } else if (isSelected) {
                        tileColor = Colors.red.withOpacity(0.2);
                        borderColor = Colors.red;
                      }
                    } else if (isSelected) {
                      borderColor = AppTheme.cyanAccent;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isAnswerRevealed
                              ? null
                              : () => _handleAnswer(option),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: tileColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: borderColor == Colors.transparent
                                    ? Colors.grey.withOpacity(0.3)
                                    : borderColor,
                                width: 2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    option,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                                if (_isAnswerRevealed && isCorrect)
                                  const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                  ),
                                if (_isAnswerRevealed &&
                                    isSelected &&
                                    !isCorrect)
                                  const Icon(Icons.cancel, color: Colors.red),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 20),
                  if (_isAnswerRevealed)
                    ElevatedButton(
                      onPressed: _generateNewQuestion,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.cyanAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.all(16),
                      ),
                      child: const Text("Next Question"),
                    ),
                ],
              ),
            ),
    );
  }
}
