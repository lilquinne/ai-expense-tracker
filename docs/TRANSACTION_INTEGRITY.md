# Spending and reservation rules

## Current receipt model

A receipt is one `TransactionModel` and one `transactions` row, using its confirmed grand total and chosen category. Item names/prices are explanatory notes only. Never parse notes back into additional ledger expenses. The receipt save screen makes one `addTransaction` call and rejects a second submission while saving.

Manual transactions use the same ledger without requiring a receipt, note or item data. Charts, category breakdowns, budgets, calendar, reports and Coach calculate spending from parent transaction amounts. A repeated save of the same transaction ID replaces that row; different transaction IDs remain distinct. Re-scanning a physical receipt is not automatically deduplicated by this change.

## Item categorisation

Item-level category allocation is not enabled. The parent category receives the entire confirmed total, even if OCR item prices are missing or inconsistent. This is deliberate: OCR notes must not change spending totals.

If allocations are introduced later, store them as non-ledger child allocations, in integer cents. For each expense, the sum of allocations must equal the confirmed parent amount, including discounts, tax and rounding. Any unresolved difference belongs to an explicit unallocated remainder. Category analytics would read either validated allocations OR the parent category, never both. Cash flow/account balances always use the parent once. Never estimate allocations from free-form notes without confirmation, and preserve the parent-only fallback for existing/manual records.

## Treasure Jar

Jars earmark an existing asset account's money. Reservation changes use a SQLite transaction and integer cents. They change neither the account balance nor the income/expense ledger. Available money equals the account balance minus all its jar reservations. Concurrent additions cannot exceed that amount. Releases cannot exceed the jar balance. Spending outside a jar can leave reservations underfunded; the jar shows that condition instead of fabricating money or blocking the recording of a real expense.

Every jar and activity entry is user-scoped. Funded jars cannot change accounts or be deleted until released. Source accounts cannot be deleted while jars reference them. Jar edits preserve saved amounts. Local schema version 8 adds jars/history without modifying transaction rows. Verified legacy profile import carries jars/history along with their source accounts.

Jars are currently stored on this device and are not included in cloud sync or Coach goal context. No real bank transfer is performed. Onboarding income and favourite categories remain on hold pending discussion; income forecasts must remain separate from received income in the ledger.
