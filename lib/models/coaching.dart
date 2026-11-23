import 'package:cloud_firestore/cloud_firestore.dart';

import 'parse.dart';

enum CoachingStatus { requested, accepted, declined, proposed, countered, active, completed, cancelled }

extension CoachingStatusX on CoachingStatus {
  static CoachingStatus parse(String? s) =>
      CoachingStatus.values.firstWhere((v) => v.name == s, orElse: () => CoachingStatus.requested);

  String get label => switch (this) {
        CoachingStatus.requested => 'Requested',
        CoachingStatus.accepted => 'Accepted',
        CoachingStatus.declined => 'Declined',
        CoachingStatus.proposed => 'Plan proposed',
        CoachingStatus.countered => 'Counter offer',
        CoachingStatus.active => 'Active',
        CoachingStatus.completed => 'Completed',
        CoachingStatus.cancelled => 'Cancelled',
      };

  bool get isOpen => this != CoachingStatus.declined &&
      this != CoachingStatus.completed &&
      this != CoachingStatus.cancelled;
}

class WorkoutDay {
  final String day; // Mon..Sun
  final String title;
  final List<String> exercises;
  final int minutes;

  const WorkoutDay({required this.day, required this.title, this.exercises = const [], this.minutes = 45});

  factory WorkoutDay.fromMap(Map<String, dynamic> m) => WorkoutDay(
        day: m['day'] ?? 'Mon',
        title: m['title'] ?? 'Workout',
        exercises: asStringList(m['exercises']),
        minutes: asInt(m['minutes'], 45),
      );
  Map<String, dynamic> toMap() => {'day': day, 'title': title, 'exercises': exercises, 'minutes': minutes};
}

class NutritionTargets {
  final int calories;
  final int proteinG;
  final double waterL;
  final String notes;

  const NutritionTargets({required this.calories, required this.proteinG, required this.waterL, this.notes = ''});

  factory NutritionTargets.fromMap(Map<String, dynamic> m) => NutritionTargets(
        calories: asInt(m['calories']),
        proteinG: asInt(m['proteinG']),
        waterL: asDouble(m['waterL']) ?? 0,
        notes: m['notes'] ?? '',
      );
  Map<String, dynamic> toMap() => {'calories': calories, 'proteinG': proteinG, 'waterL': waterL, 'notes': notes};
}

class PlanProposal {
  final String title;
  final int durationWeeks;
  final int sessionsPerWeek;
  final int price; // EGP total for the plan
  final List<WorkoutDay> workoutDays;
  final NutritionTargets? nutrition;
  final String notes;
  final int version;

  const PlanProposal({
    required this.title,
    required this.durationWeeks,
    required this.sessionsPerWeek,
    required this.price,
    this.workoutDays = const [],
    this.nutrition,
    this.notes = '',
    this.version = 1,
  });

  int get totalSessions => durationWeeks * sessionsPerWeek;

  factory PlanProposal.fromMap(Map<String, dynamic> m) => PlanProposal(
        title: m['title'] ?? 'Plan',
        durationWeeks: asInt(m['durationWeeks'], 4),
        sessionsPerWeek: asInt(m['sessionsPerWeek'], 3),
        price: asInt(m['price']),
        workoutDays: (m['workoutDays'] as List? ?? []).map((d) => WorkoutDay.fromMap(asMap(d))).toList(),
        nutrition: m['nutrition'] == null ? null : NutritionTargets.fromMap(asMap(m['nutrition'])),
        notes: m['notes'] ?? '',
        version: asInt(m['version'], 1),
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'durationWeeks': durationWeeks,
        'sessionsPerWeek': sessionsPerWeek,
        'price': price,
        'workoutDays': workoutDays.map((d) => d.toMap()).toList(),
        'nutrition': nutrition?.toMap(),
        'notes': notes,
        'version': version,
      };

  PlanProposal copyWith({int? durationWeeks, int? price, String? notes, int? version}) => PlanProposal(
        title: title,
        durationWeeks: durationWeeks ?? this.durationWeeks,
        sessionsPerWeek: sessionsPerWeek,
        price: price ?? this.price,
        workoutDays: workoutDays,
        nutrition: nutrition,
        notes: notes ?? this.notes,
        version: version ?? this.version,
      );
}

class CounterOffer {
  final int? durationWeeks;
  final int? price;
  final String notes;
  const CounterOffer({this.durationWeeks, this.price, required this.notes});

  factory CounterOffer.fromMap(Map<String, dynamic> m) => CounterOffer(
        durationWeeks: m['durationWeeks'] == null ? null : asInt(m['durationWeeks']),
        price: m['price'] == null ? null : asInt(m['price']),
        notes: m['notes'] ?? '',
      );
  Map<String, dynamic> toMap() => {'durationWeeks': durationWeeks, 'price': price, 'notes': notes};
}

class CoachingEvent {
  final String status;
  final String by; // uid
  final String note;
  final DateTime? at;
  const CoachingEvent({required this.status, required this.by, this.note = '', this.at});

  factory CoachingEvent.fromMap(Map<String, dynamic> m) =>
      CoachingEvent(status: m['status'] ?? '', by: m['by'] ?? '', note: m['note'] ?? '', at: asDate(m['at']));
}

/// One member↔PT relationship, from first request to final review.
/// Stored at coachings/{id}; both participants listen to it in real time.
class Coaching {
  final String id;
  final String memberId;
  final String ptId;
  final String memberName;
  final String ptName;
  final String? memberPhoto;
  final String? ptPhoto;
  final String goal;
  final String level;
  final String mode; // online | inGym
  final String message;
  final CoachingStatus status;
  final PlanProposal? proposal;
  final CounterOffer? counter;
  final int sessionsDone;
  final List<String> sharedScanIds;
  final bool reviewed;
  final List<CoachingEvent> events;
  final DateTime? activatedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Coaching({
    required this.id,
    required this.memberId,
    required this.ptId,
    required this.memberName,
    required this.ptName,
    this.memberPhoto,
    this.ptPhoto,
    required this.goal,
    required this.level,
    required this.mode,
    this.message = '',
    required this.status,
    this.proposal,
    this.counter,
    this.sessionsDone = 0,
    this.sharedScanIds = const [],
    this.reviewed = false,
    this.events = const [],
    this.activatedAt,
    this.createdAt,
    this.updatedAt,
  });

  String otherName(String uid) => uid == memberId ? ptName : memberName;
  String? otherPhoto(String uid) => uid == memberId ? ptPhoto : memberPhoto;
  String otherId(String uid) => uid == memberId ? ptId : memberId;

  /// Current week (1-based) of an active plan.
  int get currentWeek {
    if (activatedAt == null) return 1;
    final w = DateTime.now().difference(activatedAt!).inDays ~/ 7 + 1;
    final max = proposal?.durationWeeks ?? w;
    return w.clamp(1, max < 1 ? 1 : max);
  }

  factory Coaching.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Coaching(
      id: doc.id,
      memberId: d['memberId'] ?? '',
      ptId: d['ptId'] ?? '',
      memberName: d['memberName'] ?? 'Member',
      ptName: d['ptName'] ?? 'Trainer',
      memberPhoto: d['memberPhoto'],
      ptPhoto: d['ptPhoto'],
      goal: d['goal'] ?? 'fat_loss',
      level: d['level'] ?? 'Beginner',
      mode: d['mode'] ?? 'online',
      message: d['message'] ?? '',
      status: CoachingStatusX.parse(d['status']),
      proposal: d['proposal'] == null ? null : PlanProposal.fromMap(asMap(d['proposal'])),
      counter: d['counter'] == null ? null : CounterOffer.fromMap(asMap(d['counter'])),
      sessionsDone: asInt(d['sessionsDone']),
      sharedScanIds: asStringList(d['sharedScanIds']),
      reviewed: d['reviewed'] == true,
      events: (d['events'] as List? ?? []).map((e) => CoachingEvent.fromMap(asMap(e))).toList(),
      activatedAt: asDate(d['activatedAt']),
      createdAt: asDate(d['createdAt']),
      updatedAt: asDate(d['updatedAt']),
    );
  }
}
