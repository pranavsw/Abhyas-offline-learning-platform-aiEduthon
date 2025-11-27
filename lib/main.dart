import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// -----------------------------------------------------------------------------
// CONFIGURATION
// -----------------------------------------------------------------------------
const String kHuggingFaceToken = "YOUR_HF_TOKEN";
const String kModelUrl =
    'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task';

// -----------------------------------------------------------------------------
// MAIN ENTRY POINT
// -----------------------------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize();
  runApp(const NCERTTutorApp());
}

// -----------------------------------------------------------------------------
// APP ROOT
// -----------------------------------------------------------------------------
class NCERTTutorApp extends StatelessWidget {
  const NCERTTutorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NCERT AI Tutor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const LoadingScreen(),
    );
  }
}

// -----------------------------------------------------------------------------
// 1. LOADING SCREEN
// -----------------------------------------------------------------------------
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  String _status = "Initializing...";
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _startInitialization();
  }

  Future<void> _startInitialization() async {
    try {
      // 1. Load Book Content
      setState(() => _status = "Reading Textbooks...");
      await BookService.instance.loadBookData();

      // 2. Initialize RAG
      setState(() {
        _status = "Preparing Search Engine...";
        _progress = 0.2;
      });
      await RagService.instance.initialize();

      // 3. Download Model
      setState(() => _status = "Downloading AI Model...");
      try {
        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
        ).fromNetwork(kModelUrl, token: kHuggingFaceToken).withProgress((val) {
          if (mounted) {
            setState(() {
              _progress = 0.2 + (val / 100 * 0.6);
              _status = "Downloading AI... $val%";
            });
          }
        }).install();
      } catch (e) {
        if (e.toString().contains("TaskResumeException")) {
          final freshUrl =
              "$kModelUrl?retry=${DateTime.now().millisecondsSinceEpoch}";
          await FlutterGemma.installModel(
            modelType: ModelType.gemmaIt,
          ).fromNetwork(freshUrl, token: kHuggingFaceToken).install();
        } else {
          rethrow;
        }
      }

      setState(() {
        _status = "Loading Model...";
        _progress = 0.9;
      });

      await FlutterGemma.getActiveModel(
        preferredBackend: PreferredBackend.cpu,
        maxTokens: 1024,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      setState(() => _status = "Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.school_rounded, size: 80, color: Colors.indigo),
              const SizedBox(height: 30),
              LinearProgressIndicator(value: _progress, minHeight: 8),
              const SizedBox(height: 20),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 2. HOME SCREEN
// -----------------------------------------------------------------------------
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _openChat(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const SubjectSelectionDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("NCERT Class 9 Tutor"),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MenuButton(
              icon: Icons.chat_bubble_outline,
              label: "Chat with Tutor",
              color: Colors.blue.shade100,
              onTap: () => _openChat(context),
            ),
            const SizedBox(height: 20),
            _MenuButton(
              icon: Icons.quiz_outlined,
              label: "Take a Quiz",
              color: Colors.orange.shade100,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ChapterSelectionScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Subject Selection Dialog (Chat)
class SubjectSelectionDialog extends StatefulWidget {
  const SubjectSelectionDialog({super.key});

  @override
  State<SubjectSelectionDialog> createState() => _SubjectSelectionDialogState();
}

class _SubjectSelectionDialogState extends State<SubjectSelectionDialog> {
  bool _englishSelected = false;
  bool _scienceSelected = false;

  void _startChat() {
    List<String> selectedSubjects = [];
    if (_englishSelected) selectedSubjects.add("English");
    if (_scienceSelected) selectedSubjects.add("Science");

    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(enabledSubjects: selectedSubjects),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Select Subject"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Choose subjects to filter context (Optional)"),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: const Text("English"),
            value: _englishSelected,
            onChanged: (val) => setState(() => _englishSelected = val!),
          ),
          CheckboxListTile(
            title: const Text("Science"),
            value: _scienceSelected,
            onChanged: (val) => setState(() => _scienceSelected = val!),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(onPressed: _startChat, child: const Text("Start Chat")),
      ],
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 250,
        height: 150,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 50, color: Colors.black87),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 3. QUIZ FEATURE (UPDATED: Subject Filtering)
// -----------------------------------------------------------------------------

// Screen 3A: Chapter Selection
class ChapterSelectionScreen extends StatefulWidget {
  const ChapterSelectionScreen({super.key});

  @override
  State<ChapterSelectionScreen> createState() => _ChapterSelectionScreenState();
}

class _ChapterSelectionScreenState extends State<ChapterSelectionScreen> {
  String _selectedSubject = "English"; // Default

  @override
  Widget build(BuildContext context) {
    // Get chapters filtered by the selected subject
    final chapters = BookService.instance.getChaptersForSubject(
      _selectedSubject,
    );

    return Scaffold(
      appBar: AppBar(title: const Text("Select Chapter")),
      body: Column(
        children: [
          // Subject Toggle
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.indigo.shade50,
            child: Row(
              children: [
                const Text(
                  "Subject: ",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: const Text("English"),
                  selected: _selectedSubject == "English",
                  onSelected: (b) =>
                      setState(() => _selectedSubject = "English"),
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: const Text("Science"),
                  selected: _selectedSubject == "Science",
                  onSelected: (b) =>
                      setState(() => _selectedSubject = "Science"),
                ),
              ],
            ),
          ),
          // Chapter List
          Expanded(
            child: ListView.builder(
              itemCount: chapters.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _selectedSubject == "English"
                          ? Colors.blue.shade100
                          : Colors.green.shade100,
                      child: Text("${index + 1}"),
                    ),
                    title: Text(chapter),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QuizPlayScreen(
                            chapterTitle: chapter,
                            subject: _selectedSubject, // Pass subject!
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Screen 3B: Playing the Quiz
class QuizPlayScreen extends StatefulWidget {
  final String chapterTitle;
  final String subject; // New Parameter

  const QuizPlayScreen({
    super.key,
    required this.chapterTitle,
    required this.subject,
  });

  @override
  State<QuizPlayScreen> createState() => _QuizPlayScreenState();
}

class _QuizPlayScreenState extends State<QuizPlayScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _questionData;
  String? _selectedOption;
  bool _isAnswerRevealed = false;
  String? _error;
  InferenceChat? _chatSession;
  int _questionsGeneratedCount = 0;

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

      if (_chatSession == null || _questionsGeneratedCount >= 5) {
        _chatSession = null;
        await Future.delayed(const Duration(seconds: 1));
        final model = await FlutterGemma.getActiveModel(
          preferredBackend: PreferredBackend.cpu,
        );
        _chatSession = await model.createChat();
        _questionsGeneratedCount = 0;
      }

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
      _questionsGeneratedCount++;

      // Parsing
      Map<String, dynamic> data;
      try {
        String jsonStr = response.replaceAll(RegExp(r'```json|```'), '').trim();
        int start = jsonStr.indexOf('{');
        int end = jsonStr.lastIndexOf('}');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Quiz: ${widget.chapterTitle}")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: ElevatedButton(
                onPressed: _generateNewQuestion,
                child: const Text("Retry"),
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
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.indigo.shade100),
                    ),
                    child: Text(
                      _questionData!['question'],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ...(_questionData!['options'] as List).map((option) {
                    bool isSelected = _selectedOption == option;
                    bool isCorrect = option == _questionData!['correct_answer'];
                    Color tileColor = Colors.white;

                    if (_isAnswerRevealed) {
                      if (isCorrect)
                        tileColor = Colors.green.shade100;
                      else if (isSelected)
                        tileColor = Colors.red.shade100;
                    } else if (isSelected) {
                      tileColor = Colors.indigo.shade100;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isAnswerRevealed
                              ? null
                              : () => setState(() => _selectedOption = option),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: tileColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              option,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _selectedOption == null
                        ? null
                        : (_isAnswerRevealed
                              ? _generateNewQuestion
                              : () => setState(() => _isAnswerRevealed = true)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isAnswerRevealed
                          ? Colors.indigo
                          : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                    child: Text(
                      _isAnswerRevealed ? "Next Question" : "Check Answer",
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// 4. CHAT SCREEN (Unchanged)
// -----------------------------------------------------------------------------
class ChatScreen extends StatefulWidget {
  final List<String> enabledSubjects;

  const ChatScreen({super.key, this.enabledSubjects = const []});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isGenerating = false;
  InferenceChat? _chatSession;

  @override
  void dispose() {
    _chatSession = null;
    super.dispose();
  }

  void _resetChat() {
    setState(() {
      _messages.clear();
      _chatSession = null;
      _isGenerating = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Chat history cleared!")));
  }

  Future<void> _handleSend() async {
    if (_textController.text.trim().isEmpty || _isGenerating) return;

    final query = _textController.text;
    _textController.clear();

    setState(() {
      _messages.add(ChatMessage(text: query, isUser: true));
      _isGenerating = true;
      _messages.add(
        ChatMessage(
          text:
              "Searching ${widget.enabledSubjects.isEmpty ? 'all books' : widget.enabledSubjects.join(', ')}...",
          isUser: false,
          isStreaming: true,
        ),
      );
    });

    try {
      String context = await RagService.instance.searchForContext(
        query,
        subjects: widget.enabledSubjects,
      );

      String prompt =
          """You are a AI Tutor. Answer based on this context:
$context

Student: $query
Answer:
""";

      if (_chatSession == null) {
        final model = await FlutterGemma.getActiveModel(
          preferredBackend: PreferredBackend.cpu,
        );
        _chatSession = await model.createChat();
      }

      await _chatSession!.addQueryChunk(
        Message.text(text: prompt, isUser: true),
      );

      setState(() => _messages.last = _messages.last.copyWith(text: ""));

      int badTokenCount = 0;
      final stream = _chatSession!.generateChatResponseAsync().timeout(
        const Duration(seconds: 30),
      );

      await for (final event in stream) {
        if (event is TextResponse && event.token.isNotEmpty) {
          String token = event.token;
          if (token.contains('<bos>') || token.contains('<eos>')) {
            badTokenCount++;
            if (badTokenCount > 5) break;
            continue;
          }
          setState(() {
            final last = _messages.last;
            _messages.last = last.copyWith(text: last.text + token);
          });
        }
      }
    } catch (e) {
      setState(
        () => _messages.last = _messages.last.copyWith(text: "Error: $e"),
      );
      _chatSession = null;
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.enabledSubjects.isEmpty
              ? "Chat (All)"
              : "Chat (${widget.enabledSubjects.join('+')})",
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isGenerating ? null : _resetChat,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      "Ask me anything!",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) => ChatBubble(message: _messages[i]),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: "Ask a question...",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _isGenerating ? null : _handleSend,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SERVICES (UPDATED FOR SCIENCE + ENGLISH)
// -----------------------------------------------------------------------------

class BookService {
  static final BookService instance = BookService._();
  BookService._();

  // Store chapters separately: { "English": [...], "Science": [...] }
  Map<String, List<Map<String, dynamic>>> _chaptersBySubject = {
    "English": [],
    "Science": [],
  };

  Future<void> loadBookData() async {
    try {
      // 1. Load English
      final engJson = await rootBundle.loadString('assets/class9_english.json');
      final engData = jsonDecode(engJson);
      _chaptersBySubject["English"] = List<Map<String, dynamic>>.from(
        engData['Chapters'],
      );

      // 2. Load Science
      final sciJson = await rootBundle.loadString('assets/class9_science.json');
      final sciData = jsonDecode(sciJson);

      // Science JSON sometimes uses lowercase 'chapters' or Uppercase
      final sciList = sciData['Chapters'] ?? sciData['chapters'];
      if (sciList != null) {
        _chaptersBySubject["Science"] = List<Map<String, dynamic>>.from(
          sciList,
        );
      }

      debugPrint(
        "Books Loaded. Eng: ${_chaptersBySubject['English']!.length}, Sci: ${_chaptersBySubject['Science']!.length}",
      );
    } catch (e) {
      debugPrint("Failed to load books: $e");
    }
  }

  List<String> getChaptersForSubject(String subject) {
    if (!_chaptersBySubject.containsKey(subject)) return [];

    return _chaptersBySubject[subject]!
        .map((c) => c['chapter_title'].toString())
        .toList();
  }

  String getRandomContextForChapter(String chapterTitle, String subject) {
    // 1. Get Chapters for specific subject
    final chapters = _chaptersBySubject[subject];
    if (chapters == null) return "";

    // 2. Find the Chapter object
    final chapter = chapters.firstWhere(
      (c) => c['chapter_title'] == chapterTitle,
      orElse: () => <String, dynamic>{}, // Empty map fallback
    );

    if (chapter.isEmpty) return "";

    // 3. Get Topics
    final topics = chapter['topics'] as List?;
    if (topics == null || topics.isEmpty) return "";

    // 4. Randomly Select Context
    var random = Random();
    var topic = topics[random.nextInt(topics.length)];

    String content = topic['content']?.toString() ?? "";
    if (content.length > 350) {
      content = content.substring(0, 350) + "...";
    }

    return "SUBJECT: $subject\nCHAPTER: $chapterTitle\nTOPIC: ${topic['topic'] ?? 'General'}\nCONTENT: $content";
  }
}

class RagService {
  static final RagService instance = RagService._();
  RagService._();

  Interpreter? _interpreter;
  Database? _db;
  Map<String, int>? _vocab;

  Future<void> initialize() async {
    try {
      final vocabStr = await rootBundle.loadString('assets/vocab.txt');
      _vocab = {};
      final lines = vocabStr.split('\n');
      for (var i = 0; i < lines.length; i++) _vocab![lines[i].trim()] = i;

      _interpreter = await Interpreter.fromAsset(
        'assets/mobile_embedding.tflite',
      );

      var dbPath = p.join(await getDatabasesPath(), "class9_complete.db");
      ByteData data = await rootBundle.load("assets/class9_complete.db");
      await File(dbPath).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      _db = await openDatabase(dbPath, readOnly: true);
    } catch (e) {
      debugPrint("RAG Init Warning: $e");
    }
  }

  Future<String> searchForContext(
    String query, {
    List<String> subjects = const [],
  }) async {
    if (_db == null || _interpreter == null) return "";
    try {
      List<double> vector = _getEmbedding(query);
      String whereClause = "";
      List<String> whereArgs = [];

      if (subjects.isNotEmpty) {
        List<String> bookNames = [];
        if (subjects.contains("English"))
          bookNames.addAll(['Beehive', 'Moments', 'Words & Expressions 1']);
        if (subjects.contains("Science")) bookNames.add('Science');

        if (bookNames.isNotEmpty) {
          String placeholders = List.filled(bookNames.length, '?').join(',');
          whereClause = "WHERE book_source IN ($placeholders)";
          whereArgs = bookNames;
        }
      }

      final rows = await _db!.rawQuery(
        'SELECT * FROM knowledge_base $whereClause',
        whereArgs.isNotEmpty ? whereArgs : null,
      );

      List<Map<String, dynamic>> scored = [];
      for (var row in rows) {
        Uint8List blob = row['embedding'] as Uint8List;
        var buffer = blob.buffer.asByteData();
        double score = 0.0;
        for (int i = 0; i < min(vector.length, blob.lengthInBytes ~/ 4); i++) {
          score += vector[i] * buffer.getFloat32(i * 4, Endian.little);
        }
        scored.add({'score': score, 'text': row['display_text']});
      }
      scored.sort(
        (a, b) => (b['score'] as double).compareTo(a['score'] as double),
      );
      return scored.take(3).map((e) => e['text'].toString()).join("\n");
    } catch (e) {
      return "";
    }
  }

  List<double> _getEmbedding(String text) {
    if (_vocab == null) return List.filled(384, 0.0);
    List<int> ids = [101];
    text.toLowerCase().split(' ').forEach((w) {
      if (_vocab!.containsKey(w)) ids.add(_vocab![w]!);
    });
    ids.add(102);
    if (ids.length < 128)
      ids.addAll(List.filled(128 - ids.length, 0));
    else
      ids = ids.sublist(0, 128);
    var output = List.filled(384, 0.0).reshape([1, 384]);
    _interpreter!.run([ids, List.filled(128, 1)], {0: output});
    return List<double>.from(output[0]);
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isStreaming;
  ChatMessage({
    required this.text,
    required this.isUser,
    this.isStreaming = false,
  });
  ChatMessage copyWith({String? text, bool? isStreaming}) => ChatMessage(
    text: text ?? this.text,
    isUser: isUser,
    isStreaming: isStreaming ?? this.isStreaming,
  );
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const ChatBubble({super.key, required this.message});
  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? Colors.indigo.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(message.text),
      ),
    );
  }
}
