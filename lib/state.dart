import 'dart:async';
import 'package:flutter/foundation.dart';

import 'core/calculator.dart';
import 'core/money.dart';
import 'calculators/registry.dart';
import 'feedback.dart';
import 'rules/sg_rules.dart';

/// A saved calculation. This single object is why Basis can offer history,
/// side-by-side comparison, export and sync while the incumbent cannot:
/// its calculators hold values in loose text fields with no shared shape.
class Scenario {
  final String id;
  final String calculatorId;
  final String name;
  final Inputs inputs;
  final DateTime savedAt;

  /// Cached headline so the Saved list renders without recomputing.
  final String headlineLabel;
  final String headlineValue;

  const Scenario({
    required this.id,
    required this.calculatorId,
    required this.name,
    required this.inputs,
    required this.savedAt,
    required this.headlineLabel,
    required this.headlineValue,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'calculatorId': calculatorId,
    'name': name,
    'savedAt': savedAt.toIso8601String(),
    'headlineLabel': headlineLabel,
    'headlineValue': headlineValue,
    'inputs': {
      for (final e in inputs.entries)
        e.key: switch (e.value) {
          Money m => {'_t': 'money', 'v': m.cents},
          DateTime d => {'_t': 'date', 'v': d.toIso8601String()},
          _ => e.value,
        },
    },
  };

  static Scenario fromJson(Map<String, Object?> j) => Scenario(
    id: j['id'] as String,
    calculatorId: j['calculatorId'] as String,
    name: j['name'] as String,
    savedAt: DateTime.parse(j['savedAt'] as String),
    headlineLabel: j['headlineLabel'] as String? ?? '',
    headlineValue: j['headlineValue'] as String? ?? '',
    inputs: {
      for (final e in (j['inputs'] as Map).entries)
        e.key as String: switch (e.value) {
          {'_t': 'money', 'v': final int c} => Money(c),
          {'_t': 'date', 'v': final String d} => DateTime.parse(d),
          final Object v => v,
          null => 0,
        },
    },
  );

  String get relativeTime {
    final d = DateTime.now().difference(savedAt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays == 1) return 'yesterday';
    if (d.inDays < 7) return '${d.inDays} days ago';
    if (d.inDays < 30) return '${(d.inDays / 7).floor()} weeks ago';
    return monthYear(savedAt);
  }

  bool get isThisWeek => DateTime.now().difference(savedAt).inDays < 7;

  /// A seeded demo scenario rather than something the user worked out.
  /// Every surface that shows a scenario reads this, so the label can never
  /// be right in one place and missing in another.
  bool get isExample => id.startsWith('eg-');
}

/// Pluggable persistence. The in-memory implementation keeps the app free of
/// native plugins; swapping in shared_preferences or a database is one class.
abstract class ScenarioStore {
  Future<List<Scenario>> load();
  Future<void> save(List<Scenario> scenarios);

  /// True once anything has ever been written. Seeding the examples keys off
  /// this rather than off an empty list, so deleting every scenario does not
  /// resurrect the demos on the next launch.
  Future<bool> hasBeenWritten();
}

class InMemoryScenarioStore implements ScenarioStore {
  List<Scenario> _data = [];
  bool _written = false;
  @override
  Future<List<Scenario>> load() async => List.of(_data);
  @override
  Future<void> save(List<Scenario> s) async {
    _data = List.of(s);
    _written = true;
  }

  @override
  Future<bool> hasBeenWritten() async => _written;
}

class AppState extends ChangeNotifier {
  AppState({ScenarioStore? store, FeedbackService? feedback})
    : _store = store ?? InMemoryScenarioStore(),
      feedback = feedback ?? FeedbackService();

  final ScenarioStore _store;

  /// Feedback capture. Writes locally first and only then attempts to send,
  /// so a message is never lost to being offline.
  final FeedbackService feedback;

  SgRules _rules = SgRules.defaults;
  SgRules get rules => _rules;

  final List<Scenario> _scenarios = [];

  /// Sorted newest first. Sorts a COPY: a getter that reorders the private
  /// list mutates state on every read, which is how iteration-order bugs and
  /// concurrent-modification crashes appear later.
  List<Scenario> get scenarios => List.unmodifiable(
    [..._scenarios]..sort((a, b) => b.savedAt.compareTo(a.savedAt)),
  );

  final Set<String> _compareIds = {};
  Set<String> get compareIds => Set.unmodifiable(_compareIds);

  BasisThemeMode _themeMode = BasisThemeMode.system;
  BasisThemeMode get themeMode => _themeMode;

  bool _ready = false;
  bool get isReady => _ready;

  Future<void> init() async {
    final loaded = await _store.load();
    _scenarios
      ..clear()
      ..addAll(loaded);
    if (_scenarios.isEmpty && !await _store.hasBeenWritten()) {
      _seedExamples();
    }
    _ready = true;
    notifyListeners();
    // Feedback written while offline waits in the local queue; send it now
    // the app is open again. Never awaited: a slow network must not hold up
    // the first screen, and a failure simply leaves it queued.
    if (feedback.canSend) unawaited(feedback.flush());
  }

  /// The app opens in a realistic working state rather than an empty shell.
  /// These are plainly marked as examples in the UI.
  ///
  /// Their headlines are COMPUTED, never written by hand. A seeded card that
  /// claims a figure its own inputs do not produce is a bug the user sees the
  /// moment they open it — Compare recomputes every column, so a hand-written
  /// headline and the recomputed one would disagree on screen.
  void _seedExamples() {
    Scenario? seed(String id, String calcId, String name, int daysAgo) {
      final calc = calculatorById(calcId);
      if (calc == null) return null;
      final result = calc.compute(calc.defaults, _rules);
      if (result.error != null) return null;
      return Scenario(
        id: id,
        calculatorId: calcId,
        name: name,
        inputs: Map.of(calc.defaults),
        savedAt: DateTime.now().subtract(Duration(days: daysAgo)),
        headlineLabel: result.primaryLabel,
        headlineValue: result.primaryValue,
      );
    }

    for (final s in [
      seed('eg-1', 'affordability', 'Punggol 4-room, dual income', 2),
      seed('eg-2', 'refinance', 'Switch from 4.25% to 3.35%', 6),
    ]) {
      if (s != null) _scenarios.add(s);
    }
  }

  void setBasisThemeMode(BasisThemeMode m) {
    _themeMode = m;
    notifyListeners();
  }

  void updateRules(SgRules r) {
    _rules = r;
    notifyListeners();
  }

  Future<void> saveScenario(Scenario s) async {
    _scenarios.removeWhere((e) => e.id == s.id);
    _scenarios.add(s);
    await _store.save(_scenarios);
    notifyListeners();
  }

  Future<void> deleteScenario(String id) async {
    _scenarios.removeWhere((e) => e.id == id);
    _compareIds.remove(id);
    await _store.save(_scenarios);
    notifyListeners();
  }

  void toggleCompare(String id) {
    if (_compareIds.contains(id)) {
      _compareIds.remove(id);
    } else {
      if (_compareIds.length >= 3) _compareIds.remove(_compareIds.first);
      _compareIds.add(id);
    }
    notifyListeners();
  }

  List<Scenario> get comparing =>
      _scenarios.where((s) => _compareIds.contains(s.id)).toList();
}

enum BasisThemeMode { system, light, dark }
