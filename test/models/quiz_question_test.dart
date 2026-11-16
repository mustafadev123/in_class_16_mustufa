import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ica16_a/models/quiz_question.dart';

void main() {
  final valid = <String, dynamic>{
    'category': 'General Knowledge',
    'difficulty': 'easy',
    'type': 'multiple',
    'question': 'Tom &amp; Jerry?',
    'correct_answer': 'Yes',
    'incorrect_answers': ['No', 'Maybe', 'Unknown'],
  };

  test('decodes and caches exactly four choices', () {
    final question = QuizQuestion.fromJson(valid, random: Random(1));
    expect(question.text, 'Tom & Jerry?');
    expect(question.choices, hasLength(4));
    expect(question.choices, contains(question.correctAnswer));
  });

  test('rejects duplicate decoded choices', () {
    expect(
      () => QuizQuestion.fromJson({...valid, 'incorrect_answers': ['Yes', 'No', 'Maybe']}),
      throwsFormatException,
    );
  });
}
