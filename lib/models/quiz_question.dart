import 'dart:math';

import 'package:html_unescape/html_unescape.dart';

class QuizQuestion {
  QuizQuestion._({
    required this.text,
    required this.correctAnswer,
    required this.choices,
  });

  final String text;
  final String correctAnswer;
  final List<String> choices;

  factory QuizQuestion.fromJson(
    Map<String, dynamic> json, {
    Random? random,
  }) {
    if (json['category'] != 'General Knowledge' ||
        json['difficulty'] != 'easy' ||
        json['type'] != 'multiple') {
      throw const FormatException('Question metadata does not match Class A.');
    }

    final decode = HtmlUnescape().convert;
    final rawIncorrect = json['incorrect_answers'];
    if (json['question'] is! String ||
        json['correct_answer'] is! String ||
        rawIncorrect is! List ||
        rawIncorrect.length != 3 ||
        rawIncorrect.any((answer) => answer is! String)) {
      throw const FormatException('Question fields are incomplete.');
    }

    final question = decode(json['question'] as String).trim();
    final correct = decode(json['correct_answer'] as String).trim();
    final choices = <String>[
      correct,
      ...rawIncorrect.cast<String>().map((answer) => decode(answer).trim()),
    ];
    if (question.isEmpty ||
        choices.any((choice) => choice.isEmpty) ||
        choices.toSet().length != 4) {
      throw const FormatException('Question has empty or duplicate decoded text.');
    }
    choices.shuffle(random ?? Random.secure());
    return QuizQuestion._(
      text: question,
      correctAnswer: correct,
      choices: List.unmodifiable(choices),
    );
  }
}

