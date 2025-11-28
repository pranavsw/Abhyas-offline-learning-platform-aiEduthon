import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import '../services/rag_service.dart';
import '../theme/app_theme.dart';

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

  // Local state for selected subjects
  late List<String> _selectedSubjects;

  @override
  void initState() {
    super.initState();
    _selectedSubjects = List.from(widget.enabledSubjects);
  }

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

  void _showSubjectFilter() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Select Subjects"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    title: const Text("English"),
                    value: _selectedSubjects.contains("English"),
                    onChanged: (val) {
                      setStateDialog(() {
                        if (val == true) {
                          _selectedSubjects.add("English");
                        } else {
                          _selectedSubjects.remove("English");
                        }
                      });
                      // Update main screen state as well to reflect changes immediately if needed
                      this.setState(() {});
                    },
                  ),
                  CheckboxListTile(
                    title: const Text("Science"),
                    value: _selectedSubjects.contains("Science"),
                    onChanged: (val) {
                      setStateDialog(() {
                        if (val == true) {
                          _selectedSubjects.add("Science");
                        } else {
                          _selectedSubjects.remove("Science");
                        }
                      });
                      this.setState(() {});
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Done"),
                ),
              ],
            );
          },
        );
      },
    );
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
              "Searching ${_selectedSubjects.isEmpty ? 'all books' : _selectedSubjects.join(', ')}...",
          isUser: false,
          isStreaming: true,
        ),
      );
    });

    try {
      String context = await RagService.instance.searchForContext(
        query,
        subjects: _selectedSubjects,
      );

      String prompt =
          """You are a helpful AI Tutor for students.
Answer the student's question in simple, natural language based on the provided context.
Do NOT generate JSON. Do NOT generate quiz questions. Just explain the answer.

Context:
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
          _selectedSubjects.isEmpty
              ? "AI Tutor (All)"
              : "AI Tutor (${_selectedSubjects.join('+')})",
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showSubjectFilter,
            tooltip: "Filter Subjects",
          ),
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
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.psychology,
                          size: 64,
                          color: Theme.of(context).disabledColor,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "Ask me anything about your subjects!",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) => ChatBubble(message: _messages[i]),
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16.0),
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
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: "Ask a question...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).scaffoldBackgroundColor,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _isGenerating ? null : _handleSend,
                  backgroundColor: AppTheme.cyanAccent,
                  child: const Icon(Icons.send, color: Colors.black),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? (isDark ? Colors.blue.shade900 : Colors.blue.shade100)
              : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: isUser ? const Radius.circular(12) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(12),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser
                ? (isDark ? Colors.white : Colors.black87)
                : (isDark ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }
}
