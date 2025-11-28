import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

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
      // Only copy if not exists or force update (logic can be improved)
      if (!await File(dbPath).exists()) {
        ByteData data = await rootBundle.load("assets/class9_complete.db");
        await File(dbPath).writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      _db = await openDatabase(dbPath, readOnly: true);
    } catch (e) {
      print("RAG Init Warning: $e");
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
