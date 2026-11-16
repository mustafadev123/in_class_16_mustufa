import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

enum AttemptFailureKind {
  collision,
  permissionDenied,
  unauthenticated,
  unavailable,
  resourceExhausted,
  notFound,
  verificationUnavailable
}

enum FaultInjection {
  none,
  hideAcknowledgement,
  unavailable,
  resourceExhausted
}

class AttemptFailure implements Exception {
  const AttemptFailure(this.kind, this.message);
  final AttemptFailureKind kind;
  final String message;
  @override
  String toString() => message;
}

class AttemptRepository {
  AttemptRepository(this.firestore);
  final FirebaseFirestore firestore;
  FaultInjection fault = FaultInjection.none; // Development test control only.

  String newRoundId(String uid) =>
      firestore.collection('users').doc(uid).collection('attempts').doc().id;

  Map<String, Object> _fixedPayload(int correctCount) => {
        'schemaVersion': 1,
        'variant': 'A',
        'categoryId': 9,
        'questionCount': 10,
        'correctCount': correctCount,
      };

  DocumentReference<Map<String, dynamic>> _ref(String uid, String roundId) =>
      firestore
          .collection('users')
          .doc(uid)
          .collection('attempts')
          .doc(roundId);

  Future<void> createOnce(
      {required String uid,
      required String roundId,
      required int correctCount}) async {
    if (correctCount < 0 || correctCount > 10) {
      throw const AttemptFailure(
          AttemptFailureKind.collision, 'Score is outside the valid range.');
    }
    if (fault == FaultInjection.unavailable) {
      throw const AttemptFailure(AttemptFailureKind.unavailable,
          '[INJECTED] Service unavailable. Retry manually.');
    }
    if (fault == FaultInjection.resourceExhausted) {
      throw const AttemptFailure(AttemptFailureKind.resourceExhausted,
          '[INJECTED] Resource exhausted. Do not retry automatically.');
    }
    final fixed = _fixedPayload(correctCount);
    try {
      await firestore.runTransaction((transaction) async {
        final ref = _ref(uid, roundId);
        final existing = await transaction.get(ref);
        if (!existing.exists) {
          transaction.set(
              ref, {...fixed, 'submittedAt': FieldValue.serverTimestamp()});
          return;
        }
        final data = existing.data()!;
        final matches =
            fixed.entries.every((entry) => data[entry.key] == entry.value);
        if (!matches) {
          throw const AttemptFailure(AttemptFailureKind.collision,
              'Round ID collision: original attempt was preserved.');
        }
      });
      if (fault == FaultInjection.hideAcknowledgement) {
        throw const AttemptFailure(AttemptFailureKind.unavailable,
            '[INJECTED] Acknowledgement hidden after real commit.');
      }
    } on FirebaseException catch (error) {
      throw _mapFirebase(error, verification: false);
    }
  }

  Future<void> verifyServer(
      {required String uid,
      required String roundId,
      required int correctCount}) async {
    try {
      final snapshot =
          await _ref(uid, roundId).get(const GetOptions(source: Source.server));
      if (!snapshot.exists) {
        throw const AttemptFailure(AttemptFailureKind.notFound,
            'Server confirmed this round is not saved yet.');
      }
      if (snapshot.metadata.hasPendingWrites) {
        throw const AttemptFailure(AttemptFailureKind.verificationUnavailable,
            'Server did not return a committed document.');
      }
      final data = snapshot.data()!;
      final fixed = _fixedPayload(correctCount);
      if (data.length != 6 ||
          data['submittedAt'] is! Timestamp ||
          !fixed.entries.every((entry) => data[entry.key] == entry.value)) {
        throw const AttemptFailure(AttemptFailureKind.collision,
            'Server document does not match the frozen payload.');
      }
    } on FirebaseException catch (error) {
      throw _mapFirebase(error, verification: true);
    }
  }

  AttemptFailure _mapFirebase(FirebaseException error,
      {required bool verification}) {
    switch (error.code) {
      case 'permission-denied':
        return const AttemptFailure(AttemptFailureKind.permissionDenied,
            'Permission denied by deployed Firestore rules.');
      case 'unauthenticated':
        return const AttemptFailure(
            AttemptFailureKind.unauthenticated, 'Authentication is required.');
      case 'resource-exhausted':
        return const AttemptFailure(AttemptFailureKind.resourceExhausted,
            'Cloud quota exhausted; no automatic retry.');
      case 'unavailable':
        return AttemptFailure(
            verification
                ? AttemptFailureKind.verificationUnavailable
                : AttemptFailureKind.unavailable,
            verification
                ? 'Save may have succeeded, but server verification is unavailable.'
                : 'Save result unknown because the service is unavailable.');
      default:
        return AttemptFailure(
            verification
                ? AttemptFailureKind.verificationUnavailable
                : AttemptFailureKind.unavailable,
            error.message ?? error.code);
    }
  }

  Future<String> runDeployedRuleAttacks({
    required String uid,
    required String roundId,
    required int correctCount,
  }) async {
    fault = FaultInjection.none;
    await createOnce(uid: uid, roundId: roundId, correctCount: correctCount);
    final attempts =
        firestore.collection('users').doc(uid).collection('attempts');

    Future<bool> denied(Future<void> operation) async {
      try {
        await operation;
        return false;
      } on FirebaseException catch (error) {
        return error.code == 'permission-denied';
      }
    }

    final scoreDenied = await denied(attempts.doc().set({
      ..._fixedPayload(11),
      'submittedAt': FieldValue.serverTimestamp(),
    }));
    final extraDenied = await denied(attempts.doc().set({
      ..._fixedPayload(correctCount),
      'submittedAt': FieldValue.serverTimestamp(),
      'extra': true,
    }));
    final updateDenied = await denied(_ref(uid, roundId).update({
      'correctCount': correctCount == 10 ? 9 : correctCount + 1,
    }));
    await verifyServer(uid: uid, roundId: roundId, correctCount: correctCount);
    if (!(scoreDenied && extraDenied && updateDenied)) {
      throw StateError('At least one invalid deployed request was not denied.');
    }
    return 'T11 PASS: score 11, extra field, and update denied; original verified.';
  }

  Future<String> runGraduateContention({
    required String uid,
    required int correctCount,
  }) async {
    fault = FaultInjection.none;
    final concurrentId = newRoundId(uid);
    await Future.wait([
      createOnce(uid: uid, roundId: concurrentId, correctCount: correctCount),
      createOnce(uid: uid, roundId: concurrentId, correctCount: correctCount),
    ]);
    await verifyServer(
        uid: uid, roundId: concurrentId, correctCount: correctCount);
    var collisionPreserved = false;
    try {
      await createOnce(
          uid: uid,
          roundId: concurrentId,
          correctCount: correctCount == 10 ? 9 : correctCount + 1);
    } on AttemptFailure catch (error) {
      collisionPreserved = error.kind == AttemptFailureKind.collision;
    }
    await verifyServer(
        uid: uid, roundId: concurrentId, correctCount: correctCount);
    if (!collisionPreserved) {
      throw StateError('Different-score collision was not preserved.');
    }
    final suffix = concurrentId.length > 6
        ? concurrentId.substring(concurrentId.length - 6)
        : concurrentId;
    return 'G01/G02 PASS: concurrent match reused one document; different score collided; …$suffix';
  }
}
