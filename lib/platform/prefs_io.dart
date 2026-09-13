import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Small key-value preferences (for example, whether the intro tour has been
/// seen), kept as one JSON file beside the saved scenarios. Same guarantees as
/// the scenario store: app-private, written via a sibling file then renamed,
/// and never allowed to crash the app.
class PrefsStore {
  PrefsStore({Directory? directory, this.fileName = 'prefs.json'})
    : _override = directory;

  final Directory? _override;
  final String fileName;
  Map<String, String>? _cache;

  Future<File?> _file() async {
    try {
      final dir = _override ?? _defaultDirectory();
      if (dir == null) return null;
      if (!dir.existsSync()) await dir.create(recursive: true);
      return File('${dir.path}${Platform.pathSeparator}$fileName');
    } catch (e) {
      debugPrint('Basis: no preferences directory ($e).');
      return null;
    }
  }

  Directory? _defaultDirectory() {
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

  Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;
    try {
      final f = await _file();
      if (f != null && f.existsSync()) {
        final decoded = jsonDecode(await f.readAsString());
        if (decoded is Map) {
          return _cache = {
            for (final e in decoded.entries) '${e.key}': '${e.value}',
          };
        }
      }
    } catch (e) {
      debugPrint('Basis: could not read preferences ($e).');
    }
    return _cache = {};
  }

  Future<String?> read(String key) async => (await _load())[key];

  Future<void> write(String key, String value) async {
    final data = {...await _load(), key: value};
    _cache = data;
    try {
      final f = await _file();
      if (f == null) return;
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(data), flush: true);
      if (f.existsSync()) await f.delete();
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('Basis: could not save preferences ($e).');
    }
  }
}

PrefsStore createPrefsStore() => PrefsStore();
