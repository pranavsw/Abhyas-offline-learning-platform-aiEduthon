import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// -----------------------------------------------------------------------------
// CONFIGURATION
// -----------------------------------------------------------------------------

// !!! IMPORTANT !!!
// Replace with your actual token from https://huggingface.co/settings/tokens
const String kHuggingFaceToken = "YOUR_HUGGING_FACE_TOKEN_HERE";

const String kModelUrl =
    'https://huggingface.co/google/gemma-2b-it-tflite/resolve/main/gemma-2b-it-cpu-int4.bin';

// -----------------------------------------------------------------------------
// MAIN ENTRY POINT
// -----------------------------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Gemma
  await FlutterGemma.initialize();

  runApp(const GemmaChatApp());
}

// -----------------------------------------------------------------------------
// APP ROOT
// -----------------------------------------------------------------------------
class GemmaChatApp extends StatelessWidget {
  const GemmaChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NCERT AI Tutor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

// -----------------------------------------------------------------------------
// CHAT SCREEN
// -----------------------------------------------------------------------------
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  // AI Components
  InferenceModel? _inferenceModel;
  InferenceChat? _activeChat;
  final RagService _ragService = RagService(); // The RAG Engine

  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  bool _isSystemReady = false;
  bool _isGenerating = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _setupSystem();
  }

  Future<void> _setupSystem() async {
    setState(() {
      _isDownloading = true;
      _statusMessage = "Initializing AI System...";
    });

    try {
      // 1. Initialize RAG (Database + Embedding Model)
      await _ragService.initialize();
      debugPrint("RAG Engine Ready");

      // 2. Install/Load Gemma (CPU Version for mobile compatibility)
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(kModelUrl, token: kHuggingFaceToken)
          .withProgress((progress) {
            if (mounted) {
              setState(() {
                _downloadProgress = progress.toDouble() / 100.0;
                _statusMessage = "Downloading Gemma: $progress%";
              });
            }
          })
          .install();

      if (mounted) {
        setState(() {
          _statusMessage = "Loading Gemma into RAM...";
        });
      }

      _inferenceModel = await FlutterGemma.getActiveModel(
        preferredBackend: PreferredBackend.cpu,
        maxTokens: 1024,
      );

      if (_inferenceModel != null) {
        _activeChat = await _inferenceModel!.createChat();
      }

      if (mounted) {
        setState(() {
          _isSystemReady = true;
          _isDownloading = false;
          _statusMessage = null;
          _messages.add(
            ChatMessage(
              text:
                  "Class 9 English Tutor Ready! Ask me about 'The Fun They Had' or 'Evelyn Glennie'.",
              isUser: false,
            ),
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _statusMessage = "Error: ${e.toString()}";
        });
      }
      debugPrint("Setup Error: $e");
    }
  }

  Future<void> _handleSend() async {
    if (_textController.text.trim().isEmpty ||
        !_isSystemReady ||
        _isGenerating) {
      return;
    }

    final userQuery = _textController.text;
    _textController.clear();

    setState(() {
      _messages.add(ChatMessage(text: userQuery, isUser: true));
      _isGenerating = true;
      _messages.add(
        ChatMessage(
          text: "Searching textbook...",
          isUser: false,
          isStreaming: true,
        ),
      );
    });
    _scrollToBottom();

    try {
      if (_activeChat == null) throw Exception("Chat not initialized");

      // --- STEP 1: RAG SEARCH ---
      // We search the local DB before talking to Gemma
      String contextDocs = await _ragService.searchForContext(userQuery);

      String fullPrompt;
      if (contextDocs.isEmpty) {
        fullPrompt = userQuery; // Fallback if no docs found
      } else {
        // Inject the textbook content into the prompt
        fullPrompt =
            """
You are an expert Class 9 English teacher. Use the following textbook excerpts to answer the student's question accurately.

TEXTBOOK CONTEXT:
$contextDocs

STUDENT QUESTION: $userQuery
ANSWER:
""";
      }

      debugPrint("Sending Prompt to Gemma: $fullPrompt");

      // --- STEP 2: GEMMA GENERATION ---
      final message = Message.text(text: fullPrompt, isUser: true);
      await _activeChat!.addQueryChunk(message);
      final stream = _activeChat!.generateChatResponseAsync();

      // Clear the "Searching..." placeholder
      setState(() {
        _messages.last = _messages.last.copyWith(text: "");
      });

      await for (final event in stream) {
        if (event is TextResponse) {
          final content = event.token;
          if (content.isNotEmpty) {
            setState(() {
              final lastMsg = _messages.last;
              _messages.last = lastMsg.copyWith(text: lastMsg.text + content);
            });
            _scrollToBottom();
          }
        }
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(text: "Error: $e", isUser: false));
      });
    } finally {
      setState(() {
        _isGenerating = false;
        if (_messages.isNotEmpty) {
          _messages.last = _messages.last.copyWith(isStreaming: false);
        }
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("NCERT RAG Chat"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isSystemReady)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Icon(Icons.library_books, color: Colors.indigo),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_isDownloading || _statusMessage != null)
            Container(
              color: Colors.amber.shade100,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    _statusMessage ?? "Working...",
                    textAlign: TextAlign.center,
                  ),
                  if (_isDownloading)
                    LinearProgressIndicator(value: _downloadProgress),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) =>
                  ChatBubble(message: _messages[index]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    enabled: _isSystemReady && !_isGenerating,
                    decoration: InputDecoration(
                      hintText: "Ask a question...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: (_isSystemReady && !_isGenerating)
                      ? _handleSend
                      : null,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ragService.dispose();
    super.dispose();
  }
}

// -----------------------------------------------------------------------------
// RAG SERVICE (Simplified - Works on Main Isolate)
// -----------------------------------------------------------------------------
class RagService {
  Interpreter? _interpreter;
  Database? _db;
  Map<String, int>? _vocab;
  bool isReady = false;

  Future<void> initialize() async {
    try {
      // 1. Load Tokenizer
      final vocabString = await rootBundle.loadString('assets/vocab.txt');
      _vocab = {};
      final lines = vocabString.split('\n');
      for (var i = 0; i < lines.length; i++) {
        _vocab![lines[i].trim()] = i;
      }
      debugPrint("Vocab loaded: ${_vocab!.length} tokens");

      // 2. Load Embedding Model (TFLite)
      try {
        _interpreter = await Interpreter.fromAsset(
          'assets/mobile_embedding.tflite',
        );
        debugPrint("TFLite model loaded successfully");
        debugPrint("Input shape: ${_interpreter!.getInputTensor(0).shape}");
        debugPrint("Output shape: ${_interpreter!.getOutputTensor(0).shape}");
      } catch (e) {
        debugPrint("TFLite model load failed: $e");
        // Continue without embeddings - will use fallback
      }

      // 3. Setup Database
      var databasesPath = await getDatabasesPath();
      var dbPath = join(databasesPath, "class9_complete.db");

      // Copy DB from assets
      ByteData data = await rootBundle.load("assets/class9_complete.db");
      List<int> bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await File(dbPath).writeAsBytes(bytes, flush: true);

      _db = await openDatabase(dbPath, readOnly: true);
      debugPrint("Database opened successfully");

      isReady = true;
      debugPrint("RAG Engine Ready");
    } catch (e) {
      debugPrint("RAG Init Error: $e");
      // Don't rethrow - allow app to continue without RAG
    }
  }

  Future<String> searchForContext(String query) async {
    if (!isReady || _db == null) {
      debugPrint("RAG not ready, returning empty context");
      return "";
    }

    try {
      // If embedding model failed to load, use simple text search
      if (_interpreter == null) {
        return await _simpleTextSearch(query);
      }

      // 1. Generate embedding for query
      List<double> queryVector = await _getEmbedding(query);

      if (queryVector.isEmpty || queryVector.every((v) => v == 0.0)) {
        debugPrint("Embedding failed, falling back to text search");
        return await _simpleTextSearch(query);
      }

      // 2. Fetch all chunks from DB
      final rows = await _db!.query('knowledge_base');
      debugPrint("Searching ${rows.length} knowledge base entries");

      List<Map<String, dynamic>> scoredResults = [];

      for (var row in rows) {
        // Decode binary blob back to float list
        Uint8List blob = row['embedding'] as Uint8List;
        var buffer = blob.buffer.asByteData();

        // Dot Product (Similarity Score)
        double score = 0.0;
        int vectorLength = blob.lengthInBytes ~/ 4;

        for (int i = 0; i < min(queryVector.length, vectorLength); i++) {
          score += queryVector[i] * buffer.getFloat32(i * 4, Endian.little);
        }

        scoredResults.add({
          'score': score,
          'text': row['display_text'],
          'header': row['context_header'],
        });
      }

      // 3. Sort by highest score
      scoredResults.sort(
        (a, b) => (b['score'] as double).compareTo(a['score'] as double),
      );

      debugPrint("Top score: ${scoredResults.first['score']}");

      // 4. Return top 3 results
      return scoredResults
          .take(3)
          .map((e) => "[SOURCE: ${e['header']}]\n${e['text']}")
          .join("\n\n---\n\n");
    } catch (e) {
      debugPrint("RAG Search Error: $e");
      return await _simpleTextSearch(query);
    }
  }

  // Fallback: Simple keyword-based search
  Future<String> _simpleTextSearch(String query) async {
    try {
      final keywords = query.toLowerCase().split(' ');
      final rows = await _db!.query('knowledge_base');

      List<Map<String, dynamic>> scoredResults = [];

      for (var row in rows) {
        String text = (row['display_text'] as String).toLowerCase();
        int score = 0;

        for (var keyword in keywords) {
          if (keyword.length > 2 && text.contains(keyword)) {
            score += keyword.length;
          }
        }

        if (score > 0) {
          scoredResults.add({
            'score': score,
            'text': row['display_text'],
            'header': row['context_header'],
          });
        }
      }

      scoredResults.sort(
        (a, b) => (b['score'] as int).compareTo(a['score'] as int),
      );

      if (scoredResults.isEmpty) {
        return "";
      }

      return scoredResults
          .take(3)
          .map((e) => "[SOURCE: ${e['header']}]\n${e['text']}")
          .join("\n\n---\n\n");
    } catch (e) {
      debugPrint("Text search error: $e");
      return "";
    }
  }

  Future<List<double>> _getEmbedding(String text) async {
    if (_interpreter == null || _vocab == null) {
      return [];
    }

    try {
      // Tokenize
      List<int> ids = [_vocab!['[CLS]'] ?? 101];
      final words = text
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .split(RegExp(r'\s+'));

      for (var word in words) {
        if (_vocab!.containsKey(word)) {
          ids.add(_vocab![word]!);
        } else {
          ids.add(_vocab!['[UNK]'] ?? 100);
        }
      }
      ids.add(_vocab!['[SEP]'] ?? 102);

      // Get model input shape
      var inputShape = _interpreter!.getInputTensor(0).shape;
      int modelSequenceLength = inputShape[1];

      var attentionMask = List.filled(ids.length, 1);

      // Pad or Truncate
      if (ids.length < modelSequenceLength) {
        int padCount = modelSequenceLength - ids.length;
        ids.addAll(List.filled(padCount, 0));
        attentionMask.addAll(List.filled(padCount, 0));
      } else if (ids.length > modelSequenceLength) {
        ids = ids.sublist(0, modelSequenceLength);
        attentionMask = attentionMask.sublist(0, modelSequenceLength);
      }

      // Run Inference
      var input = [ids, attentionMask];
      var output = List.filled(1 * 384, 0.0).reshape([1, 384]);

      _interpreter!.runForMultipleInputs(input, {0: output});

      return List<double>.from(output[0]);
    } catch (e) {
      debugPrint("Embedding generation error: $e");
      return [];
    }
  }

  void dispose() {
    _interpreter?.close();
    _db?.close();
  }
}

// -----------------------------------------------------------------------------
// UI WIDGETS
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
  ChatMessage copyWith({String? text, bool? isStreaming}) {
    return ChatMessage(
      text: text ?? this.text,
      isUser: isUser,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? Colors.indigo : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.text,
          style: TextStyle(color: isUser ? Colors.white : Colors.black87),
        ),
      ),
    );
  }
}
