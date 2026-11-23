# Stage 4 — Shared totals, complete months and transaction sync retries

24 October 2026.

## Implementation

- Added `LedgerTotals`: amounts are rounded per entry to integer sen before aggregation. Provider income/expense/category/daily totals, database statistics, budget alerts, monthly calendar/reports and category transaction analysis use these rules. The existing dashboard chart already sums integer sen.
- Month queries use an inclusive first day and exclusive first day of the following month. This includes the last second/microsecond of every month and budgets saved later on the last day.
- Budget overview subtracts only expenses in budgeted parent categories, and separately displays unbudgeted spending. Category percentages are uncapped; progress bars remain capped. Zero-limit usage is explicit.
- Parent category budgets use the transaction's parent enum. Analytics retains custom-category detail within that parent, without allocating the same transaction twice. Manual and legacy entries retain their parent fallback. Item allocations remain deferred.
- Recorded reports continue to include all saved entries in the selected month, including future-dated entries. These are recorded cash-flow views; Stage 5 forecasts must filter actual evidence through an explicit as-of date.
- Local schema version 9 adds `pending_transaction_deletes` without rewriting existing transactions/balances. Confirmed deletion and its owner-scoped retry marker commit with the balance reversal. Failed deletion rolls all three back. Recreating the same ID clears its marker in the same transaction.
- Transaction uploads serialize and read fresh local records when each queued job starts, ignoring stale caller snapshots. Uploads use batches of 500. Pending deletes run first with explicit ID and owner filters and survive failures/restarts. Markers are retained for idempotent replay; this intentionally trades repeated deletion requests for durability.
- Coach uses the same serialized transaction sync and propagates a sync failure before requesting an answer. Background failures remain nonfatal to a successful local save. Retries happen on subsequent data loads/syncs or Coach preparation; there is no new background scheduler.

## Verification

- Full clean Flutter regression: **96 passed** (`tmp/stage4-verified-tests.log`), including the new month-boundary, budget totals, SQLite rollback/retry and mocked cloud synchronization checks.
- Completed full analysis during implementation: **0 errors, 4 existing warnings, 83 informational notices** (`tmp/stage4-analysis-final.log`).
- Final targeted analysis of shared totals, monthly analysis, alerts, cloud sync and new tests: **0 errors, 0 warnings, 2 style notices** (`tmp/stage4-targeted-analysis.log`). A final full-analysis retry stalled; its incomplete log is not counted as a pass.
- Initial test startup required SDK-cache access. Superseded compilers stalled and were restarted only after verifying their exact process identities; the final suite used one worker. Earlier cloud-test failures came from the injected session check and missing request metadata in mock responses; both test setup problems were corrected before the successful 96-test run.
- Notification plugin messages in headless tests are expected safe fallbacks, not device notification verification.

## Limits

No live Supabase query, phone camera/UI test, APK installation, production schema change or deployment was performed. Mock HTTP tests verify request behavior, not deployed RLS/network behavior. Supabase deletion follows the documented filtered-delete API: https://supabase.com/docs/reference/dart/delete . The changelog markdown endpoint could not be read by the web tool.

Cloud writes remain eventually consistent, not a distributed transaction with SQLite. A local change during an in-flight upload converges on the next queued sync; cross-device conflict resolution is not implemented. Historical cloud rows deleted before retry markers existed are not automatically repaired. Budget/category/account cloud deletion queues remain outside this transaction-ledger change. Persistent transaction markers can grow over time; compaction requires a separate synchronization acknowledgement design.

Onboarding and item-level category allocations remain deferred.

## Next

Stage 5: deterministic monthly pace, projection and purchase/category comparisons with as-of dates and insufficient-history handling. Verify live cloud behavior and device flows before release.
