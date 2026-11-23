# Stage 1 — Spendly workflow audit

Date: 21 October 2026. Scope: local source and automated checks; no production database changes or live AI requests. This audit does not certify the deployed backend or phone OCR accuracy.

## Existing architecture and working foundations

- Flutter uses `ExpenseProvider` (ChangeNotifier), SQLite via `DatabaseService`, and `SupabaseSyncService` for cloud uploads. Keep these patterns.
- `OcrService` uses on-device ML Kit, geometry-based text ordering and a contrast retry. `ReceiptParser` extracts receipt fields; merchant aliases and saved shop names help normalize merchants.
- `AiReceiptService` calls an existing Supabase function. Both client and backend validate field types, categories, finite amounts and dates. Backend receipt validation flags mismatched item totals. Failed AI extraction preserves the local result.
- Review supports editable receipt fields/items and calendar dates. Saving creates one parent expense. Item names/prices become notes, not extra expenses. Manual transactions need no receipt items. The save button guards repeat taps.
- Dashboard Week/Year charts, touch amounts, Records navigation, central Scan navigation and account-backed Treasure Jars already exist. Do not rebuild them.
- Budgets and analytics derive from provider transactions; mutations notify listeners. Budget alerts explicitly filter by category/month and warn at 80%/100%. Notification history limits repeated threshold alerts. Budget analysis already displays transaction notes.
- Coach retrieves authenticated cloud records, computes amounts in sen on the backend, and validates generated numeric placeholders. Category rankings and explicit simple goal questions can bypass the language model. Provider/validation failure has a calculated fallback after records have been retrieved.
- Private Groq credentials are read from backend environment variables. No Groq private key or service-role key reference was found in Flutter `lib`. Receipt OCR text goes to extraction; Coach sends aggregate evidence plus the question/history to Groq, not receipt photos or account identifiers. Ordinary cloud sync separately uploads transaction fields including notes and receipt path strings.

## Findings to address

| Priority | Finding and source | Practical impact / proposed correction |
| --- | --- | --- |
| High | `database_service.dart:getTransactionsByMonth` ends at last day 23:59:00 inclusive. | Records at 23:59:01–23:59:59 are omitted. Use start-inclusive, next-month-exclusive bounds and test leap years/year boundaries. |
| High | Provider mutation writes the transaction, then account balance separately. Catch paths restore memory but do not undo a committed ledger row. | Partial failure can leave persisted records and balances different. Commit local ledger/account changes together, then publish state and sync. |
| High | Edit/delete finds the old transaction only in the selected month's in-memory list. | Operating on a record outside that list may not reverse its old balance effect. Fetch the owned persisted record by ID within the mutation. |
| High | Cloud `_run` swallows failures; snapshot uploads upsert current rows but do not replay failed deletions. | A deleted local expense can remain in cloud Coach results. Add a durable, owner-scoped retry/deletion strategy without deleting unrelated cloud records. |
| High | Transaction/budget amounts and most local totals use doubles/SQLite REAL. Jars, chart sums and Coach already use sen. | Different calculations use different rounding policies. Add one validated sen conversion/calculation path; preserve old data while planning any additive storage change. |
| High | Manual amount/budget validation checks parsing and positivity but not finiteness/upper bounds at all entry points; DB mutation methods lack central financial validation. | NaN/infinity or invalid programmatic values can bypass UI assumptions. Validate at the persistence boundary as well as forms. |
| Medium | Receipt items are not persisted as structured, categorized allocations. Only one dominant transaction category is stored. | Mixed receipts cannot accurately split category budgets. Introduce confirmed allocations under the existing parent, never additional ledger expenses. |
| Medium | `getBudgetUsage` and category-card usage cap ratios at 150%; card bar caps at 100%. | Keep a capped visual bar, but display the uncapped numeric percentage and signed remaining amount. Handle zero limits explicitly. |
| Medium | Budget overview subtracts all expenses from the sum of category limits. | Unbudgeted spending affects this number. Separate spending within budgeted categories from unbudgeted spending and label both. |
| Medium | Budgets group by parent enum, while analytics may group custom category IDs. | Define parent/subcategory aggregation once so reports explain the same spending consistently. |
| Medium | No deterministic budget pace/forecast service or category/transaction increase attribution. | Add tested, date-aware calculations before any AI explanation. New/sparse budgets need an insufficient-data state. |
| Medium | Coach queries transactions/categories, not budgets or saved jars; it omits transaction titles/notes from evidence. | Remaining-budget, goal-progress and individual purchase-contributor answers are not implemented. Retrieve only the additional evidence needed for each question. |
| Medium | Coach requires a configured Groq key and consumes shared AI quota before deterministic category/goal answers. | Calculated answers should not require an AI call or consume an AI allowance. Network/sync failure currently still prevents them. |
| Medium | Future-dated records in the selected local month enter local totals, while Coach excludes dates after today. | Establish an explicit actual-versus-planned policy; forecasts must use actual expenses through the as-of date. |
| Medium | Same-ID inserts replace a row, but rescanning a physical receipt creates a new ID. | Parent/item double counting is avoided; physical receipt duplicate detection is not implemented. Use a reviewable duplicate check, not automatic deletion. |
| Low | Treasure Jars support recorded reservations/releases, targets, optional dates and history, but no weekly/monthly required-contribution calculation. | Extend the existing jar model/UI later; no separate goals service or bank integration needed. Jars remain local-only and can become underfunded when account balances decrease. |

## Reconciliation decision for later stages

The confirmed receipt total remains the single ledger amount used for account balances and total cash flow. Confirmed item/category allocations must sum exactly to it in sen. Explicit tax/discount/rounding allocations and an unallocated remainder must account for differences; never invent product prices. Category reports use either reconciled allocations or the parent's category, never both. Legacy/manual records without allocations continue to use the parent category and amount. Unreadable items remain optional.

## Focused sequence

1. Stage 2: harden receipt validation and unify categorization evidence; test malformed/partial inputs and mixed baskets. Keep the existing OCR and backend extraction.
2. Stage 3: add user-confirmed structured allocations/reconciliation and safe saving; test transaction/account atomicity, repeat submission and manual compatibility. Plan additive schema changes only when needed.
3. Stage 4: introduce shared sen-based totals, period boundaries and category grouping; integrate create/edit/delete/category/date changes with budgets, dashboard and analytics. Address cloud deletion consistency before relying on cloud Coach totals.
4. Stage 5: add deterministic monthly pace, projection and evidence-based contributor/comparison insights. Use a controlled as-of date, no forecasts for future periods, and clear insufficient-history handling. Keep notification thresholds limited.
5. Stage 6: extend the current Coach with calculated budget/goal/comparison evidence, question-specific retrieval, minimal external payloads and useful calculated answers without AI availability. No private client keys.
6. Stage 7: extend Treasure Jar with required weekly/monthly contributions and optional feasibility guidance. Planned amounts never increase actual savings.
7. Stage 8: run regression checks, document limitations, then build/install only after verification.

At each implementation stage, record changed files, decisions, actual test results, limitations and the next step. Do not mix all stages into one rewrite.

## Onboarding remains on hold

An introductory onboarding screen already exists, but not income/favourite-category setup. Recommend a skippable setup after signup. Store expected income separately from received income; a recurring flag alone is not an automatic payment scheduler. Ask for amount, payment day and receiving account, and confirm receipt before increasing balance unless the user explicitly chooses automatic posting. Pin favourite categories while retaining access to all categories. No onboarding changes in this audit.

## Verification and limitations

- Existing Flutter suite: **73 passed** (`flutter test --reporter compact`).
- Existing receipt/Coach backend suite: **36 passed** (`node --test` on both function test files).
- `flutter analyze --no-pub`: completed with exit 1, **0 errors, 4 warnings and 83 informational notices** (87 total). These are the unchanged baseline: unnecessary null comparison in `budget_screen.dart:271`, unused intl import in `home_screen.dart:5`, unused optional onTap parameter in `settings_screen.dart:348`, unnecessary non-null assertion in `dashboard_navigation_test.dart:95`; remaining notices are style/deprecation items. No production source was changed to silence the audit baseline.
- Existing tests cover parser fixtures, malformed AI data, receipt review, account selection, basic budget thresholds, calendar/report totals, jar reservation safeguards and Coach failure responses. They do not prove month-end-second handling, all provider CRUD rollback paths, forecasts or reconciled item allocations.
- No real camera scan, device UI run, live Supabase verification, production deployment or migration was performed. Code findings above are inspection findings, not claims that those failure scenarios were reproduced by the baseline suite.
- Files created in this stage: this audit document. Diagnostic logs: `tmp/stage1-tests.log`, `tmp/stage1-backend-tests.log`, `tmp/stage1-analyze.log`. No application source changed.

Recommended next step: Stage 2 receipt validation/categorization, followed by confirmed reconciliation and safe persistence before budget forecasting or expanded Coach functionality.
