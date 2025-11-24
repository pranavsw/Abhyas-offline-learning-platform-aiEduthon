import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

// -----------------------------------------------------------------------------
// CONFIGURATION
// -----------------------------------------------------------------------------

// !!! IMPORTANT !!!
// 1. Go to https://huggingface.co/google/gemma-2b-it-tflite and Click "Agree"
// 2. Get your token from https://huggingface.co/settings/tokens
// 3. Paste it below inside the quotes:
const String kHuggingFaceToken = "HUGGING_FACE_TOKEN";

// UPDATED URL: Switched to CPU model for Emulator compatibility.
// Emulators CANNOT run the GPU model.
const String kModelUrl =
    'https://huggingface.co/google/gemma-2b-it-tflite/resolve/main/gemma-2b-it-cpu-int4.bin';

// -----------------------------------------------------------------------------
// MAIN ENTRY POINT
// -----------------------------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the Gemma plugin
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
      title: 'Gemma Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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

  InferenceModel? _inferenceModel;
  InferenceChat? _activeChat;

  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  bool _isModelReady = false;
  bool _isGenerating = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _setupModel();
  }

  Future<void> _setupModel() async {
    setState(() {
      _isDownloading = true;
      _statusMessage = "Initializing Model (CPU)...";
    });

    try {
      // 1. Install Model (CPU Version)
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(kModelUrl, token: kHuggingFaceToken)
          .withProgress((progress) {
            setState(() {
              _downloadProgress = progress.toDouble() / 100.0;
              _statusMessage = "Downloading Model: $progress%";
            });
          })
          .install();

      setState(() {
        _statusMessage = "Loading into Memory (this may take a moment)...";
      });

      // 2. Get Active Model - FORCE CPU BACKEND
      // Emulators crash on GPU backend because they lack OpenCL support.
      _inferenceModel = await FlutterGemma.getActiveModel(
        preferredBackend: PreferredBackend.cpu,
        maxTokens: 1024,
      );

      // 3. Create Chat Session
      if (_inferenceModel != null) {
        _activeChat = await _inferenceModel!.createChat();
      }

      setState(() {
        _isModelReady = true;
        _isDownloading = false;
        _statusMessage = null;
        _messages.add(
          ChatMessage(
            text: "Gemma 2B (CPU) loaded! Ask me anything.",
            isUser: false,
          ),
        );
      });
    } catch (e) {
      setState(() {
        _isDownloading = false;
        // Convert error to string to display safely
        _statusMessage = "Error: ${e.toString()}";
      });
      debugPrint("Gemma Error: $e");
    }
  }

  Future<void> _handleSend() async {
    if (_textController.text.trim().isEmpty ||
        !_isModelReady ||
        _isGenerating) {
      return;
    }

    final userText = _textController.text;
    _textController.clear();

    setState(() {
      _messages.add(ChatMessage(text: userText, isUser: true));
      _isGenerating = true;
      _messages.add(ChatMessage(text: "", isUser: false, isStreaming: true));
    });

    _scrollToBottom();

    try {
      if (_activeChat == null) throw Exception("Chat not initialized");

      final message = Message.text(text: userText, isUser: true);
      await _activeChat!.addQueryChunk(message);

      final stream = _activeChat!.generateChatResponseAsync();

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
        title: const Text("Gemma Local Chat"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isModelReady)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Icon(Icons.check_circle, color: Colors.green),
            ),
        ],
      ),
      body: Column(
        children: [
          // STATUS AREA (Fixed Overflow Issue)
          if (_isDownloading || _statusMessage != null)
            Container(
              color: Colors.yellow.shade100,
              width: double.infinity,
              // Limit height to prevent overflow on long error messages
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      _statusMessage ?? "Processing...",
                      style: const TextStyle(color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                    if (_isDownloading) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: _downloadProgress),
                    ],
                  ],
                ),
              ),
            ),

          // CHAT AREA
          Expanded(
            child: _messages.isEmpty && _isModelReady
                ? const Center(child: Text("Start a conversation!"))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return ChatBubble(message: _messages[index]);
                    },
                  ),
          ),

          // INPUT AREA
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    enabled: _isModelReady && !_isGenerating,
                    decoration: InputDecoration(
                      hintText: _isGenerating
                          ? "Generating..."
                          : "Type a message...",
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
                  onPressed: (_isModelReady && !_isGenerating)
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
}

// -----------------------------------------------------------------------------
// HELPER WIDGETS
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
    final theme = Theme.of(context);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(16),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
