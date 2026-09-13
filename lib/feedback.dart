import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'platform/feedback_store_io.dart'
    if (dart.library.js_interop) 'platform/feedback_store_web.dart';

export 'platform/feedback_store_io.dart'
    if (dart.library.js_interop) 'platform/feedback_store_web.dart';

/// Feedback capture.
///
/// Design constraints this had to live inside:
///
///   * `supabase_flutter` and `url_launcher` are PLUGINS, and plugins cannot
///     be built here without Windows Developer Mode. `http` is pure Dart, so
///     an HTTPS POST is the one route that works today.
///   * Feedback is written locally FIRST and only then sent. Nothing is lost
///     because the phone was offline or the endpoint was down, and a failed
///     send leaves the item queued rather than dropping it.
///   * No secret ever ships in the app. [kFeedbackEndpoint] is a public
///     form URL by design — the kind Formspree or Web3Forms hand out. A
///     database service key or bot token must never go here.
const String kFeedbackEndpoint = '';

enum FeedbackCategory {
  wrongNumber('A number looks wrong'),
  bug('Something is broken'),
  suggestion('Suggestion'),
  other('Something else');

  const FeedbackCategory(this.label);
  final String label;
}

@immutable
class FeedbackItem {
  final String id;
  final FeedbackCategory category;

  /// 1–5, or null when the person did not rate.
  final int? rating;
  final String message;

  /// Which calculator they were looking at, when that is known.
  final String? calculatorId;

  /// Shipped so a report can be tied to a build and a ruleset revision. No
  /// personal data is collected, and the form says so.
  final String rulesetVersion;
  final DateTime createdAt;
  final bool sent;

  const FeedbackItem({
    required this.id,
    required this.category,
    required this.message,
    required this.rulesetVersion,
    required this.createdAt,
    this.rating,
    this.calculatorId,
    this.sent = false,
  });

  FeedbackItem markSent() => FeedbackItem(
    id: id,
    category: category,
    message: message,
    rulesetVersion: rulesetVersion,
    createdAt: createdAt,
    rating: rating,
    calculatorId: calculatorId,
    sent: true,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'category': category.name,
    'rating': rating,
    'message': message,
    'calculatorId': calculatorId,
    'rulesetVersion': rulesetVersion,
    'createdAt': createdAt.toIso8601String(),
    'sent': sent,
  };

  static FeedbackItem fromJson(Map<String, Object?> j) => FeedbackItem(
    id: j['id'] as String,
    category: FeedbackCategory.values.firstWhere(
      (c) => c.name == j['category'],
      orElse: () => FeedbackCategory.other,
    ),
    rating: j['rating'] as int?,
    message: j['message'] as String? ?? '',
    calculatorId: j['calculatorId'] as String?,
    rulesetVersion: j['rulesetVersion'] as String? ?? '',
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    sent: j['sent'] as bool? ?? false,
  );

  /// Plain text, for the copy-to-clipboard fallback when there is no endpoint.
  String asText() {
    final b = StringBuffer()
      ..writeln('Basis feedback')
      ..writeln('Category: ${category.label}');
    if (rating != null) b.writeln('Rating: $rating/5');
    if (calculatorId != null) b.writeln('Calculator: $calculatorId');
    b
      ..writeln('Ruleset: $rulesetVersion')
      ..writeln('When: ${createdAt.toIso8601String()}')
      ..writeln()
      ..writeln(message);
    return b.toString();
  }
}

/// Where feedback goes once it has been stored locally.
abstract class FeedbackSink {
  /// True when the item was accepted. False leaves it queued for a retry;
  /// it is never a reason to lose the item or to throw at the user.
  Future<bool> send(FeedbackItem item);
}

/// Does nothing but succeed. Used when no endpoint is configured, so feedback
/// still lands in the local queue and can be copied out.
class LocalOnlySink implements FeedbackSink {
  @override
  Future<bool> send(FeedbackItem item) async => false;
}

class HttpFeedbackSink implements FeedbackSink {
  HttpFeedbackSink(this.endpoint, {http.Client? client})
    : _client = client ?? http.Client();

  final String endpoint;
  final http.Client _client;

  @override
  Future<bool> send(FeedbackItem item) async {
    if (endpoint.isEmpty) return false;
    try {
      final res = await _client
          .post(
            Uri.parse(endpoint),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(item.toJson()),
          )
          .timeout(const Duration(seconds: 12));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('Basis: feedback not sent ($e); it stays queued.');
      return false;
    }
  }
}

/// The local queue lives in platform/: a file on phones and in tests,
/// localStorage in the browser. Both expose the same FeedbackStore API.

/// Result of a submission, so the UI can tell the truth about what happened
/// rather than always claiming it was sent.
enum FeedbackOutcome { sent, queued, rejected }

class FeedbackService {
  FeedbackService({FeedbackStore? store, FeedbackSink? sink})
    : _store = store ?? FeedbackStore(),
      _sink =
          sink ??
          (kFeedbackEndpoint.isEmpty
              ? LocalOnlySink()
              : HttpFeedbackSink(kFeedbackEndpoint));

  final FeedbackStore _store;
  final FeedbackSink _sink;

  /// Store first, then try to send. Returns what actually happened.
  Future<FeedbackOutcome> submit(FeedbackItem item) async {
    if (item.message.trim().isEmpty) return FeedbackOutcome.rejected;

    final queue = await _store.load()
      ..add(item);
    await _store.saveAll(queue);

    // A sink that throws is a failed send, not a crash. The message is
    // already on disk by this point, so the person never loses it.
    final ok = await _trySend(item);
    if (!ok) return FeedbackOutcome.queued;

    final updated = queue
        .map((i) => i.id == item.id ? i.markSent() : i)
        .toList(growable: false);
    await _store.saveAll(updated);
    return FeedbackOutcome.sent;
  }

  Future<bool> _trySend(FeedbackItem item) async {
    try {
      return await _sink.send(item);
    } catch (e) {
      debugPrint('Basis: feedback sink failed ($e); message stays queued.');
      return false;
    }
  }

  Future<List<FeedbackItem>> pending() async =>
      (await _store.load()).where((i) => !i.sent).toList();

  Future<int> flush() async {
    final all = await _store.load();
    var sentCount = 0;
    final updated = <FeedbackItem>[];
    for (final item in all) {
      if (item.sent) {
        updated.add(item);
        continue;
      }
      final ok = await _trySend(item);
      updated.add(ok ? item.markSent() : item);
      if (ok) sentCount++;
    }
    await _store.saveAll(updated);
    return sentCount;
  }
}
