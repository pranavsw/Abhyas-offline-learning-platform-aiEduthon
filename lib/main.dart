import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import 'screens/main_navigation_screen.dart';
import 'services/book_service.dart';
import 'services/rag_service.dart';
import 'services/quiz_service.dart';

// -----------------------------------------------------------------------------
// CONFIGURATION
// -----------------------------------------------------------------------------
const String kHuggingFaceToken = "YOUR_HF_TOKEN"; // User needs to replace this
const String kModelUrl =
    'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize();
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => ThemeProvider())],
      child: const AbhyasApp(),
    ),
  );
}

class AbhyasApp extends StatelessWidget {
  const AbhyasApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'ABHYAS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      home: const LoadingScreen(),
    );
  }
}

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

      // 3. Initialize Quiz Service
      await QuizService.instance.initialize();

      // 4. Download Model
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
          // If model is already installed or other error, we might proceed or rethrow
          // For now, let's assume if it fails it might be because it's already there or network issue
          // But we should try to proceed to check if model works
          debugPrint("Model install warning: $e");
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
          MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
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
              const Icon(
                Icons.school_rounded,
                size: 80,
                color: AppTheme.cyanAccent,
              ),
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
