import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/quiz_question.dart';
import '../services/attempt_repository.dart';
import '../services/question_service.dart';

enum RoundView { loading, requestError, playing, readyToSubmit, submitting, verifying, saveUnknown, permissionDenied, verificationUnavailable, cloudVerified }

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.user, required this.questionService, required this.attempts});
  final User user;
  final QuestionService questionService;
  final AttemptRepository attempts;
  @override State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  RoundView view = RoundView.loading;
  List<QuizQuestion> questions = const [];
  final List<String?> selections = List.filled(10, null);
  int index = 0;
  String message = '';
  late String roundId;

  int get score => List.generate(questions.length, (i) => selections[i] == questions[i].correctAnswer).where((v) => v).length;
  bool get unresolved => {RoundView.submitting, RoundView.verifying, RoundView.saveUnknown, RoundView.verificationUnavailable}.contains(view);

  @override void initState() { super.initState(); _newRound(); }

  Future<void> _newRound() async {
    roundId = widget.attempts.newRoundId(widget.user.uid);
    index = 0; selections.fillRange(0, selections.length, null);
    setState(() { view = RoundView.loading; message = 'Loading 10 questions…'; });
    try {
      final loaded = await widget.questionService.fetchQuestions();
      if (!mounted) return;
      setState(() { questions = loaded; view = RoundView.playing; message = ''; });
    } catch (error) {
      if (mounted) setState(() { view = RoundView.requestError; message = error.toString(); });
    }
  }

  void _choose(String choice) {
    if (selections[index] != null) return;
    setState(() => selections[index] = choice);
  }

  void _next() {
    if (selections[index] == null) return;
    setState(() {
      if (index < 9) index++; else view = RoundView.readyToSubmit;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !unresolved,
    child: Scaffold(
      appBar: AppBar(title: const Text('General Knowledge'), actions: [
        IconButton(tooltip: unresolved ? 'Resolve submission before sign-out' : 'Sign out',
          onPressed: unresolved ? null : FirebaseAuth.instance.signOut, icon: const Icon(Icons.logout)),
      ]),
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: _body())),
    ),
  );

  Widget _body() {
    if (view == RoundView.loading) return _status(Icons.cloud_download, message, busy: true);
    if (view == RoundView.requestError) return _status(Icons.error_outline, message,
      action: FilledButton(onPressed: _newRound, child: const Text('Retry after 5 seconds')));
    if (view == RoundView.playing) return _question();
    return _review();
  }

  Widget _status(IconData icon, String text, {bool busy = false, Widget? action}) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 56), const SizedBox(height: 12), Text(text, textAlign: TextAlign.center),
    if (busy) const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
    if (action != null) Padding(padding: const EdgeInsets.only(top: 16), child: action),
  ]));

  Widget _question() {
    final q = questions[index]; final selected = selections[index];
    return ListView(children: [
      LinearProgressIndicator(value: (index + 1) / 10),
      Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text('Question ${index + 1} of 10', style: Theme.of(context).textTheme.titleMedium)),
      Text(q.text, style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 18),
      for (final choice in q.choices) Card(child: ListTile(
        enabled: selected == null, title: Text(choice), onTap: () => _choose(choice),
        leading: selected == choice ? Icon(choice == q.correctAnswer ? Icons.check_circle : Icons.cancel,
          color: choice == q.correctAnswer ? Colors.green : Colors.red) : const Icon(Icons.circle_outlined),
      )),
      if (selected != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(selected == q.correctAnswer ? 'Correct ✓' : 'Incorrect. Correct answer: ${q.correctAnswer}',
          style: TextStyle(fontWeight: FontWeight.bold, color: selected == q.correctAnswer ? Colors.green.shade800 : Colors.red.shade800))),
      FilledButton(onPressed: selected == null ? null : _next, child: Text(index == 9 ? 'Review answers' : 'Next')),
    ]);
  }

  Widget _review() => ListView(children: [
    Text('Score: $score / 10', style: Theme.of(context).textTheme.headlineMedium),
    Text('Round …${roundId.substring(roundId.length - 6)}'), const Divider(),
    for (var i = 0; i < questions.length; i++) ListTile(
      leading: Icon(selections[i] == questions[i].correctAnswer ? Icons.check : Icons.close,
        color: selections[i] == questions[i].correctAnswer ? Colors.green : Colors.red),
      title: Text('${i + 1}. ${questions[i].text}'),
      subtitle: Text('Your answer: ${selections[i]}\nCorrect: ${questions[i].correctAnswer}'),
    ),
    const SizedBox(height: 12),
    Text(message, style: TextStyle(color: view == RoundView.cloudVerified ? Colors.green.shade800 : Theme.of(context).colorScheme.error)),
    if (view == RoundView.readyToSubmit) FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.cloud_upload), label: const Text('Submit')),
    if (view == RoundView.saveUnknown || view == RoundView.verificationUnavailable)
      FilledButton(onPressed: _reconcile, child: const Text('Verify same round on server')),
    if (view == RoundView.submitting || view == RoundView.verifying) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
    OutlinedButton(onPressed: unresolved ? null : _newRound, child: const Text('Replay with new round ID')),
  ]);

  Future<void> _submit() async => _runSubmission(() => widget.attempts.createOnce(uid: widget.user.uid, roundId: roundId, correctCount: score));
  Future<void> _reconcile() async => _runSubmission(() async {});

  Future<void> _runSubmission(Future<void> Function() operation) async {
    final initiatingUid = widget.user.uid; final initiatingRound = roundId;
    setState(() { view = RoundView.submitting; message = 'Submitting immutable attempt…'; });
    try {
      await operation();
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != initiatingUid || roundId != initiatingRound) return;
      setState(() { view = RoundView.verifying; message = 'Reading exact document from server…'; });
      await widget.attempts.verifyServer(uid: initiatingUid, roundId: initiatingRound, correctCount: score);
      if (mounted && FirebaseAuth.instance.currentUser?.uid == initiatingUid && roundId == initiatingRound) {
        setState(() { view = RoundView.cloudVerified; message = 'Cloud verified: users/$initiatingUid/attempts/$initiatingRound'; });
      }
    } on AttemptFailure catch (error) {
      if (!mounted) return;
      setState(() {
        view = switch (error.kind) {
          AttemptFailureKind.permissionDenied || AttemptFailureKind.unauthenticated => RoundView.permissionDenied,
          AttemptFailureKind.verificationUnavailable => RoundView.verificationUnavailable,
          AttemptFailureKind.collision || AttemptFailureKind.resourceExhausted => RoundView.readyToSubmit,
          AttemptFailureKind.unavailable => RoundView.saveUnknown,
        };
        message = error.message;
      });
    } catch (error) {
      if (mounted) setState(() { view = RoundView.saveUnknown; message = 'Save result unknown. Reconcile this same round. $error'; });
    }
  }
}
