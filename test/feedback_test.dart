import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:basis/feedback.dart';
import 'package:basis/state.dart';

/// A sink that records what it was asked to send and can be made to fail,
/// so the queueing behaviour can be tested without a network.
class _RecordingSink implements FeedbackSink {
  _RecordingSink({this.succeed = true});
  bool succeed;
  final sent = <FeedbackItem>[];

  @override
  Future<bool> send(FeedbackItem item) async {
    sent.add(item);
    return succeed;
  }
}

FeedbackItem _item(String id, {String message = 'Instalment looks high'}) =>
    FeedbackItem(
      id: id,
      category: FeedbackCategory.wrongNumber,
      message: message,
      rulesetVersion: '2026.09',
      createdAt: DateTime(2026, 9, 13),
      rating: 4,
      calculatorId: 'mortgage',
    );

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('basis_fb_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  FeedbackService service({bool succeed = true, _RecordingSink? sink}) =>
      FeedbackService(
        store: FeedbackStore(directory: tmp),
        sink: sink ?? _RecordingSink(succeed: succeed),
      );

  group('Nothing is lost', () {
    test('a failed send leaves the message queued, not dropped', () async {
      final sink = _RecordingSink(succeed: false);
      final s = service(sink: sink);

      final outcome = await s.submit(_item('a'));
      expect(outcome, FeedbackOutcome.queued);
      expect(sink.sent, hasLength(1), reason: 'it still tried');

      final pending = await s.pending();
      expect(pending, hasLength(1));
      expect(pending.first.message, 'Instalment looks high');
    });

    test('a successful send marks it as sent and stops queueing it', () async {
      final s = service(succeed: true);
      expect(await s.submit(_item('a')), FeedbackOutcome.sent);
      expect(await s.pending(), isEmpty);
    });

    test('the message is written before any send is attempted', () async {
      // Even a sink that throws must not lose the message.
      final s = FeedbackService(
        store: FeedbackStore(directory: tmp),
        sink: _ThrowingSink(),
      );
      final outcome = await s.submit(_item('a'));
      expect(outcome, FeedbackOutcome.queued);
      expect(await s.pending(), hasLength(1));
    });

    test('an empty message is rejected and never stored', () async {
      final s = service();
      expect(
        await s.submit(_item('a', message: '   ')),
        FeedbackOutcome.rejected,
      );
      expect(await s.pending(), isEmpty);
    });

    test('the queue survives a restart', () async {
      final store = FeedbackStore(directory: tmp);
      final a = FeedbackService(
        store: store,
        sink: _RecordingSink(succeed: false),
      );
      await a.submit(_item('a'));

      store.reset();
      final b = FeedbackService(
        store: FeedbackStore(directory: tmp),
        sink: _RecordingSink(succeed: false),
      );
      expect(await b.pending(), hasLength(1));
    });

    test('flush sends everything queued and reports how many went', () async {
      final failing = _RecordingSink(succeed: false);
      final s = FeedbackService(
        store: FeedbackStore(directory: tmp),
        sink: failing,
      );
      await s.submit(_item('a'));
      await s.submit(_item('b'));
      expect(await s.pending(), hasLength(2));

      failing.succeed = true;
      expect(await s.flush(), 2);
      expect(await s.pending(), isEmpty);
    });

    test('one corrupt row does not destroy the queue', () async {
      final s = service(succeed: false);
      await s.submit(_item('good'));

      final f = File('${tmp.path}${Platform.pathSeparator}feedback.json');
      final rows = (jsonDecode(await f.readAsString()) as List).toList()
        ..insert(0, {'nonsense': true});
      await f.writeAsString(jsonEncode(rows));

      final fresh = FeedbackService(
        store: FeedbackStore(directory: tmp),
        sink: _RecordingSink(succeed: false),
      );
      final pending = await fresh.pending();
      expect(pending.map((i) => i.id), contains('good'));
    });
  });

  group('What gets sent', () {
    test(
      'carries the ruleset revision and the calculator, nothing personal',
      () {
        final json = _item('a').toJson();
        expect(json['rulesetVersion'], '2026.09');
        expect(json['calculatorId'], 'mortgage');
        expect(json['category'], 'wrongNumber');
        expect(json['rating'], 4);
        // No device id, no location, no account, no figures the user entered.
        expect(json.keys, isNot(contains('device')));
        expect(json.keys, isNot(contains('email')));
        expect(json.keys, isNot(contains('inputs')));
      },
    );

    test('round-trips through JSON', () {
      final back = FeedbackItem.fromJson(_item('a').toJson());
      expect(back.id, 'a');
      expect(back.category, FeedbackCategory.wrongNumber);
      expect(back.rating, 4);
      expect(back.message, 'Instalment looks high');
    });

    test('an unknown category decodes to "other" rather than throwing', () {
      final back = FeedbackItem.fromJson({
        'id': 'x',
        'category': 'something_new',
        'message': 'hi',
        'rulesetVersion': '1',
        'createdAt': DateTime(2026).toIso8601String(),
      });
      expect(back.category, FeedbackCategory.other);
    });

    test('the copyable text names the category and the message', () {
      final text = _item('a').asText();
      expect(text, contains('A number looks wrong'));
      expect(text, contains('Instalment looks high'));
      expect(text, contains('2026.09'));
    });
  });

  group('HTTP sink', () {
    test('an empty endpoint never attempts a request', () async {
      final sink = HttpFeedbackSink('');
      expect(await sink.send(_item('a')), isFalse);
    });

    test('a 2xx counts as sent, anything else does not', () async {
      Future<bool> withStatus(int code) async {
        final client = MockClient((_) async => http.Response('', code));
        return HttpFeedbackSink(
          'https://example.invalid/f',
          client: client,
        ).send(_item('a'));
      }

      expect(await withStatus(200), isTrue);
      expect(await withStatus(201), isTrue);
      expect(await withStatus(400), isFalse);
      expect(await withStatus(500), isFalse);
    });

    test('a network failure is reported, not thrown', () async {
      final client = MockClient(
        (_) async => throw const SocketException('down'),
      );
      final sink = HttpFeedbackSink(
        'https://example.invalid/f',
        client: client,
      );
      expect(await sink.send(_item('a')), isFalse);
    });

    test('posts JSON containing the message', () async {
      String? body;
      final client = MockClient((req) async {
        body = req.body;
        return http.Response('{}', 200);
      });
      await HttpFeedbackSink(
        'https://example.invalid/f',
        client: client,
      ).send(_item('a'));
      expect(body, isNotNull);
      expect(jsonDecode(body!)['message'], 'Instalment looks high');
    });
  });

  test('no secret is compiled into the app', () {
    // The endpoint is a public relay URL by design. A bot token must never
    // be compiled in, whatever FEEDBACK_URL the build was given.
    expect(
      isSafeFeedbackEndpoint(kFeedbackEndpoint),
      isTrue,
      reason: 'FEEDBACK_URL must be the relay, never a Telegram API URL',
    );
  });

  test('the endpoint guard rejects anything that would leak a bot token', () {
    expect(isSafeFeedbackEndpoint(''), isTrue);
    expect(
      isSafeFeedbackEndpoint('https://basis-feedback.ben.workers.dev'),
      isTrue,
    );
    expect(
      isSafeFeedbackEndpoint(
        'https://api.telegram.org/bot123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw/sendMessage',
      ),
      isFalse,
    );
    expect(
      isSafeFeedbackEndpoint(
        'https://relay.example.com/?t=123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw',
      ),
      isFalse,
    );
    expect(isSafeFeedbackEndpoint('http://insecure.example.com'), isFalse);
  });

  test(
    'feedback queued while offline is sent when the app next opens',
    () async {
      final tmp = Directory.systemTemp.createTempSync('basis_fb_reopen');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final offline = FeedbackService(
        store: FeedbackStore(directory: tmp),
        sink: _RecordingSink(succeed: false),
      );
      expect(await offline.submit(_item('q1')), FeedbackOutcome.queued);

      final online = _RecordingSink();
      final app = AppState(
        feedback: FeedbackService(
          store: FeedbackStore(directory: tmp),
          sink: online,
        ),
      );
      await app.init();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(online.sent.map((i) => i.id), ['q1']);
      expect(await app.feedback.pending(), isEmpty);
    },
  );
}

class _ThrowingSink implements FeedbackSink {
  @override
  Future<bool> send(FeedbackItem item) async => throw StateError('boom');
}
