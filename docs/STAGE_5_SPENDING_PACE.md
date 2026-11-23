# Stage 5 — Spending pace and comparisons

24 October 2026.

## Delivered

- New deterministic `SpendingPace` calculation service, using per-entry integer sen and an explicit `asOf` clock. No AI calls or remote data are required.
- Current-month daily average and month-end projection: recorded expense sen divided by inclusive elapsed calendar days, multiplied by calendar days in the month, rounded once to sen.
- Forecast eligibility requires at least seven elapsed calendar days and expenses on three distinct dates. Empty/sparse months show insufficient history. Future months never forecast. Completed months show actual recorded totals without a forecast.
- Entries after the supplied timestamp, income, nonfinite and nonpositive amounts are excluded. Existing recorded ledger/report totals remain unchanged, so they can include future-dated entries that pace excludes.
- Previous-month comparisons use matching day counts and matching time of day for an active partial day. Shorter previous months cap both comparison windows to that month's day count. Completed periods compare equally long prefixes. December/January and leap years use calendar boundaries.
- Previous-month comparison requires expenses on at least three distinct dates. Missing/sparse records do not become an assumed zero baseline. Percentage change is absent for a zero baseline. These are recorded-spending comparisons, not proof that every expense was entered.
- Category increases are derived from the same matched comparison windows; their signed deltas reconcile to total change. Largest current-month purchases provide transaction evidence and are labelled as largest recorded expenses, not asserted to be causes of an increase.
- The Budget Tracker now includes a spending pace card. With budgets, its scope is only budgeted parent categories and its allowance is the sum of those limits. Without budgets, it shows all expense categories and omits allowance guidance.
- Remaining budget per day is the nonnegative unspent allowance divided by calendar days after today. Overspent budgets show zero; completed months and months without a positive budget omit it. This is an allowance calculation, not a guarantee of affordability.
- Data reloads on owner, ledger revision and transaction-list changes, with loading/error/retry handling and stale-owner FutureBuilder separation. Estimates recompute when the card rebuilds; no timer, new background work or notification thresholds were added.

## Files

- `lib/services/spending_pace_service.dart`
- `lib/widgets/spending_pace_card.dart`
- `lib/screens/budget_screen.dart`
- `test/spending_pace_test.dart`
- `test/spending_pace_card_test.dart`

## Verification

- Full Flutter regression: **103 passed** (`tmp/stage5-tests.log`).
- Targeted analysis of the new service, widget and tests: **No issues found** (`tmp/stage5-analysis.log`).
- New tests cover timestamp exclusion, income exclusion, sen totals, forecast thresholds, completed/future months, remaining allowance, matched category deltas, sparse previous history, leap years/short February, year boundaries and a 320-pixel-wide future-month card.
- No physical phone run, APK installation, live cloud operation, production deployment, schema or dependency change.

## Limits and next step

The linear projection assumes the observed daily rate continues. It does not model paydays, recurring bills, seasonality or missing entries. Eligibility is an explicit data sufficiency heuristic; no stored budget creation date or complete-record guarantee exists. Structured item allocations remain deferred. Comparison category grouping uses existing parent categories.

Stage 6: extend the existing Coach with calculated budget, comparison and jar evidence, selective retrieval and useful deterministic responses when AI is unavailable. Onboarding remains on hold.
