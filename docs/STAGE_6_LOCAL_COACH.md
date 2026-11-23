# Stage 6 — Calculated Coach evidence without AI

24 October 2026.

## Delivered

- Added an owner-scoped local calculation path before cloud preparation and AI requests. Supported standalone questions cover remaining category budgets, matched previous-month comparisons, spending pace, top categories/largest purchases, and recorded Treasure Jar progress.
- Simple local questions do not upload records, sync cloud data, require Groq availability or consume AI allowance. Existing online-account access controls remain: a cached authenticated session can work without network access; this does not enable signed-out access.
- Question-specific retrieval: jars read only the owner's jars; category/pace questions read the selected month; comparisons add the previous month; budget questions add only the selected month's budgets. No receipt images, item notes or account details are read or transmitted for these calculations.
- Calculations reuse Stage 4 integer-sen amounts and Stage 5 controlled-clock spending rules. Future entries do not become actual spending. Future months and sparse comparison/forecast evidence explain missing information rather than inventing values.
- Budget amounts describe saved spending and signed remaining/over-budget balances. Selected categories restrict both budgets and expenses. Default answers explicitly state all expense categories and the selected month.
- Category changes and largest purchases provide recorded evidence. Jar answers describe current saved reservations and remaining targets, without claiming bank deposits or affordability. Required contributions remain Stage 7 work.
- Local answers share the existing validated CoachReply shape and Numbers used panel, and are labelled as calculated on this device. They do not falsely claim an AI outage. Local load errors do not silently send the question to an external service.
- Existing generation/owner guards discard pending responses after a session change. A prior savings-plan discussion no longer prevents a later standalone budget question from using local calculations.
- Added budget and jar starter questions and updated the data-sharing notice. General advice, confirmed savings-plan evaluation, unsupported explicit periods and ambiguous mixed-intent questions retain the existing contextual online path.

## Files

- `lib/services/local_coach_service.dart`
- `lib/services/spending_coach_service.dart`
- `lib/screens/spending_coach_screen.dart`
- `test/local_coach_test.dart`
- `test/spending_coach_test.dart`

## Verification

- Full Flutter regression: **109 passed** (`tmp/stage6-regression.log`).
- Final focused rerun after routing adjustment: **12 passed** (`tmp/stage6-focused-final.log`).
- Completed targeted analysis before that adjustment: **0 errors, 0 warnings, 20 informational style notices** (`tmp/stage6-analysis-final.log`). Final analysis rerun: **0 errors, 0 warnings, 21 informational style notices** (`tmp/stage6-analysis-verified.log`).
- New tests cover over-budget arithmetic, future-entry exclusion, sparse/future periods, jar reservation wording, conservative intent routing, owner-scoped real SQLite retrieval, and a widget answer that succeeds while both sync and AI callbacks throw if invoked.
- Initial analysis caught two integration errors (a nullable response capture and an incorrectly edited metric-label map); both were corrected before the passing regression run. Initial Flutter startup stalled and was restarted only after verifying exact test-process identities.

## Limits

This is a bounded English intent router, not general natural-language understanding. It does not evaluate arbitrary questions or guarantee complete records. Existing remote Coach retrieval, quota behavior and confirmed-plan evaluation are unchanged. Local answers use saved on-device records, which may differ from another device or the cloud while sync is pending.

No new backend code, dependency, schema, production operation, device installation or live AI call. Onboarding and item-level budget allocations remain deferred.

## Next

Stage 7: extend Treasure Jars with deterministic required weekly/monthly contributions and optional feasibility guidance. Planned contributions must never increase actual saved balances.
