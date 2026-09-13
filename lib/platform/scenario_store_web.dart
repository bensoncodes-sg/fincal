import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../state.dart';
import 'local_storage_web.dart';

/// Browser persistence: the same JSON the phone writes to a file, kept in
/// localStorage. It survives closing the tab and reopening the site in the
/// same browser; it is not synced between devices.
class LocalStorageScenarioStore implements ScenarioStore {
  LocalStorageScenarioStore({this.key = 'basis.scenarios'});

  final String key;
  List<Scenario>? _cache;

  @override
  Future<List<Scenario>> load() async {
    if (_cache != null) return List.of(_cache!);
    final out = <Scenario>[];
    try {
      final raw = readLocal(key);
      final decoded = raw == null || raw.trim().isEmpty
          ? null
          : jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          // One corrupt record must not lose the rest.
          try {
            out.add(Scenario.fromJson(Map<String, Object?>.from(item as Map)));
          } catch (e) {
            debugPrint('Basis: skipping an unreadable saved scenario ($e).');
          }
        }
      }
    } catch (e) {
      debugPrint('Basis: could not read saved scenarios ($e).');
    }
    _cache = out;
    return List.of(out);
  }

  @override
  Future<void> save(List<Scenario> scenarios) async {
    _cache = List.of(scenarios);
    writeLocal(
      key,
      jsonEncode(scenarios.map((s) => s.toJson()).toList(growable: false)),
    );
  }

  @override
  Future<bool> hasBeenWritten() async => readLocal(key) != null;
}

/// The store the app uses on this platform.
ScenarioStore createScenarioStore() => LocalStorageScenarioStore();
