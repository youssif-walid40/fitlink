import 'package:fitlink/logic/coaching_flow.dart';
import 'package:fitlink/models/app_user.dart';
import 'package:fitlink/models/coaching.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pt = UserRole.pt;
  const member = UserRole.member;

  group('CoachingFlow', () {
    test('happy path: request -> accept -> propose -> accept -> complete', () {
      expect(CoachingFlow.canTransition(CoachingStatus.requested, CoachingStatus.accepted, pt), isTrue);
      expect(CoachingFlow.canTransition(CoachingStatus.accepted, CoachingStatus.proposed, pt), isTrue);
      expect(CoachingFlow.canTransition(CoachingStatus.proposed, CoachingStatus.active, member), isTrue);
      expect(CoachingFlow.canTransition(CoachingStatus.active, CoachingStatus.completed, pt), isTrue);
    });

    test('negotiation loop: counter, then revised proposal or accepted counter', () {
      expect(CoachingFlow.canTransition(CoachingStatus.proposed, CoachingStatus.countered, member), isTrue);
      expect(CoachingFlow.canTransition(CoachingStatus.countered, CoachingStatus.proposed, pt), isTrue);
      expect(CoachingFlow.canTransition(CoachingStatus.countered, CoachingStatus.active, pt), isTrue);
    });

    test('roles cannot act for each other', () {
      expect(CoachingFlow.canTransition(CoachingStatus.requested, CoachingStatus.accepted, member), isFalse);
      expect(CoachingFlow.canTransition(CoachingStatus.proposed, CoachingStatus.active, pt), isFalse);
      expect(CoachingFlow.canTransition(CoachingStatus.active, CoachingStatus.completed, member), isFalse);
    });

    test('steps cannot be skipped', () {
      expect(CoachingFlow.canTransition(CoachingStatus.requested, CoachingStatus.active, member), isFalse);
      expect(CoachingFlow.canTransition(CoachingStatus.requested, CoachingStatus.proposed, pt), isFalse);
      expect(CoachingFlow.canTransition(CoachingStatus.completed, CoachingStatus.active, pt), isFalse);
      expect(CoachingFlow.canTransition(CoachingStatus.declined, CoachingStatus.accepted, pt), isFalse);
    });

    test('nextFor lists the actions available to a role', () {
      expect(CoachingFlow.nextFor(CoachingStatus.requested, pt), containsAll([CoachingStatus.accepted, CoachingStatus.declined]));
      expect(CoachingFlow.nextFor(CoachingStatus.requested, member), [CoachingStatus.cancelled]);
      expect(CoachingFlow.nextFor(CoachingStatus.completed, pt), isEmpty);
    });

    test('only the member of a completed, unreviewed coaching can review', () {
      Coaching c(CoachingStatus s, {bool reviewed = false}) => Coaching(
            id: 'c1',
            memberId: 'm',
            ptId: 'p',
            memberName: 'M',
            ptName: 'P',
            goal: 'fat_loss',
            level: 'Beginner',
            mode: 'online',
            status: s,
            reviewed: reviewed,
          );
      expect(CoachingFlow.canReview(c(CoachingStatus.completed), 'm'), isTrue);
      expect(CoachingFlow.canReview(c(CoachingStatus.completed), 'p'), isFalse);
      expect(CoachingFlow.canReview(c(CoachingStatus.active), 'm'), isFalse);
      expect(CoachingFlow.canReview(c(CoachingStatus.completed, reviewed: true), 'm'), isFalse);
    });
  });
}
