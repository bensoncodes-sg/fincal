import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../feedback.dart';
import 'local_storage_web.dart';

/// Browser feedback queue, kept in localStorage. Same API as the file-based
/// store so [FeedbackService] does not know which one it has.
class FeedbackStore {
  FeedbackStore({Object? directory, this.fileName = 'feedback.json'});

  final String fileName;

  String get _key => 'basis.$fileName';

  Future<List<FeedbackItem>> load() async {
    try {
      final raw = readLocal(_key);
      if (raw == null || raw.trim().isEmpty) return [];
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
    writeLocal(
      _key,
      jsonEncode(items.map((i) => i.toJson()).toList(growable: false)),
    );
  }

  @visibleForTesting
  void reset() {}
}
