import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:basis/prefs.dart';
import 'package:basis/ui/tour.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('basis_prefs'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a value survives a new store, as after an app restart', () async {
    await PrefsStore(directory: dir).write('tour.v1.seen', 'true');
    expect(await PrefsStore(directory: dir).read('tour.v1.seen'), 'true');
  });

  test('writing one key keeps the others', () async {
    final a = PrefsStore(directory: dir);
    await a.write('x', '1');
    await a.write('y', '2');
    final b = PrefsStore(directory: dir);
    expect(await b.read('x'), '1');
    expect(await b.read('y'), '2');
  });

  test('a corrupt file degrades to empty rather than crashing', () async {
    File(
      '${dir.path}${Platform.pathSeparator}prefs.json',
    ).writeAsStringSync('{not json');
    expect(await PrefsStore(directory: dir).read('tour.v1.seen'), isNull);
  });

  test('the tour is remembered as seen across restarts', () async {
    expect(
      await PrefsTourMemory(PrefsStore(directory: dir)).hasSeen(),
      isFalse,
    );
    await PrefsTourMemory(PrefsStore(directory: dir)).markSeen();
    expect(await PrefsTourMemory(PrefsStore(directory: dir)).hasSeen(), isTrue);
  });
}
