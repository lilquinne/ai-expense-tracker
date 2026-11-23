# Stage 2 — Receipt reliability

22 October 2026. Focused changes to existing services; no database migration, new package, screen, cloud deployment or transaction format change.

## Changes and decisions

- `lib/services/ai_receipt_service.dart`: AI receipts now reuse local receipt categorization. Exact remembered basket choices and strong local product evidence take precedence; weak evidence retains a valid AI category. Manual edits retain the user's category. Unknown fields remain unknown instead of borrowing speculative totals, dates or prices.
- The same service rechecks item sums and quantity/price consistency at the client boundary, including manual edits. Sums use rounded integer sen with a one-sen rounding tolerance. Differences are recorded in existing review metadata; the total and item prices are never rewritten to force agreement. Partial item lists with missing prices are not claimed to reconcile. No extra warning paragraphs were added to the scan screen.
- `lib/services/ai_categorization_service.dart`: receipt metadata rejected by the existing item cleanup is excluded from item-category scoring. Existing merchant, household, grocery and learned rules remain in use.
- `lib/services/receipt_parser.dart`: local monetary values reject nonfinite, negative and excessive values (same maximum as AI receipt validation). Signed refund/credit totals are not stripped into positive expenses; those need manual review. This does not implement a refund transaction workflow.
- `test/receipt_validation_stage2_test.dart`: eight regression tests cover local/AI consistency, remembered choices, manual precedence, user separation, mismatches, incomplete lists, sen rounding, malformed AI fallback, signed/oversized totals, invalid price weights and repeated purchases.

## Scope and limitations

One parent expense is still saved; items remain notes. There is no item-level budget splitting, automatic physical receipt deduplication or automatic price correction. Existing manual transactions and merchant normalization are preserved. Review metadata is not yet a reconciled allocation model. Missing/ambiguous OCR still requires user confirmation, and actual camera recognition was not tested on a phone in this stage.

The audit's atomic transaction saving, month boundary, cloud deletion and budget-total issues belong to subsequent focused stages. No claim is made that Stage 2 fixes them. Onboarding remains on hold.

## Verification

- Focused receipt tests: **36 passed** (new Stage 2 tests plus existing AI receipt and category tests).
- Full Flutter suite: **81 passed**, including existing receipt review, account selection, budget, analytics, Coach and Treasure Jar tests.
- `flutter analyze --no-pub`: completed with **0 errors, 4 existing warnings and 84 informational notices**, exit 1. One new notice required braces around a parser guard; corrected it, then `dart analyze lib/services/receipt_parser.dart` returned **No issues found**. The remaining warning/style baseline was documented in Stage 1. The full analyzer was not rerun after this braces-only correction.
- Logs: `tmp/stage2-focused.log`, `tmp/stage2-all-tests.log`, `tmp/stage2-analyze.log`.
- No backend source changed, so no deployment was needed. No APK was built or installed for this source-level stage.

## Recommended next step

Stage 3: strengthen confirmed receipt saving and persistence, then introduce explicit reconciled allocations only when the parent amount, account changes and manual-entry compatibility are protected by tests. Keep allocations separate from ledger expenses.
