# Basis

Financial calculators for Singapore. Flutter + Dart, no plugins.

```bash
cd C:/basis && flutter run -d chrome
```

## Look and feel

Designed to be usable by someone who has never used a financial calculator:

- **Home** greets you, has a search box that understands everyday words
  ("house", "tax", "COE"), and colour-codes the six question groups.
- **Inputs look like inputs**: each value sits in a box with S$ or its unit,
  a helper line under the label, and a clear outline while you edit.
- **Jargon is explained where it appears**: an ⓘ next to TDSR, LTV, tenor,
  flat rate and ~25 other terms opens a plain-language note
  (`lib/ui/glossary.dart`, tested so it never matches inside other words).
- **Example numbers say so** in a banner as well as the EXAMPLE badge.
- **Nothing reads as an alarm**: an incomplete input shows "Almost there",
  tips use readable text with an icon, and assumptions show their name
  ("TDSR ceiling: 55%") rather than a bare number.
- **Prompts are consistent bottom sheets** with large buttons; saving offers a
  suggested name and a "View" shortcut to Saved.

## Intro tour

First launch shows a 10-step guided tour (`lib/ui/tour.dart`). It dims the
app and spotlights one real element at a time — the question groups, recent
scenarios, a calculator's result, inputs, "Show the math" and save bar, then
the Saved, Compare and Settings tabs — with **Back / Next / Skip**. It opens
the Mortgage calculator and switches tabs itself, so each tip points at the
thing it describes.

- Elements opt in with `TourTarget(id: ...)`; a missing target centres the card
  instead of breaking the tour.
- Seen once, remembered (`prefs.json` on phones, localStorage on the web);
  **Settings → Replay the app tour** runs it again.
- Android back and browser back step the tour back; arrow keys and Escape
  work on desktop; taps outside the card never reach the app underneath.
- `test/tour_test.dart` walks all 10 steps on an iPhone-sized screen and fails
  if any spotlight finds nothing or lands off screen.

## On the web (for iPhone users)

The same code builds for the browser, so it runs on an iPhone in Safari with no
App Store. Three things differ from the Android build, each behind a
conditional import in `lib/platform/`:

| | Phone | Web |
|---|---|---|
| Saved scenarios | JSON file in app storage | same JSON in localStorage |
| Feedback queue | JSON file | localStorage |
| Export file | written to disk | downloaded (Files app on iPhone) |

Saved scenarios stay in that browser on that phone. They do not sync between
devices, and clearing Safari's website data removes them.

**Proof the numbers match.** On the web a Dart `int` is a JavaScript number
and `1.0.toString()` is `"1"`. `tool/web_parity.dart` prints every figure for
all golden cases and every calculator's defaults (699 lines: headlines,
metrics, notes, the worked maths, schedule totals, chart endpoints) and checks
the 139 expected figures. Run natively and compiled with dart2js — the same
compiler the web release uses — the two outputs are byte-identical:

```bash
dart run tool/web_parity.dart > build/parity_vm.txt
dart compile js -O2 -o build/parity.js tool/web_parity.dart
node -e "globalThis.self=globalThis;require('./build/parity.js')" > build/parity_js.txt
diff --strip-trailing-cr build/parity_vm.txt build/parity_js.txt
```

The golden cases are embedded in `test/golden_cases.g.dart` because a browser
cannot read files (regenerate with `python tool/embed_goldens.py`;
`golden_test.dart` fails if the copy is stale). `test/web_parity_test.dart` and
`test/web_storage_test.dart` are written for `flutter test --platform chrome`,
but that runner fails to load even a one-line test on this machine (Chrome
152), so the storage path was verified end to end in headless Chrome instead:
save, reload, reopen, export.

**Deploy.** `render.yaml` + `build.sh` deploy to a Render static site. The
build pins Flutter 3.44.4 and runs `flutter test` first, so a failing test
stops the deploy.

Tests: `flutter test` — 372 passing, plus the web parity check below. Golden coverage: every one of the 19
calculators has a golden file, 49 of 49 cases captured with named provenance.

## The architectural bet

A calculator is **data, not a screen**. Every tool is a `Calculator`
declaration — typed inputs, a pure compute function, an explanation — and
`lib/ui/screens/calculator_screen.dart` is the single renderer that walks it.

That means save, charts, the amortization schedule, "show the math" and the
error path are each built **once**, and every calculator inherits all of them.
Adding the thirteenth tool is one file in `lib/calculators/` plus one line in
`registry.dart`. Nothing else changes.

This is the direct inverse of the incumbent this app was designed against,
which built ~50 independent screens each with its own inlined formula. Every
later feature there cost fifty implementations, so none shipped.

## Precision

`lib/core/money.dart` — money is **integer cents**, never a double. Rounding is
**half-even** and happens once, at the display edge.

`lib/core/finance.dart` — the monthly rate is the nominal annual rate ÷ 12,
which is what Singapore banks quote and use. Schedules run in cents and the
final instalment is balanced so the closing balance is exactly zero.

`lib/core/solver.dart` — Newton–Raphson with a bisection fallback, tolerance
1e-10, capped at 100 iterations. **A rate that does not converge returns a
failure, never a plausible number.** The incumbent's worst review is about
wrong TVM results; that outcome is structurally excluded here.

Fixtures in `test/finance_test.dart` are pinned to values computed
independently in Excel (`PMT`, `RATE`, `NPER`, `IRR`, `NPV`) — e.g.
`PMT(0.005, 240, 200000) = -1432.862117`, and a 637,500 loan at 3.85% over
25 years giving 3,312.39 a month and 356,215 total interest.

## Golden harness — the only tests that are real evidence

`test/golden/` holds one JSON file per calculator. Each case pins our output
against a number **that came from outside this repository** — an official
calculator, a bank's tool, a published table.

This exists because the rest of the suite cannot catch the failure that
matters. `test('income tax on 120k = 5,880')` proves the band-walking loop
works; it proves nothing about whether the bands are right, because the test
and the code read the same table. A wrong statutory figure passes every test
in `calculators_test.dart` and is still wrong.

Two properties make the harness worth having:

- **A pending case cannot masquerade as verification.** Unfilled cases are
  reported by name in a coverage summary, so an empty golden file never looks
  healthy.
- **A captured case must cite its source.** A number with no provenance fails.

Run it:

```bash
flutter test test/golden_test.dart
```

It prints how many cases are externally verified and lists every one that is
not. To fill a pending case, follow `test/golden/README.md`: open the source,
enter the inputs verbatim, paste the result back, set `status` to `captured`.

**Never fill an expected value from this app's own output.** That is the single
thing that makes a golden file worthless.

### Provenance of the statutory tables

Every statutory figure now traces to a primary document, not a summary site:

| Table | Source | Read |
|---|---|---|
| Income tax bands, relief cap | IRAS `tax-calculator_residents_ya26.xlsm` | 13 Sep 2026 |
| BSD tiers, ABSD rates | IRAS "Duty Rates for Stamp Duty" on data.gov.sg | 13 Sep 2026 |
| CPF contribution rates | CPF Board `CPFcontributionratesfrom1Jan2026.pdf` | 12 Sep 2026 |
| CPF allocation rates | CPF Board `CPFAllocationRatesfromJanuary2026.pdf` | 12 Sep 2026 |
| TDSR 55%, 4% floor, LTV 75% | MAS published guidance (Notice 645 PDF unreachable) | 13 Sep 2026 |
| Basic Healthcare Sum, interest floors, extra interest | MOH/CPF release for 2026 | 13 Sep 2026 |
| Basic and Full Retirement Sums | MOM factsheet, BRS for members reaching 55, 2023–2027 | 13 Sep 2026 |

The IRAS spreadsheet confirmed the tax table at **every** threshold — 3,350 /
7,950 / 13,950 / 21,150 / 28,750 / 36,550 / 44,550 / 84,150 / 199,150.

Arithmetic-only cases (mortgage, HDB vs bank, refinance, affordability) were
recomputed in a **separate Python implementation using exact `Decimal`
arithmetic** — a different numeric model from Dart's doubles — and agree to the
cent.

No case is left pending. The CPF projection now implements the ceilings that
previously made it incomparable:

- **MediSave is capped at the Basic Healthcare Sum** (S$79,000). The cap
  applies to the BALANCE, not only to contributions, so credited interest is
  swept out too — without that sweep MediSave drifted to S$138,839 against a
  S$79,000 ceiling.
- **At 55 the Special Account closes** and a Retirement Account is formed from
  SA first, then OA, up to the Full Retirement Sum (S$220,400). Contributions
  past the FRS go to OA; the RA still grows on its own interest.
- **Interest accrues monthly and is credited annually**, including the extra
  interest tiers: +1% on the first S$60,000 combined below 55 (OA counting at
  most S$20,000), +2% on the first S$30,000 and +1% on the next S$30,000
  from 55.

`test/cpf_ceilings_test.dart` pins all of it. What it does NOT claim is a
match against CPF's own projection calculator — it verifies that the app
faithfully implements the published rules, cross-checked against a separate
Python implementation written from those rules. The BHS is still held flat
(CPF raises it most years), and housing withdrawals, top-ups and CPF LIFE are
out of scope; both are stated on the result.

### What this already caught

Cross-checking against a third-party app's published figures found a real bug:
the schedule ran **181 payments on a 180-month loan**. Rounding the level
instalment down leaves a few cents unamortised each month; the 25-year fixture
happened to land clean, so 63 passing tests never saw it. The final instalment
now absorbs the residue in both directions, as banks do.

## The nineteen tools

| Tool | Group | SG-specific |
|---|---|---|
| Home affordability | Can I afford it? | TDSR + MSR, stress-tested |
| Mortgage & amortization | What will this loan cost? | |
| HDB loan vs bank loan | What will this loan cost? | ✓ |
| Refinance break-even | What will this loan cost? | |
| Credit card payoff | What will this loan cost? | minimum-payment trap shown |
| Personal loan: flat vs effective rate | What will this loan cost? | ✓ |
| Car loan: Rule of 78 | What will this loan cost? | ✓ early settlement cost |
| CPF OA/SA/MA projection | Will I have enough later? | ✓ |
| Savings growth | Will I have enough later? | any compounding, APY |
| Time value of money | Is this investment worth it? | solve for PV/PMT/FV/RATE/N |
| Return on investment | Is this investment worth it? | annualised, after fees |
| Share average cost | Is this investment worth it? | 4dp SGX prices, break-even |
| What fees cost you | Is this investment worth it? | fund/ILP fee drag |
| Income tax | What do I actually take home? | ✓ |
| Stamp duty (BSD + ABSD) | What do I actually take home? | ✓ |
| Percentage change | Quick math | |
| Rule of 72 | Quick math | |
| GST inclusive / exclusive | Quick math | ✓ |
| Bill, service charge and split | Quick math | ✓ |

Tools are grouped by the **question you arrive with**, not by formula family.
Home-screen counts are computed from the registry, so the app can never
advertise more tools than it has.

## The ruleset — read this before shipping

`lib/rules/sg_rules.dart` holds every statutory figure as **data** with an
`effectiveFrom` and a `verifiedOn` date, surfaced to the user in Settings and
overridable at runtime.

**The shipped values are a starting point, not an authority.** TDSR/MSR
ceilings, LTV limits, CPF allocation bands and wage ceilings, income tax
bands, BSD tiers, ABSD rates and GST all change. Re-verify against MAS, IRAS
and the CPF Board, then update `verifiedOn`. Settings shows an amber warning
once the ruleset is over 180 days old.

Hardcoding these inside individual calculators is exactly why the incumbent
goes stale and cannot support another country. Here, a rate change is a data
edit and adding Malaysia is a data task.

## CPF rates: primary source, and why secondary sources were not enough

`contributionForAge` and `allocationForAge` are transcribed from the CPF
Board's own PDFs, effective 1 January 2026:

- `CPFcontributionratesfrom1Jan2026.pdf`
- `CPFAllocationRatesfromJanuary2026.pdf`

Both were read on 12 Sep 2026. This matters because **web search gave the
wrong numbers for three of the five contribution bands.** Had the table been
filled from search results it would have shipped wrong. The published table
gives the total and the employee share; the employer share here is the
difference.

Two traps in this table worth knowing:

- The first band is **"55 & below"**, so an employee aged exactly 55
  contributes at 37%, not 34%. A test asserting 34% at age 55 was wrong.
- A **swapped employee/employer split still sums to the correct total**, so
  the 65–70 band read 9/7.5 instead of 7.5/9 and passed a total-only
  assertion. `statutory_rules_test.dart` now pins each share individually.

## Seeded values never masquerade as the user's own

A calculator that opens showing `850,000` at full ink is making a claim about
someone's money that nobody made. So until a field is edited:

- the value is drawn **translucent**, the way placeholder text is, along with
  its `SGD` prefix and unit suffix, so the whole row reads as one state;
- the result badge says **EXAMPLE**, not LIVE;
- seeded scenarios on Home and in Saved carry an `EXAMPLE` pill and a
  translucent figure.

Editing a field snaps *that row* to solid and flips the badge to LIVE; every
other row stays marked. `Scenario.isExample` is the single source of truth so
the label cannot be right on one screen and missing on another, and
`seriesColor` does the same job for chart legends and strokes.

`test/example_state_test.dart` covers all of it, including that an edited
value actually drives the result rather than merely restyling.

## Property-based tests

`test/properties_test.dart` fuzzes thousands of random inputs against laws
that must hold for every one of them — principal payments summing to exactly
the loan, schedules closing at zero, monotonicity in every lever, PV/FV and
RATE/NPER round trips, tax continuity across band boundaries, allocation
shares summing to one at every age.

It also computes the remaining balance a **second, independent way** (the
closed form `B_k = P(1+i)^k − M((1+i)^k − 1)/i`) and checks it against the
iterated schedule, so agreement is evidence rather than a restatement.

## Bug hunt before deploy

`test/robustness_test.dart` targets places that looked wrong on inspection
rather than places a feature was being added. It found four:

1. **The `scenarios` getter sorted the private list in place.** Reading state
   mutated it — the seed of iteration-order bugs and concurrent-modification
   crashes. It sorts a copy now.
2. **A clamped input showed one number and computed with another.** Typing
   `99` into a rate capped at 8 left `99` on screen while the app used 8. It
   now says *"Using the maximum, 8%"* in amber and snaps the field to the real
   value on blur.
3. **Choosing what TVM solves for flipped the badge to LIVE.** Rearranging the
   question is not the user supplying a figure, so the seeded values are still
   examples. `_setMode` changes a value without marking it touched.
4. **`Money.tryParse("--5")` returned 5.** A minus is only meaningful once, at
   the front; anything else is now rejected rather than quietly accepted.
5. **Long choice pills scrolled off-screen.** "Pay a fixed amount" sat half
   outside the card. Choice rows with long or many options now wrap under the
   label; the last row no longer centres itself.
6. **A mode switch left an ignored field on screen.** Credit card showed both
   "Monthly payment" and "Clear it within" whichever mode was chosen. Inputs
   can declare `showWhen`, and hidden inputs are left out of the CSV export.
7. **Picking any option flipped EXAMPLE to LIVE.** Choices no longer count as
   the user supplying a figure; only typed numbers do.

8. **Clearing a field closed the keyboard.** Deleting "8,000.00" passes
   through "0", the result becomes an error, the assumption chips above the
   inputs disappeared, the input card shifted one slot in the list and was
   rebuilt — dropping focus mid-edit, on every platform. The chip row now
   keeps its slot. Found by driving the web build in headless Chrome; the
   regression test was checked to fail with the bug put back.
9. **OPEN on a saved scenario showed the example numbers.** The Saved tab
   pushed the calculator without the scenario's inputs, so a saved S$12,000
   balance reopened as S$8,000. Saved inputs are restored and read as LIVE;
   Recent cards on Home now open their scenario too. Mutation-checked.
10. **Save looked tappable during an error but did nothing.** It is now
    visibly disabled, and Export stays in place disabled so the bar does not
    jump.
11. **Tapping a figure put the caret where the finger landed**, so editing
    "8,000.00" from the middle produced "1200000". A tap now selects the whole
    figure and typing replaces it.
12. **Metric labels were cut off at iPhone width** ("MINIMUM-ONLY INTERE…").
    They wrap to two lines, with values in a row kept level.

Incumbent cross-check: the Bishinews savings screen (10,000 + 1,000 a month,
1 year, 2.125% compounded monthly, start of month) shows S$22,353.61 and
2.1458% APY. Basis produces both exactly; the case is pinned in
`test/golden/savings_growth.json`.

## Bugs found by verification, not by writing more tests

Worth recording because each was invisible to the tests that existed at the time:

1. **181 payments on a 180-month loan.** Rounding the level instalment down
   left cents unamortised each month. Caught by cross-checking a third-party
   app's published figure; the 25-year fixture happened to land clean.
2. **Blank screen on every pushed route, release builds only.** `BasisTheme`
   wrapped `home:`, making it a *sibling* of pushed routes rather than an
   ancestor. Debug fired the assert; release strips asserts, so the null check
   threw and the route rendered nothing. Caught by running a release APK on a
   real emulator. `test/navigation_test.dart` now guards it.
3. **Infinite-height layout crash in `SeriesChart`.** `CrossAxisAlignment.stretch`
   on a `Row` inside an unbounded parent. Same emulator run.
4. **A loan whose instalment rounds to zero returned an empty schedule.** The
   "payment cannot cover interest" guard fired before the final-period payoff
   could run, so `rows.last` threw. Found by property tests on adversarial
   inputs, not by any fixture.
5. **CPF employee/employer split reversed on the 65–70 band.** Invisible to a
   total-only assertion; caught by reading the primary source.

The lesson is in the pattern: all three needed an oracle outside the code —
another tool's numbers, or the app actually running in release.

## What is built

All four gaps from the first cut are closed.

**Persistence** — `lib/storage.dart` writes JSON with `dart:io` into the app's
private directory, chosen so it survives a restart on each platform. Plugins
were not an option (`shared_preferences` needs Windows Developer Mode to
build), and the store degrades to in-memory rather than ever taking the app
down. One corrupt record is skipped, not allowed to lose the file, and writes
go to a sibling then rename so an interrupted write cannot destroy good data.
Verified on device: save, force-stop, relaunch, still there.

**Compare** — recomputes every column from the scenario's stored inputs
against the *current* ruleset, so a scenario saved before a rate change shows
today's figure. Direction of improvement is declared by the calculator
(`Better.lower` / `Better.higher`), never guessed from a label, because lower
is better for interest paid and worse for interest earned. Where the selected
scenarios come from different calculators it says so and marks nothing best.

**Export** — CSV covering inputs, result, assumptions and the full schedule,
to the clipboard or to a file whose path is shown. A share sheet and a PDF
writer are both plugins, so neither is pretended at.

**Quick math** — percentage, Rule of 72, GST, and a bill splitter that applies
service charge first and GST on the subtotal, which is the Singapore ordering.
Adding 19% straight to the bill gives the wrong answer and there is a test
pinned against exactly that mistake.

## Loan-to-value is not a flat 75%

Full LTV requires BOTH a short-enough tenure (30 years private, 25 HDB) AND
the loan to finish by age 65. Fail either and it drops to 55%, which cuts the
maximum price by roughly a quarter.

Applying 75% flat — which this did until it was fixed — overstates borrowing
power for anyone borrowing later in life, the group least able to absorb being
told they can afford more than they can. A 50-year-old over 25 years goes from
S$682,029 to S$555,556, and the result says why: *"LTV cut to 55% — Loan ends
at 75, past 65."*

`test/ltv_rule_test.dart` pins the rule, including the boundary where a loan
ending exactly at 65 still keeps full LTV.

## What "accurate" means here, precisely

| Layer | Status |
|---|---|
| Arithmetic engine | Cross-validated against a third-party app and an independent `Decimal` implementation |
| Income tax, stamp duty, ABSD | **Primary** — IRAS calculator spreadsheet and IRAS dataset on data.gov.sg |
| CPF rates, allocation, BHS, FRS, interest | **Primary** — CPF Board, MOH and MOM documents |
| TDSR, MSR, stress floor, LTV limits | **Secondary** — MAS blocks automated access; Notice 645 could not be read |

That last row is the one honest gap left. MAS returns bot-protection error
pages for both the Notice PDFs and their own explainer, so those four figures
rest on MAS-published guidance quoted elsewhere rather than on the Notice.
They are stated on screen and in the result footnote so nobody mistakes them
for verified.

## Known gaps

- **No live FX.** A currency converter needs a rates API; not built rather
  than shipped with stale rates.
- **Car loan limits not applied.** MAS minimum down payment and maximum
  tenure, and lenders' early-settlement fees, are stated but not enforced.
- **Card minimum payment is one rule** (3% or S$50). Cards differ.
- **Statutory truth is not self-certifying.** The shipped Singapore rules remain
  versioned data and must be checked against MAS, IRAS, and CPF Board before
  production use. Formula tests prove implementation behavior; they do not
  prove that a statutory rate is current.
