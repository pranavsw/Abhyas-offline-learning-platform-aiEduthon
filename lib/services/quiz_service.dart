import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class QuizResult {
  final int? id;
  final String subject;
  final String chapter;
  final String question;
  final List<String> options;
  final String correctAnswer;
  final String selectedAnswer;
  final int timestamp;
  final bool isCorrect;
  final bool synced;

  QuizResult({
    this.id,
    required this.subject,
    required this.chapter,
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.selectedAnswer,
    required this.timestamp,
    required this.isCorrect,
    this.synced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'subject': subject,
      'chapter': chapter,
      'question': question,
      'options': jsonEncode(options),
      'correct_answer': correctAnswer,
      'selected_answer': selectedAnswer,
      'timestamp': timestamp,
      'is_correct': isCorrect ? 1 : 0,
      'synced': synced ? 1 : 0,
    };
  }

  factory QuizResult.fromMap(Map<String, dynamic> map) {
    return QuizResult(
      id: map['id'],
      subject: map['subject'],
      chapter: map['chapter'],
      question: map['question'],
      options: List<String>.from(jsonDecode(map['options'])),
      correctAnswer: map['correct_answer'],
      selectedAnswer: map['selected_answer'],
      timestamp: map['timestamp'],
      isCorrect: map['is_correct'] == 1,
      synced: (map['synced'] ?? 0) == 1,
    );
  }
}

class QuizService {
  static final QuizService instance = QuizService._();
  QuizService._();

  Database? _db;

  Future<void> initialize() async {
    var dbPath = p.join(await getDatabasesPath(), "quiz_history.db");
    _db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE history('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'subject TEXT, '
          'chapter TEXT, '
          'question TEXT, '
          'options TEXT, '
          'correct_answer TEXT, '
          'selected_answer TEXT, '
          'timestamp INTEGER, '
          'is_correct INTEGER, '
          'synced INTEGER DEFAULT 0)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE history ADD COLUMN synced INTEGER DEFAULT 0',
          );
        }
      },
    );
  }

  Future<void> saveResult(QuizResult result) async {
    if (_db == null) await initialize();
    await _db!.insert('history', result.toMap());
  }

  Future<List<QuizResult>> getHistory() async {
    if (_db == null) await initialize();
    final List<Map<String, dynamic>> maps = await _db!.query(
      'history',
      orderBy: 'timestamp DESC',
    );
    return List.generate(maps.length, (i) => QuizResult.fromMap(maps[i]));
  }

  Future<Map<String, dynamic>> getStats() async {
    if (_db == null) await initialize();
    final total = Sqflite.firstIntValue(
      await _db!.rawQuery('SELECT COUNT(*) FROM history'),
    );
    final correct = Sqflite.firstIntValue(
      await _db!.rawQuery('SELECT COUNT(*) FROM history WHERE is_correct = 1'),
    );
    return {'total': total ?? 0, 'correct': correct ?? 0};
  }
}
