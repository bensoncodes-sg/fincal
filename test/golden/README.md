# Golden files

Each JSON file here holds cases for one calculator. A case is only evidence if
its number came from **outside this repository** — an official calculator, a
bank's own tool, a published table, a real statement.

Tests written against numbers I produced prove only that my arithmetic agrees
with itself. These files exist to break that circularity.

## Filling in a pending case

1. Open the URL in `source`.
2. Enter exactly the values in `inputs` — nothing else, no rounding.
3. Copy the result back into `expect`.
4. Change `status` to `"captured"`, set `capturedOn` to today and `capturedBy`
   to your name.

Run `flutter test test/golden_test.dart` and it will tell you what is still
pending.

## Fields

| Field | Meaning |
|---|---|
| `calculator` | `Calculator.id` from `lib/calculators/registry.dart` |
| `source` | Where the expected number came from. Required for `captured`. |
| `status` | `pending` or `captured` |
| `capturedOn` | ISO date the number was read off the source |
| `capturedBy` | Who read it |
| `cases[].inputs` | Keys must match the calculator's `CalcInput.key` |
| `cases[].expect.primary` | The headline figure, as the source states it |
| `cases[].expect.secondary` | Map of metric label to expected value |
| `cases[].toleranceCents` | Allowed difference. Default 1 cent. |
| `cases[].note` | Why this case is worth pinning |

## Rules

- **Never fill `expect` from this app's own output.** That is the one thing
  that makes a golden file worthless.
- A tolerance above about 100 cents usually means the two tools disagree on a
  convention (day count, rest basis, when payments land). Write the convention
  difference in `note` rather than widening the tolerance silently.
- If the source disagrees with us by more than rounding, **the source wins
  until proven otherwise.** Investigate before changing the tolerance.

## Where to get oracles

| Calculator | Suggested source |
|---|---|
| `mortgage`, `refinance` | Any SG bank's public repayment calculator |
| `hdb_vs_bank` | HDB's own loan calculator, plus a bank's |
| `affordability` | A bank's affordability / TDSR tool |
| `income_tax` | IRAS individual income tax calculator |
| `stamp_duty` | IRAS stamp duty calculator |
| `cpf_projection` | CPF Board's retirement / contribution calculators |
| `tvm` | Excel `PMT`/`RATE`/`NPER`, or an HP-12C |
