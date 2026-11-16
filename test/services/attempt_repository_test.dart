import 'package:flutter_test/flutter_test.dart';
import 'package:ica16_a/services/attempt_repository.dart';

void main() {
  test('failure kinds stay distinct for the UI state machine', () {
    expect(AttemptFailureKind.values, containsAll([
      AttemptFailureKind.permissionDenied,
      AttemptFailureKind.unavailable,
      AttemptFailureKind.resourceExhausted,
      AttemptFailureKind.verificationUnavailable,
      AttemptFailureKind.collision,
    ]));
  });
}
