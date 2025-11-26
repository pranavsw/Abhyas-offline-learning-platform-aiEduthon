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

// const String kModelUrl =
// 'https://huggingface.co/google/gemma-2b-it-tflite/resolve/main/gemma-2b-it-cpu-int4.bin';

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
// 1. LOADING & INITIALIZATION SCREEN
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
      // 1. Load Book Content (JSON)
      setState(() => _status = "Reading Textbook...");
      await BookService.instance.loadBookData();

      // 2. Initialize RAG Engine (DB & Tokenizer)
      setState(() {
        _status = "Preparing Search Engine...";
        _progress = 0.2;
      });
      await RagService.instance.initialize();

      // 3. Download & Load Gemma Model
      // 3. Download & Load Gemma Model
      setState(() => _status = "Downloading AI Model...");

      try {
        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
        ).fromNetwork(kModelUrl, token: kHuggingFaceToken).withProgress((val) {
          if (mounted) {
            setState(() {
              _progress = 0.2 + (val / 100 * 0.6); // Map 0-100 to 0.2-0.8
              _status = "Downloading AI... $val%";
            });
          }
        }).install();
      } catch (e) {
        // Handle Resume/ETag errors by forcing a fresh download
        if (e.toString().contains("TaskResumeException") ||
            e.toString().contains("ETag")) {
          debugPrint("Download mismatch detected. Retrying with fresh URL...");
          setState(() => _status = "Retrying Download (Fresh)...");

          // Append timestamp to force new download task
          final freshUrl =
              "$kModelUrl?retry=${DateTime.now().millisecondsSinceEpoch}";

          await FlutterGemma.installModel(
            modelType: ModelType.gemmaIt,
          ).fromNetwork(freshUrl, token: kHuggingFaceToken).withProgress((val) {
            if (mounted) {
              setState(() {
                _progress = 0.2 + (val / 100 * 0.6);
                _status = "Downloading (Retry)... $val%";
              });
            }
          }).install();
        } else {
          rethrow;
        }
      }

      setState(() {
        _status = "Loading Model into RAM...";
        _progress = 0.9;
      });

      // Force CPU for compatibility
      await FlutterGemma.getActiveModel(
        preferredBackend: PreferredBackend.cpu,
        maxTokens: 1024,
      );

      // Done!
      if (mounted) {
        Navigator.pushReplacement(
          this.context,
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
// 2. HOME SCREEN (Menu)
// -----------------------------------------------------------------------------
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatScreen()),
              ),
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
// 3. QUIZ FEATURE
// -----------------------------------------------------------------------------

// Screen 3A: Chapter Selection
class ChapterSelectionScreen extends StatelessWidget {
  const ChapterSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chapters = BookService.instance.getAllChapters();

    return Scaffold(
      appBar: AppBar(title: const Text("Select Chapter")),
      body: ListView.builder(
        itemCount: chapters.length,
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          final chapter = chapters[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(child: Text("${index + 1}")),
              title: Text(chapter),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuizPlayScreen(chapterTitle: chapter),
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

// Screen 3B: Playing the Quiz
class QuizPlayScreen extends StatefulWidget {
  final String chapterTitle;
  const QuizPlayScreen({super.key, required this.chapterTitle});

  @override
  State<QuizPlayScreen> createState() => _QuizPlayScreenState();
}

class _QuizPlayScreenState extends State<QuizPlayScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _questionData;
  String? _selectedOption;
  bool _isAnswerRevealed = false;
  String? _error;

  // Persistent chat session to avoid memory leaks
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

    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        // 1. Get Context
        String context = BookService.instance.getRandomContextForChapter(
          widget.chapterTitle,
        );

        if (context.isEmpty) throw "No content available";

        String question = "";
        String correctAnswer = "";
        List<String> options = [];

        // 2. Initialize Model & Chat
        // REFRESH STRATEGY: Re-create session every 5 questions to clear context
        if (_chatSession == null || _questionsGeneratedCount >= 5) {
          debugPrint("Refreshing AI Session...");
          _chatSession = null; // Help GC
          await Future.delayed(
            const Duration(seconds: 1),
          ); // Longer delay for safety

          final model = await FlutterGemma.getActiveModel(
            preferredBackend: PreferredBackend.cpu,
          );
          _chatSession = await model.createChat();
          _questionsGeneratedCount = 0;
        }

        // ---------------------------------------------------------
        // SINGLE STEP: Generate Question, Answer & Distractors (JSON)
        // ---------------------------------------------------------
        final randomId = Random().nextInt(10000);
        String prompt =
            """Context:
$context

Task ID: $randomId
Task: Generate 1 UNIQUE multiple-choice question, its correct answer, and 3 related but wrong options based on the text provided.
Output strictly in JSON format:
{
  "question": "The question text here",
  "answer": "The correct answer here",
  "distractors": ["Wrong option 1", "Wrong option 2", "Wrong option 3"]
}
Do not add any other text.""";

        await _chatSession!.addQueryChunk(
          Message.text(text: prompt, isUser: true),
        );

        String response = "";
        int tokenCount = 0;

        // Add Timeout to prevent infinite loading
        await for (final event
            in _chatSession!.generateChatResponseAsync().timeout(
              const Duration(seconds: 25),
            )) {
          if (event is TextResponse) {
            String t = event.token;
            if (t.contains('<bos>') || t.contains('<eos>')) continue;
            response += t;
            if (++tokenCount > 250) break;
          }
        }

        _questionsGeneratedCount++;

        // Parse JSON
        try {
          String jsonStr = response
              .replaceAll(RegExp(r'```json|```'), '')
              .trim();
          int start = jsonStr.indexOf('{');
          int end = jsonStr.lastIndexOf('}');
          if (start != -1 && end != -1) {
            jsonStr = jsonStr.substring(start, end + 1);
            final data = jsonDecode(jsonStr);
            question = data['question'] ?? "";
            correctAnswer = data['answer'] ?? "";
            if (data['distractors'] is List) {
              List<dynamic> dists = data['distractors'];
              options = dists.map((e) => e.toString().trim()).toList();
            }
          }
        } catch (e) {
          debugPrint("JSON Parse Error: $e");
        }

        if (question.isEmpty || correctAnswer.isEmpty) {
          _useDeterministicFallback(context);
          return;
        }

        // Filter valid distractors
        options = options
            .where(
              (l) =>
                  l.isNotEmpty &&
                  l.toLowerCase() != correctAnswer.toLowerCase(),
            )
            .take(3)
            .toList();

        // Combine & Randomize
        options = [correctAnswer, ...options];

        // Ensure 4 options
        int fallbackCount = 1;
        while (options.length < 4) {
          options.add("Option $fallbackCount");
          fallbackCount++;
        }

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
        return; // Success!
      } catch (e) {
        debugPrint("Quiz Gen Error (Attempt ${retryCount + 1}): $e");

        // Handle Race Condition specifically
        if (e.toString().contains("IllegalStateException") ||
            e.toString().contains("Previous invocation")) {
          debugPrint("Model busy, waiting...");
          await Future.delayed(const Duration(seconds: 2));
          retryCount++;
          continue; // Retry loop
        }

        // If it's not a race condition (e.g. timeout), break and show error or fallback
        _chatSession = null; // Force reset
        break;
      }
    }

    // If all retries failed
    if (mounted) {
      // Try fallback one last time
      try {
        String context = BookService.instance.getRandomContextForChapter(
          widget.chapterTitle,
        );
        _useDeterministicFallback(context);
      } catch (e) {
        setState(() {
          _error = "Failed to generate question. Please try again.";
          _isLoading = false;
        });
      }
    }
  }

  void _useDeterministicFallback(String context) {
    final topicMatch = RegExp(r'TOPIC: (.*)').firstMatch(context);
    String topic = topicMatch?.group(1) ?? "this chapter";
    String question = "What is the main subject discussed in '$topic'?";

    List<String> words = context
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 5)
        .toSet()
        .toList();
    words.shuffle();

    List<String> options = words.take(4).toList();

    // Robust Fallback: Ensure 4 options
    List<String> fillers = [
      "None of the above",
      "All of the above",
      "Information not provided",
      "Check the textbook",
    ];
    int fillerIndex = 0;
    while (options.length < 4) {
      options.add(fillers[fillerIndex % fillers.length]);
      fillerIndex++;
    }

    if (mounted) {
      setState(() {
        _questionData = {
          'question': question,
          'options': options,
          'correct_answer': options[0],
        };
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Quiz: ${widget.chapterTitle}")),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Reading Chapter & Generating Question..."),
                ],
              ),
            )
          : _error != null
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _generateNewQuestion,
                      child: const Text("Retry"),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Question
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

                  // Options
                  ...(_questionData!['options'] as List).map((option) {
                    bool isSelected = _selectedOption == option;
                    bool isCorrect = option == _questionData!['correct_answer'];

                    Color tileColor = Colors.white;
                    Color textColor = Colors.black87;
                    IconData? icon;

                    if (_isAnswerRevealed) {
                      if (isCorrect) {
                        tileColor = Colors.green.shade100;
                        textColor = Colors.green.shade900;
                        icon = Icons.check_circle;
                      } else if (isSelected) {
                        tileColor = Colors.red.shade100;
                        textColor = Colors.red.shade900;
                        icon = Icons.cancel;
                      }
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: tileColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    option,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: textColor,
                                    ),
                                  ),
                                ),
                                if (icon != null) Icon(icon, color: textColor),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),

                  const SizedBox(height: 20),

                  // Bottom Button
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _selectedOption == null
                          ? null
                          : (_isAnswerRevealed
                                ? _generateNewQuestion
                                : () =>
                                      setState(() => _isAnswerRevealed = true)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isAnswerRevealed
                            ? Colors.indigo
                            : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        _isAnswerRevealed ? "Next Question" : "Check Answer",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// 4. CHAT SCREEN (RAG Based)
// -----------------------------------------------------------------------------
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isGenerating = false;

  // Helper to init chat if not ready
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
          text: "Searching Textbook...",
          isUser: false,
          isStreaming: true,
        ),
      );
    });

    try {
      // 1. Search Vector DB
      String context = await RagService.instance.searchForContext(query);

      String prompt =
          """
You are a Class 9 English Tutor. Answer based on this textbook context:
$context

Student: $query
Answer:
""";

      // 2. Generate
      if (_chatSession == null) {
        final model = await FlutterGemma.getActiveModel(
          preferredBackend: PreferredBackend.cpu,
        );
        _chatSession = await model.createChat();
      }

      // Add the context-aware prompt to the model
      await _chatSession!.addQueryChunk(
        Message.text(text: prompt, isUser: true),
      );

      setState(() {
        _messages.last = _messages.last.copyWith(
          text: "",
        ); // Clear loading text
      });

      int badTokenCount = 0;
      // Add timeout to prevent freeze
      final stream = _chatSession!.generateChatResponseAsync().timeout(
        const Duration(seconds: 30),
      );

      await for (final event in stream) {
        if (event is TextResponse && event.token.isNotEmpty) {
          String token = event.token;
          // Infinite loop protection
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
      // If error is timeout or memory, force reset next time
      _chatSession = null;
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chat Tutor"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Clear Chat",
            onPressed: _isGenerating ? null : _resetChat,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      "Ask me anything about Class 9 English!",
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
// SERVICES & HELPERS
// -----------------------------------------------------------------------------

// A. BOOK SERVICE (Handles Raw JSON for Quiz)
class BookService {
  static final BookService instance = BookService._();
  BookService._();

  Map<String, dynamic>? _bookData;

  Future<void> loadBookData() async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/class9_english.json',
      );
      _bookData = jsonDecode(jsonString);
      debugPrint(
        "Book Loaded. Chapters: ${(_bookData!['Chapters'] as List).length}",
      );
    } catch (e) {
      debugPrint("Failed to load book JSON: $e");
    }
  }

  List<String> getAllChapters() {
    if (_bookData == null) return [];
    return (_bookData!['Chapters'] as List)
        .map((c) => c['chapter_title'].toString())
        .toList();
  }

  String getRandomContextForChapter(String chapterTitle) {
    if (_bookData == null) return "";

    // Find Chapter
    final chapters = _bookData!['Chapters'] as List;
    final chapter = chapters.firstWhere(
      (c) => c['chapter_title'] == chapterTitle,
      orElse: () => null,
    );

    if (chapter == null) return "";

    // Get Topics
    final topics = chapter['topics'] as List;
    if (topics.isEmpty) return "";

    // Pick ONLY 1 random topic to avoid memory crash
    var random = Random();
    var topic = topics[random.nextInt(topics.length)];

    // Limit content length to prevent crash (max 300 chars)
    String content = topic['content'].toString();
    if (content.length > 300) {
      content = content.substring(0, 300) + "...";
    }

    return "TOPIC: ${topic['topic']}\nCONTENT: $content";
  }
}

// B. RAG SERVICE (Vector Search for Chat)
class RagService {
  static final RagService instance = RagService._();
  RagService._();

  Interpreter? _interpreter;
  Database? _db;
  Map<String, int>? _vocab;

  Future<void> initialize() async {
    try {
      // Load Tokenizer
      final vocabStr = await rootBundle.loadString('assets/vocab.txt');
      _vocab = {};
      final lines = vocabStr.split('\n');
      for (var i = 0; i < lines.length; i++) _vocab![lines[i].trim()] = i;

      // Load Model
      _interpreter = await Interpreter.fromAsset(
        'assets/mobile_embedding.tflite',
      );

      // Load DB
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

  Future<String> searchForContext(String query) async {
    if (_db == null || _interpreter == null) return "";
    try {
      // Embedding Logic (Simplified for brevity - ensure your vector logic is here)
      List<double> vector = _getEmbedding(query);
      final rows = await _db!.query('knowledge_base');

      // ... perform dot product search ...
      // For safety in this paste, assume simple return if logic is complex
      return rows.take(3).map((e) => e['display_text'].toString()).join("\n");
    } catch (e) {
      return "";
    }
  }

  List<double> _getEmbedding(String text) {
    // Basic tokenizer implementation
    if (_vocab == null) return List.filled(384, 0.0);
    List<int> ids = [101]; // CLS
    text.toLowerCase().split(' ').forEach((w) {
      if (_vocab!.containsKey(w)) ids.add(_vocab![w]!);
    });
    ids.add(102); // SEP

    // Pad to 128 (or whatever your model needs)
    if (ids.length < 128)
      ids.addAll(List.filled(128 - ids.length, 0));
    else
      ids = ids.sublist(0, 128);

    var output = List.filled(384, 0.0).reshape([1, 384]);
    _interpreter!.run([ids, List.filled(128, 1)], {0: output});
    return List<double>.from(output[0]);
  }
}

// C. JSON CLEANER (Crucial for Small Models)
class JsonCleaner {
  static Map<String, dynamic> cleanAndParse(String rawResponse) {
    try {
      // 1. Remove Markdown
      String clean = rawResponse.replaceAll(RegExp(r'```json|```'), '');

      // 2. Find the JSON Object (start '{' and end '}')
      int start = clean.indexOf('{');
      int end = clean.lastIndexOf('}');
      if (start == -1 || end == -1) throw "No JSON found";

      clean = clean.substring(start, end + 1);

      return jsonDecode(clean);
    } catch (e) {
      throw "AI generated invalid JSON. Try again.";
    }
  }
}

// -----------------------------------------------------------------------------
// HELPERS (Chat Bubble)
// -----------------------------------------------------------------------------
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
