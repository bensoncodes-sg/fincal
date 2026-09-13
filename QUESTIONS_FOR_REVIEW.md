# Questions for someone who works in this daily

These are the things testing cannot settle. Every one is a judgement call
about Singapore practice, not arithmetic — the arithmetic is cross-checked
against IRAS, CPF and MOM documents and an independent implementation.

Roughly fifteen minutes. Answers in the margin are fine.

---

## 1. The four figures I could not source (highest priority)

MAS blocks automated access, so these four came from MAS guidance quoted
elsewhere rather than from Notice 645 itself. **Everything in "Can I afford
it?" rests on them.**

| Figure | App uses | Right? |
|---|---|---|
| TDSR ceiling | 55% | |
| MSR ceiling (HDB/EC only) | 30% | |
| Stress-test floor rate | 4.00% | |
| LTV, first housing loan | 75% | |
| LTV when reduced | 55% | |

**Q1.1** Are all five current?

**Q1.2** The app drops LTV from 75% to 55% when either the tenure exceeds
30 years (25 for HDB) **or** the loan runs past age 65. Is that the right
trigger, and is it "past 65" or "at 65"?

**Q1.3** TDSR is applied to gross monthly income with no haircut. In practice
variable income, commission and self-employed income get discounted. Should
the app ask, or is a plain-income version honest enough if it says so?

---

## 2. Affordability — is the answer the useful one?

**Q2.1** The result is "maximum property price". Is that what someone actually
wants, or do they want "monthly instalment I can carry"?

**Q2.2** It uses the stress rate (4%) for the *maximum loan*, then shows the
instalment at that same stress rate. Real instalments would be lower at
today's rates. Is showing the stressed figure right, or misleading?

**Q2.3** Cash-versus-CPF is a single "Cash and CPF available" input. Worth
splitting, given the 5% minimum-cash rule on the down payment?

---

## 3. CPF projection

The rates, allocation bands, BHS (S$79,000) and FRS (S$220,400) are taken
from CPF Board, MOH and MOM documents.

**Q3.1** The BHS is held flat over the whole projection. CPF raises it most
years. Better to assume a growth rate — and if so, what?

**Q3.2** At 55 the app forms the RA from SA first, then OA, up to the FRS, and
sends later contributions to OA once the RA is full. Correct?

**Q3.3** Housing withdrawals are ignored entirely. For most people the OA is
drained by a mortgage — does a projection that ignores that mislead more than
it helps?

**Q3.4** Extra interest is modelled as +1% on the first S$60,000 (OA counting
at most S$20,000) below 55, and +2%/+1% tiers from 55. Right?

---

## 4. Mortgage and refinance

**Q4.1** The monthly rate is the nominal annual rate ÷ 12, monthly rest. Is
that what SG banks actually do, or do some use a different basis?

**Q4.2** Refinance break-even counts cumulative interest saved against the
switching cost. Should the lock-in penalty on the *existing* loan be a
separate input rather than folded into "switching cost"?

**Q4.3** HDB-vs-bank holds the bank rate flat for the whole tenure. That
flatters a floating package. Worth modelling a reprice after the lock-in?

---

## 5. Tax and stamp duty

Bands come from the IRAS YA2026 calculator and the IRAS stamp duty dataset.

**Q5.1** Reliefs are a single "Total reliefs" input capped at S$80,000. Would
itemising (earned income, CPF, parent, course fees) be worth the extra
friction?

**Q5.2** Stamp duty applies no reliefs — no married-couple remission, no
en-bloc. Is that an acceptable v1 given it says so?

**Q5.3** Is BSD/ABSD normally wanted alongside the affordability answer rather
than as a separate tool? It is a large cash cost people forget.

---

## 6. What is missing

**Q6.1** Of these, which would you reach for first?
CPF LIFE payout · SRS relief optimiser · endowment or ILP vs investing ·
policy IRR from a surrender-value table · TDSR across joint borrowers

**Q6.2** If you handed this to a client, what would they ask that it cannot
answer?

**Q6.3** Anything here that would embarrass you to put in front of a client?

---

## 7. Trust

**Q7.1** The app shows its assumptions on every result and says when a figure
is unverified. Useful, or noise?

**Q7.2** Seeded example values are greyed out and badged EXAMPLE until edited,
so they cannot be mistaken for the user's own figures. Does that read clearly?

**Q7.3** Would you trust a number from this enough to repeat it to a client —
and if not, what would have to change?
