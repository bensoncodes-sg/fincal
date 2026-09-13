import 'package:flutter_test/flutter_test.dart';

import 'package:basis/calculators/registry.dart';
import 'package:basis/ui/glossary.dart';

void main() {
  test('finds jargon as whole words, ignoring case and plurals', () {
    expect(glossaryFor('TDSR ceiling')?.term, 'TDSR');
    expect(glossaryFor('Advertised flat rate')?.term, 'Flat rate');
    expect(glossaryFor('Total reliefs')?.term, 'Relief');
    expect(glossaryFor('EFFECTIVE INTEREST RATE')?.term, 'Effective');
  });

  test('does not match inside other words', () {
    expect(glossaryFor('Maximum price'), isNull); // "ma"
    expect(glossaryFor('Stressed instalment'), isNull); // "stress"
    expect(glossaryFor('Card balance'), isNull);
    expect(glossaryFor('Starting amount'), isNull); // "ra"
  });

  test('every entry is written out in full sentences', () {
    for (final e in glossary) {
      expect(e.meaning.trim().endsWith('.'), isTrue, reason: e.term);
      expect(e.meaning.length, greaterThan(40), reason: e.term);
    }
  });

  test('explanations appear on real calculator inputs', () {
    final labels = [
      for (final c in allCalculators) ...c.inputs.map((i) => i.label),
    ];
    final explained = labels.where((l) => glossaryFor(l) != null).toList();
    expect(explained, isNotEmpty);
  });
}
