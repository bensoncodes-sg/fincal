/// Plain-language explanations for the terms Basis uses.
///
/// Written for someone who has never heard the term. Each entry says what the
/// thing is and why it matters to the number on screen. Where a figure depends
/// on current rules it points to Settings rather than repeating a number here,
/// so this text cannot drift out of date when a rule changes.
library;

class GlossaryEntry {
  final String term;
  final String meaning;
  const GlossaryEntry(this.term, this.meaning);
}

const List<GlossaryEntry> glossary = [
  GlossaryEntry(
    'TDSR',
    'Total Debt Servicing Ratio. A MAS limit on how much of your gross monthly '
        'income can go to all debt repayments together, including the new home '
        'loan, car loans and credit cards. The limit the app uses is shown in '
        'Settings.',
  ),
  GlossaryEntry(
    'MSR',
    'Mortgage Servicing Ratio. For HDB flats and ECs only: a separate, lower '
        'limit on how much of your gross monthly income the home loan '
        'instalment alone can take.',
  ),
  GlossaryEntry(
    'LTV',
    'Loan-to-Value. The most a bank can lend as a share of the property price. '
        'The rest is your down payment. The limit drops for longer loans or '
        'loans that run past a certain age.',
  ),
  GlossaryEntry(
    'Stress',
    'Banks check you could still pay if interest rates rose. They work out '
        'the instalment at a higher "stress" rate, which is why the '
        'affordability figure is more cautious than today\'s rates suggest.',
  ),
  GlossaryEntry(
    'BSD',
    'Buyer\'s Stamp Duty. Tax every buyer pays on a property purchase, '
        'charged in tiers on the price. It is due within 14 days of signing.',
  ),
  GlossaryEntry(
    'ABSD',
    'Additional Buyer\'s Stamp Duty. An extra tax on top of BSD for some '
        'buyers, depending on citizenship and how many properties you already '
        'own.',
  ),
  GlossaryEntry(
    'OA',
    'CPF Ordinary Account. Can be used for housing, insurance and education. '
        'Earns the lowest CPF interest rate.',
  ),
  GlossaryEntry(
    'SA',
    'CPF Special Account. For retirement. Earns a higher rate than OA and '
        'closes at 55, when savings move into the Retirement Account.',
  ),
  GlossaryEntry(
    'MA',
    'CPF MediSave Account. For healthcare costs and approved medical '
        'insurance. Capped at the Basic Healthcare Sum.',
  ),
  GlossaryEntry(
    'RA',
    'CPF Retirement Account. Created at 55 from your SA and OA savings, up to '
        'the Full Retirement Sum. It funds your monthly payouts later.',
  ),
  GlossaryEntry(
    'BHS',
    'Basic Healthcare Sum. The cap on MediSave. Anything above it overflows '
        'to your other CPF accounts.',
  ),
  GlossaryEntry(
    'FRS',
    'Full Retirement Sum. The amount CPF sets aside in your Retirement '
        'Account at 55, if you have enough.',
  ),
  GlossaryEntry(
    'Flat rate',
    'Interest charged on the original loan amount for the whole term, even '
        'as you repay it. It sounds cheap, but the real cost is roughly double '
        'the number quoted.',
  ),
  GlossaryEntry(
    'Effective',
    'The true yearly cost or return once compounding and repayments are '
        'counted. Use it to compare offers that quote rates differently.',
  ),
  GlossaryEntry(
    'Rule of 78',
    'A way lenders work out how much interest you save by settling a loan '
        'early. It front-loads interest, so settling early saves less than you '
        'might expect.',
  ),
  GlossaryEntry(
    'Tenor',
    'How long the loan runs, in years. A longer tenor lowers the monthly '
        'instalment but adds to the total interest.',
  ),
  GlossaryEntry(
    'Tenure',
    'How long the loan runs, in years. A longer tenure lowers the monthly '
        'instalment but adds to the total interest.',
  ),
  GlossaryEntry(
    'Lock-in',
    'A period at the start of a bank loan when repaying or switching costs a '
        'penalty, usually a percentage of the amount repaid.',
  ),
  GlossaryEntry(
    'Break-even',
    'The point where what you gain finally covers what you paid to get there, '
        'such as a refinancing fee or a trading fee.',
  ),
  GlossaryEntry(
    'Annualised',
    'A return spread evenly over each year, so investments held for different '
        'lengths of time can be compared fairly.',
  ),
  GlossaryEntry(
    'Marginal',
    'The tax rate on your next dollar of income. It is higher than your '
        'overall average rate, because tax is charged in bands.',
  ),
  GlossaryEntry(
    'Relief',
    'An amount taken off your income before tax is worked out, such as for '
        'CPF contributions or supporting parents. More relief means less tax.',
  ),
  GlossaryEntry(
    'Service charge',
    'Usually 10% added by restaurants. GST is then charged on the food plus '
        'the service charge, which is why the total is more than adding 19%.',
  ),
  GlossaryEntry(
    'GST',
    'Goods and Services Tax, added to most things you buy. The rate the app '
        'uses is shown in Settings.',
  ),
  GlossaryEntry(
    'Amortization',
    'Paying a loan off through regular instalments. Early payments are mostly '
        'interest; later ones are mostly the loan itself.',
  ),
  GlossaryEntry(
    'Present value',
    'What a future amount is worth in today\'s money, after allowing for the '
        'interest it could have earned in the meantime.',
  ),
  GlossaryEntry(
    'Future value',
    'What money today grows to by a future date at a given rate.',
  ),
  GlossaryEntry(
    'Expense ratio',
    'The yearly fee a fund takes, as a share of what you have invested. It is '
        'charged whether the fund does well or not.',
  ),
];

/// The entry whose term appears in [text], matched as a whole word and
/// ignoring case. Longer terms win, so "Flat rate" is found before "rate".
GlossaryEntry? glossaryFor(String text) {
  final lower = text.toLowerCase();
  final sorted = [...glossary]
    ..sort((a, b) => b.term.length.compareTo(a.term.length));
  for (final e in sorted) {
    final t = RegExp.escape(e.term.toLowerCase());
    if (RegExp('(^|[^a-z])${t}s?([^a-z]|\$)').hasMatch(lower)) return e;
  }
  return null;
}
