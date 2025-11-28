import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  List<Map<String, dynamic>> getTopicsForChapter(
    String chapterTitle,
    String subject,
  ) {
    final chapters = _chaptersBySubject[subject];
    if (chapters == null) return [];

    final chapter = chapters.firstWhere(
      (c) => c['chapter_title'] == chapterTitle,
      orElse: () => <String, dynamic>{},
    );

    if (chapter.isEmpty) return [];
    return List<Map<String, dynamic>>.from(chapter['topics'] ?? []);
  }

  List<String> getAvailableSubjects() {
    return _chaptersBySubject.keys.toList();
  }
}
