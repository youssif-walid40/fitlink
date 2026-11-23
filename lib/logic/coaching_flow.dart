import '../models/app_user.dart';
import '../models/coaching.dart';

/// The hire-a-PT state machine. The same table is enforced in firestore.rules,
/// so a tampered client cannot skip steps.
///
///  requested --pt--> accepted | declined
///  accepted  --pt--> proposed
///  proposed  --member--> active | countered
///  proposed  --pt--> proposed (revise before the member answers)
///  countered --pt--> active (accept counter) | proposed (revised proposal)
///  active    --pt--> completed
///  requested/accepted/proposed/countered --member--> cancelled
class CoachingFlow {
  CoachingFlow._();

  static const Map<CoachingStatus, Map<CoachingStatus, UserRole>> _table = {
    CoachingStatus.requested: {
      CoachingStatus.accepted: UserRole.pt,
      CoachingStatus.declined: UserRole.pt,
      CoachingStatus.cancelled: UserRole.member,
    },
    CoachingStatus.accepted: {
      CoachingStatus.proposed: UserRole.pt,
      CoachingStatus.cancelled: UserRole.member,
    },
    CoachingStatus.proposed: {
      CoachingStatus.active: UserRole.member,
      CoachingStatus.countered: UserRole.member,
      CoachingStatus.proposed: UserRole.pt,
      CoachingStatus.cancelled: UserRole.member,
    },
    CoachingStatus.countered: {
      CoachingStatus.active: UserRole.pt,
      CoachingStatus.proposed: UserRole.pt,
      CoachingStatus.cancelled: UserRole.member,
    },
    CoachingStatus.active: {
      CoachingStatus.completed: UserRole.pt,
    },
  };

  static bool canTransition(CoachingStatus from, CoachingStatus to, UserRole actor) =>
      _table[from]?[to] == actor;

  static List<CoachingStatus> nextFor(CoachingStatus from, UserRole actor) => _table[from]
          ?.entries
          .where((e) => e.value == actor)
          .map((e) => e.key)
          .toList() ??
      const [];

  static bool canReview(Coaching c, String uid) =>
      c.status == CoachingStatus.completed && c.memberId == uid && !c.reviewed;
}
