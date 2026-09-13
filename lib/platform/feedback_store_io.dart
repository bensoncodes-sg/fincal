import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../feedback.dart';

/// Local queue. Same durable-write approach as the scenario store: write to a
/// sibling then rename, so an interrupted write cannot destroy the queue.
class FeedbackStore {
  FeedbackStore({Directory? directory, this.fileName = 'feedback.json'})
    : _override = directory;

  final Directory? _override;
  final String fileName;
  File? _resolved;

  Future<File?> _file() async {
    if (_resolved != null) return _resolved;
    try {
      final dir = _override ?? await _defaultDirectory();
      if (dir == null) return null;
      if (!dir.existsSync()) await dir.create(recursive: true);
      _resolved = File('${dir.path}${Platform.pathSeparator}$fileName');
      return _resolved;
    } catch (e) {
      debugPrint('Basis: no feedback directory ($e).');
      return null;
    }
  }

  Future<Directory?> _defaultDirectory() async {
    try {
      final tmp = Directory.systemTemp;
      if (Platform.isAndroid) {
        final files = Directory('${tmp.parent.path}/files/basis');
        try {
          if (!files.existsSync()) files.createSync(recursive: true);
          return files;
        } catch (_) {
          return Directory('${tmp.path}/basis');
        }
      }
      return Directory('${tmp.path}${Platform.pathSeparator}basis');
    } catch (_) {
      return null;
    }
  }

  Future<List<FeedbackItem>> load() async {
    try {
      final f = await _file();
      if (f == null || !f.existsSync()) return [];
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <FeedbackItem>[];
      for (final row in decoded) {
        try {
          out.add(FeedbackItem.fromJson(Map<String, Object?>.from(row as Map)));
        } catch (e) {
          debugPrint('Basis: skipping an unreadable feedback row ($e).');
        }
      }
      return out;
    } catch (e) {
      debugPrint('Basis: could not read feedback ($e).');
      return [];
    }
  }

  Future<void> saveAll(List<FeedbackItem> items) async {
    try {
      final f = await _file();
      if (f == null) return;
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(
        jsonEncode(items.map((i) => i.toJson()).toList(growable: false)),
        flush: true,
      );
      if (f.existsSync()) await f.delete();
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('Basis: could not persist feedback ($e).');
    }
  }

  @visibleForTesting
  void reset() => _resolved = null;
}
