# Stage 3 — Confirmed receipt saving

22 October 2026. This stage improves the existing confirmation flow and local persistence. No schema changes, migrations, new packages, real bank transfers or production backend changes.

## Changes

- `lib/services/database_service.dart`: added confirmed-save/delete operations. The original persisted transaction is read by ID and owner inside a SQLite transaction. Old balance effects are reversed, new effects are applied and the ledger write commits together. A failed insert, update or delete rolls everything back. New accounts must exist and belong to the owner. Same-ID identical create retries are idempotent; a conflicting create or missing edit fails safely. Existing raw CRUD remains for legacy imports/test fixtures, not UI saves.
- Amounts must be finite, positive, no greater than RM100,000,000 and round to at least one sen. Confirmed amounts and balance deltas use integer sen, converting back only for compatibility with existing REAL storage. Account signs retain existing asset/liability/other behaviour. A deleted legacy source account is not recreated when its transaction is edited/deleted; no unrelated owner's account is touched.
- `lib/providers/expense_provider.dart`: UI CRUD uses the confirmed operations and refreshes from persisted state after commit. There is no optimistic balance to roll back incorrectly. Edits outside the selected month use the original database record. Chart revisions refresh after commits. Loads capture owner/month and discard superseded results to avoid stale data replacing newer state. Post-commit refresh/sync errors do not report a locally committed transaction as an unsuccessful save and invite duplicate submission.
- `lib/screens/add_transaction_screen.dart`: rejects nonfinite/excessive/sub-sen amounts before submission. Existing account selection and repeated-tap guard are retained.
- `lib/widgets/receipt_summary.dart`: existing collapsed Receipt details displays item subtotal and signed receipt-total-minus-items difference. Incomplete prices display only the known-item subtotal; no invented missing values or claim of full reconciliation. No new warning paragraphs or duplicate review screen.
- `lib/services/ai_receipt_service.dart`: derived mismatch flags are recomputed after edits rather than preserving an obsolete mismatch.

## Tests changed

- New `test/confirmed_transaction_test.dart`: real SQLite tests for idempotence, edits across accounts/dates/categories, deletion retries, injected insert/update/delete failures, owner isolation, input validation, liability/manual-income signs, concurrent writes, sen rounding and provider edits/deletions outside its selected month.
- Updated `test/receipt_summary_test.dart`: expandable totals/difference.
- Updated `test/receipt_validation_stage2_test.dart`: corrected receipt totals clear the old computed mismatch.

## Important limits

The parent expense remains authoritative; item notes never create extra ledger rows. Structured item-category allocations are still deferred, and differences are displayed rather than automatically distributed. This is reconciliation for review, not completed item-level budget allocation. Manual transactions do not require items.

No old records or balances are rewritten retrospectively. This prevents new partial-save inconsistencies; it does not automatically repair historical inconsistencies. Raw import APIs do not apply balance deltas. Existing cloud retry/deletion limitations remain for Stage 4; local SQLite atomicity does not make remote uploads atomic. A post-commit reload failure may leave a stale view until refresh. Month-end query and shared budget totals are also Stage 4 work.

No phone camera/device run, new APK installation or live Supabase test was performed. Onboarding stays on hold.

## Verification

- Focused final suite: **19 passed** (confirmed transactions, receipt summary/review, Stage 2 receipt validation).
- Full Flutter suite: **90 passed**. Log: `tmp/stage3-all-tests.log`.
- Initial verification processes stalled before executing tests and were restarted; those runs are not counted as passes. The first completed retry found a `num` versus `double` type error in the new test fixture; the fixture was corrected before the successful runs above.
- Full `flutter analyze --no-pub`: **0 errors, 4 existing warnings, 86 informational notices**, exit 1. Four new braces-only style notices in the new database/state guards were corrected afterward. Final targeted `dart analyze` of database/state files: **0 errors, 0 warnings, 10 existing informational notices**, exit 0. No behaviour changed after the successful test run. Logs: `tmp/stage3-analyze-final.log`, `tmp/stage3-final-style.log`.

## Next step

Stage 4: integrate the committed ledger with shared sen-based category/budget/analytics calculations, correct period boundaries, and address reliable cloud deletion/retry before expanding Coach evidence. Item allocations must reconcile exactly to one parent before being used for category budgets.
