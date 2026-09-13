import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../state.dart';

/// Plugin-free persistence.
///
/// `shared_preferences` and `path_provider` are plugins, and building with
/// plugins on this machine needs Windows Developer Mode, which is off. Rather
/// than leave scenarios in memory, this writes JSON with `dart:io` into the
/// app's own private directory.
///
/// Every path here is app-private:
///   * Android — `Directory.systemTemp` resolves to the app's cache directory
///     (`/data/user/0/<pkg>/cache`), so its sibling `files` directory is the
///     standard private store. If that cannot be created we stay in cache,
///     which survives restarts and is only cleared under storage pressure.
///   * Desktop and tests — a named folder under the system temp directory.
///
/// Persistence must never take the app down, so every operation is guarded and
/// degrades to in-memory on failure.
class FileScenarioStore implements ScenarioStore {
  FileScenarioStore({this.fileName = 'scenarios.json', Directory? directory})
    : _override = directory;

  final String fileName;

  /// Tests point this at a fresh temp directory. Without it they would share
  /// the real store and a file left by an earlier run would make a "first
  /// launch" assertion false.
  final Directory? _override;
  List<Scenario>? _cache;
  File? _resolved;

  Future<File?> _file() async {
    if (_resolved != null) return _resolved;
    try {
      final dir = await _directory();
      if (dir == null) return null;
      if (!dir.existsSync()) await dir.create(recursive: true);
      _resolved = File('${dir.path}${Platform.pathSeparator}$fileName');
      return _resolved;
    } catch (e) {
      debugPrint(
        'Basis: could not resolve a storage directory ($e); '
        'scenarios will not survive a restart.',
      );
      return null;
    }
  }

  Future<Directory?> _directory() async {
    if (_override != null) return _override;
    try {
      final tmp = Directory.systemTemp;
      if (Platform.isAndroid) {
        // systemTemp is .../<pkg>/cache; its sibling `files` is the durable
        // private store Android apps are expected to use.
        final files = Directory('${tmp.parent.path}/files/basis');
        try {
          if (!files.existsSync()) files.createSync(recursive: true);
          return files;
        } catch (_) {
          // Fall through to the cache directory, which still persists.
          return Directory('${tmp.path}/basis');
        }
      }
      return Directory('${tmp.path}${Platform.pathSeparator}basis');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Scenario>> load() async {
    if (_cache != null) return List.of(_cache!);
    try {
      final f = await _file();
      if (f == null || !f.existsSync()) {
        _cache = [];
        return [];
      }
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) {
        _cache = [];
        return [];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _cache = [];
        return [];
      }
      final out = <Scenario>[];
      for (final item in decoded) {
        // One corrupt record must not lose the whole file.
        try {
          out.add(Scenario.fromJson(Map<String, Object?>.from(item as Map)));
        } catch (e) {
          debugPrint('Basis: skipping an unreadable saved scenario ($e).');
        }
      }
      _cache = out;
      return List.of(out);
    } catch (e) {
      debugPrint('Basis: could not read saved scenarios ($e).');
      _cache = [];
      return [];
    }
  }

  @override
  Future<void> save(List<Scenario> scenarios) async {
    _cache = List.of(scenarios);
    try {
      final f = await _file();
      if (f == null) return;
      final payload = jsonEncode(
        scenarios.map((s) => s.toJson()).toList(growable: false),
      );
      // Write to a sibling then rename, so an interrupted write cannot leave
      // a half-written file where a good one used to be.
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(payload, flush: true);
      if (f.existsSync()) await f.delete();
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint(
        'Basis: could not persist scenarios ($e); '
        'they are still available for this session.',
      );
    }
  }

  @override
  Future<bool> hasBeenWritten() async {
    try {
      final f = await _file();
      return f != null && f.existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Test hook: forget the resolved path and cached rows.
  @visibleForTesting
  void reset() {
    _cache = null;
    _resolved = null;
  }
}

/// The store the app uses on this platform.
ScenarioStore createScenarioStore() => FileScenarioStore();
