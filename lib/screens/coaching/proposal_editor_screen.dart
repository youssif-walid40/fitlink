import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/live_data.dart';
import '../../core/validators.dart';
import '../../core/widgets/common.dart';
import '../../models/chat.dart';
import '../../models/coaching.dart';
import '../../models/parse.dart';
import '../../providers/session_provider.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/coaching_repository.dart';
import '../../services/api_service.dart';
import '../../services/cache_service.dart';

class _DayDraft {
  String day;
  final TextEditingController title;
  final TextEditingController minutes;
  final TextEditingController exercises;
  _DayDraft({required this.day, String title = '', int minutes = 45, List<String> exercises = const []})
      : title = TextEditingController(text: title),
        minutes = TextEditingController(text: '$minutes'),
        exercises = TextEditingController(text: exercises.join('\n'));

  void dispose() {
    title.dispose();
    minutes.dispose();
    exercises.dispose();
  }

  WorkoutDay toDay() => WorkoutDay(
        day: day,
        title: title.text.trim(),
        minutes: int.tryParse(minutes.text) ?? 45,
        exercises: exercises.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      );
}

/// Workflow steps 3 and 5: the PT writes (or revises) a plan proposal.
/// The form is auto-saved as a draft in SharedPreferences.
class ProposalEditorScreen extends StatefulWidget {
  const ProposalEditorScreen({super.key, required this.coachingId});
  final String coachingId;

  @override
  State<ProposalEditorScreen> createState() => _ProposalEditorScreenState();
}

class _ProposalEditorScreenState extends State<ProposalEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _weeks = TextEditingController(text: '8');
  final _perWeek = TextEditingController(text: '4');
  final _price = TextEditingController();
  final _notes = TextEditingController();
  final _calories = TextEditingController(text: '2100');
  final _protein = TextEditingController(text: '130');
  final _water = TextEditingController(text: '2.5');
  final _nutritionNotes = TextEditingController();
  bool _includeNutrition = true;
  final List<_DayDraft> _days = [];
  bool _busy = false;
  bool _initialised = false;
  late CacheService _cache;

  List<TextEditingController> get _controllers =>
      [_title, _weeks, _perWeek, _price, _notes, _calories, _protein, _water, _nutritionNotes];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final d in _days) {
      d.dispose();
    }
    super.dispose();
  }

  void _init(Coaching c) {
    _cache = context.read<CacheService>();
    final draft = _cache.proposalDraft(widget.coachingId);
    final source = draft != null ? PlanProposal.fromMap(draft) : c.proposal;
    if (source != null) {
      _title.text = source.title;
      _weeks.text = '${source.durationWeeks}';
      _perWeek.text = '${source.sessionsPerWeek}';
      _price.text = '${source.price}';
      _notes.text = source.notes;
      _includeNutrition = source.nutrition != null;
      if (source.nutrition != null) {
        _calories.text = '${source.nutrition!.calories}';
        _protein.text = '${source.nutrition!.proteinG}';
        _water.text = fmtNum(source.nutrition!.waterL);
        _nutritionNotes.text = source.nutrition!.notes;
      }
      for (final d in source.workoutDays) {
        _days.add(_DayDraft(day: d.day, title: d.title, minutes: d.minutes, exercises: d.exercises));
      }
      // Counter terms are pre-filled so the PT can revise from them.
      if (c.counter != null && draft == null) {
        if (c.counter!.durationWeeks != null) _weeks.text = '${c.counter!.durationWeeks}';
        if (c.counter!.price != null) _price.text = '${c.counter!.price}';
      }
    } else {
      final goal = AppConfig.goals[c.goal] ?? 'Fitness';
      _title.text = '$goal and Strength Plan';
      _days.addAll([
        _DayDraft(day: 'Mon', title: 'Upper body push', minutes: 55, exercises: ['Bench press 4×8', 'Overhead press 3×10', 'Incline DB press 3×10', 'Lateral raises 3×15', 'Triceps pushdown 3×12']),
        _DayDraft(day: 'Wed', title: 'Lower body', minutes: 60, exercises: ['Back squat 4×6', 'Romanian deadlift 3×8', 'Walking lunges 3×12', 'Leg curl 3×12', 'Calf raises 4×15', 'Plank 3×45s']),
        _DayDraft(day: 'Fri', title: 'Upper body pull', minutes: 50, exercises: ['Pull-ups 4×6', 'Barbell row 3×8', 'Face pulls 3×15', 'Hammer curls 3×12', 'Dead hang 3×30s']),
        _DayDraft(day: 'Sat', title: 'Cardio and core', minutes: 40, exercises: ['Intervals 20 min', 'Hanging knee raises 3×12', 'Cable crunch 3×15', 'Side plank 3×30s']),
      ]);
    }
    if (draft != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => showSnack(context, 'Restored your unsent draft'));
    }
    for (final ctrl in _controllers) {
      ctrl.addListener(_saveDraft);
    }
    for (final d in _days) {
      _listenDay(d);
    }
  }

  void _listenDay(_DayDraft d) {
    d.title.addListener(_saveDraft);
    d.minutes.addListener(_saveDraft);
    d.exercises.addListener(_saveDraft);
  }

  PlanProposal _build() => PlanProposal(
        title: _title.text.trim(),
        durationWeeks: int.tryParse(_weeks.text) ?? 0,
        sessionsPerWeek: int.tryParse(_perWeek.text) ?? 0,
        price: int.tryParse(_price.text) ?? 0,
        notes: _notes.text.trim(),
        workoutDays: _days.map((d) => d.toDay()).toList(),
        nutrition: _includeNutrition
            ? NutritionTargets(
                calories: int.tryParse(_calories.text) ?? 0,
                proteinG: int.tryParse(_protein.text) ?? 0,
                waterL: asDouble(_water.text) ?? 0,
                notes: _nutritionNotes.text.trim(),
              )
            : null,
      );

  void _saveDraft() => _cache.saveProposalDraft(widget.coachingId, _build().toMap());

  Future<void> _submit(Coaching c) async {
    if (!_form.currentState!.validate()) return;
    if (_days.isEmpty) {
      showSnack(context, 'Add at least one workout day', error: true);
      return;
    }
    final me = context.read<SessionProvider>().user!;
    final p = _build();
    setState(() => _busy = true);
    try {
      await context.read<CoachingRepository>().propose(c.id, me, p);
      if (!mounted) return;
      // Post the proposal in the chat too, as in the wireframe.
      final chats = context.read<ChatRepository>();
      final chatId = await chats.openThread(
        meId: me.uid,
        meName: me.name,
        mePhoto: me.photoUrl,
        otherId: c.memberId,
        otherName: c.memberName,
        otherPhoto: c.memberPhoto,
      );
      await chats.send(chatId, senderId: me.uid, type: MessageType.proposal, payload: {
        'coachingId': c.id,
        'title': p.title,
        'durationWeeks': p.durationWeeks,
        'sessionsPerWeek': p.sessionsPerWeek,
        'price': p.price,
        'nutrition': p.nutrition != null,
      });
      await _cache.clearProposalDraft(widget.coachingId);
      if (!mounted) return;
      context.read<ApiService>().notify(type: 'coaching', refId: c.id);
      showSnack(context, 'Proposal sent to ${c.memberName}');
      goBack(context);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = context.watch<LiveData<List<Coaching>>>().data;
    final c = list?.where((x) => x.id == widget.coachingId).firstOrNull;
    if (c == null) return Scaffold(appBar: AppBar(title: const Text('Plan proposal')), body: const LoadingView());
    if (!_initialised) {
      _initialised = true;
      _init(c);
    }

    return Scaffold(
      appBar: AppBar(title: Text(c.proposal == null ? 'New plan proposal' : 'Revise proposal')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          Text('For ${c.memberName} · ${AppConfig.goals[c.goal]} · ${c.level}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (c.counter != null && c.status == CoachingStatus.countered)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AppCard(child: Text('Client asked: ${c.counter!.notes}')),
            ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Plan title'),
            validator: (v) => Validators.required(v, 'Title'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _weeks,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Weeks'),
                validator: (v) => Validators.number(v, min: 1, max: 52, field: 'Weeks'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _perWeek,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sessions / week'),
                validator: (v) => Validators.number(v, min: 1, max: 14, field: 'Sessions'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Total price (EGP)', prefixText: 'EGP '),
            validator: (v) => Validators.number(v, min: 0, max: 200000, field: 'Price'),
          ),
          const SectionHeader('Workout days'),
          for (var i = 0; i < _days.length; i++) ...[
            _DayEditor(
              key: ObjectKey(_days[i]),
              draft: _days[i],
              onDayChanged: (d) => setState(() {
                _days[i].day = d;
                _saveDraft();
              }),
              onRemove: () => setState(() {
                _days.removeAt(i).dispose();
                _saveDraft();
              }),
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add workout day'),
            onPressed: () => setState(() {
              final used = _days.map((d) => d.day).toSet();
              final next = AppConfig.weekdays.firstWhere((d) => !used.contains(d), orElse: () => 'Mon');
              final d = _DayDraft(day: next);
              _listenDay(d);
              _days.add(d);
            }),
          ),
          const SectionHeader('Nutrition'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Include a nutrition guide'),
            value: _includeNutrition,
            onChanged: (v) => setState(() {
              _includeNutrition = v;
              _saveDraft();
            }),
          ),
          if (_includeNutrition) ...[
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _calories,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'kcal / day'),
                  validator: (v) => Validators.number(v, min: 800, max: 6000, field: 'Calories'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _protein,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Protein g'),
                  validator: (v) => Validators.number(v, min: 20, max: 400, field: 'Protein'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _water,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Water L'),
                  validator: (v) => Validators.number(v, min: 0.5, max: 8, field: 'Water'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            TextFormField(
              controller: _nutritionNotes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Nutrition notes', alignLabelWithHint: true),
            ),
          ],
          const SectionHeader('Notes for the client'),
          TextFormField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Check-in schedule, equipment, expectations…'),
          ),
          const SizedBox(height: 20),
          BusyButton(label: 'Send proposal', icon: Icons.send, busy: _busy, onPressed: () => _submit(c)),
        ]),
      ),
    );
  }
}

class _DayEditor extends StatelessWidget {
  const _DayEditor({super.key, required this.draft, required this.onDayChanged, required this.onRemove});
  final _DayDraft draft;
  final ValueChanged<String> onDayChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            SizedBox(
              width: 92,
              child: DropdownButtonFormField<String>(
                initialValue: draft.day,
                decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
                items: [for (final d in AppConfig.weekdays) DropdownMenuItem(value: d, child: Text(d))],
                onChanged: (v) {
                  if (v != null) onDayChanged(v);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: draft.title,
                decoration: const InputDecoration(labelText: 'Focus'),
                validator: (v) => Validators.required(v, 'Focus'),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 70,
              child: TextFormField(
                controller: draft.minutes,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Min'),
                validator: (v) => Validators.number(v, min: 5, max: 240, field: 'Min'),
              ),
            ),
            IconButton(onPressed: onRemove, icon: const Icon(Icons.delete_outline)),
          ]),
          const SizedBox(height: 8),
          TextFormField(
            controller: draft.exercises,
            maxLines: 4,
            minLines: 2,
            decoration: const InputDecoration(labelText: 'Exercises (one per line)', alignLabelWithHint: true),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Add at least one exercise' : null,
          ),
        ]),
      );
}
