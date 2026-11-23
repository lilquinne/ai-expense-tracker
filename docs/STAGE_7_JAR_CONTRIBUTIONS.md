# Stage 7 — Treasure Jar contribution guidance

24 October 2026.

## Delivered

- Added a pure `JarContributionPlan` service with a required as-of clock, integer-sen arithmetic and no persistence operations.
- Existing jar cards now show alternative weekly and monthly contributions based on the target minus saved reservations. Schedules start today and include an aligned deadline. Choose one schedule; they are not amounts to add together.
- Weekly opportunities occur today and every seven calendar days through the deadline. Monthly opportunities use today's day of month and clamp to shorter months without drifting (January 31, February 28/29, March 31). Date-only UTC arithmetic avoids daylight-saving day-count errors.
- Equal contributions round upward to sen; the last contribution can be smaller. Stop once the target is met. Counts represent maximum available opportunities, not a required number of nonzero payments.
- A deadline today requires the remaining amount today. Overdue jars ask for a revised date, undated jars invite a target date, and completed targets need no further contribution.
- Account availability and underfunded-reservation messages remain alongside the plan. No income-based affordability claim is made: a recurring contribution estimate does not prove future funds are available.
- Existing save, reserve, release and history flows remain the only ways saved amounts change. Viewing a plan never adds money or creates transactions. No automatic posting, transfers, schema changes or dependencies.

## Verification

- Full Flutter regression: **114 passed** (`tmp/stage7-tests.log`).
- Final focused contribution and narrow-screen checks: **6 passed** (`tmp/stage7-focused-final.log`), including a new 320-pixel-wide jar-card test after the final wording adjustment.
- Targeted analysis: **0 errors, 0 warnings, 10 informational style notices** (`tmp/stage7-analysis.log`).
- Coverage includes inclusive weekly opportunities, monthly clamping without drift, leap years, same-day/overdue/missing deadlines, rounding, partial savings and a read-only narrow-screen card.
- Files: `lib/services/jar_contribution_service.dart`, `lib/screens/treasure_jar_screen.dart`, `test/jar_contribution_test.dart`, `test/jar_contribution_widget_test.dart`.

## Limits and next

No device run or new APK installation. Estimates depend on the saved target, reservations and date. There is no recurring income forecast, automatic contribution scheduler or combined multi-jar affordability estimate. Jar data remains local to the device.

Stage 8: final regression/release checks, document remaining limitations, then prepare a verified build for phone testing. Onboarding and item-level category allocations remain deferred.
