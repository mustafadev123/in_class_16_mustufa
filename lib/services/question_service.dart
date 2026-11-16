import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/quiz_question.dart';

class QuestionService {
  QuestionService({http.Client? client}) : _client = client ?? http.Client();

  static final uri = Uri.https('opentdb.com', '/api.php', {
    'amount': '10',
    'category': '9',
    'difficulty': 'easy',
    'type': 'multiple',
  });

  final http.Client _client;
  DateTime? _lastRequestAt;

  Future<List<QuizQuestion>> fetchQuestions() async {
    final now = DateTime.now();
    if (_lastRequestAt != null &&
        now.difference(_lastRequestAt!).inSeconds < 5) {
      throw StateError('Please wait five seconds before retrying.');
    }
    _lastRequestAt = now;
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw QuestionRequestException('HTTP ${response.statusCode}');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const QuestionRequestException(
          'The question service returned bad JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const QuestionRequestException('Unexpected response shape.');
    }
    if (decoded['response_code'] != 0) {
      throw QuestionRequestException(
          'OpenTDB code ${decoded['response_code']}');
    }
    final results = decoded['results'];
    if (results is! List || results.length != 10) {
      throw const QuestionRequestException(
          'Exactly 10 questions are required.');
    }
    try {
      return List.unmodifiable(results.map((raw) {
        if (raw is! Map<String, dynamic>) {
          throw const FormatException('Invalid question object.');
        }
        return QuizQuestion.fromJson(raw);
      }));
    } on FormatException catch (error) {
      throw QuestionRequestException(error.message);
    }
  }
}

class QuestionRequestException implements Exception {
  const QuestionRequestException(this.message);
  final String message;
  @override
  String toString() => message;
}
