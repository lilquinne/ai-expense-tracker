# Device sync

The new Android build uses one versioned snapshot per authenticated Supabase user. The deployed database migration is named `versioned_device_sync`; `supabase/device_sync_schema.sql` records its source. The existing relational tables remain available to the spending coach. Do not use older APKs for writes after migrating to snapshot sync.

## First use

1. Update the existing installation on the phone holding the complete records. Do not uninstall or clear app storage.
2. Sign in online and open Settings > Device sync > Sync now. Wait for Up to date.
3. Update the tablet, sign in to the same account, and tap Sync now.
4. Verify expenses, account balances, budgets, jars and history on both devices.

Sync runs after local saves and when the app resumes. Sync now can be used while both apps remain open. This is not a background or real-time synchronization service.

## Safety model

- The server atomically compares snapshot revisions. A stale write is rejected and retried against the new revision.
- Each device stores its last accepted snapshot as a three-way merge baseline. Absence is treated as deletion only for a previously observed record.
- Account cash movements and manual balance adjustments are merged separately. Independent expenses therefore both affect the merged account balance. Jar reservations are similarly derived from portable activity IDs.
- Concurrent edits to the same record stop sync for review. Choosing a full device or cloud copy is explicit. Non-conflicting records merge automatically during normal sync.
- A local SQLite transaction compares the captured local state with the current state before import; saves made during the request are rebased, not overwritten.
- Imports bypass normal transaction-save methods so balances and reservations are not replayed. Receipt paths are retained locally and never copied to a different device.
- The five most recent local copies replaced by sync are retained. The server also retains five previous snapshot revisions. Settings > Save backup exports the current local records and local previous copies as JSON; there is no in-app backup import yet.
- Row-level security restricts both snapshots and snapshot history to `auth.uid()`. Anonymous access is denied. The RPC uses SECURITY INVOKER, not elevated privileges. No service-role key is added to the app.

## Scope

Synced: transactions (including split details), accounts, custom categories, budgets, treasure jars, jar activity, split people, split repayments, and account transfers.

Not synced: receipt image files, device preferences, notification permissions/read status, learned merchant/category hints, authentication credentials, and offline PINs.

The first snapshot imports the previous cloud ledger and merges records already present on the phone. Legacy shared default categories are supplied by the application, not imported as user-owned copies. Empty seeded tablet accounts defer to an existing cloud account. Newly added local jar activity uses UUIDs; existing integer activity IDs receive stable portable IDs during the database upgrade.

Snapshot requests are capped at 20 MB and have a 25-second network timeout. Large ledgers may eventually require incremental sync. Offline failures leave local data intact and expose a retry status.

## Verification

`test/device_sync_test.dart` exercises two simulated devices, cash totals, offline deletes, edit conflicts, jar histories, concurrent local writes, stale revisions and session switches.

`test/device_sync_database_test.dart` verifies atomic SQLite imports, receipt preservation, stable jar history IDs, local backups, record ownership and in-flight edits.

Live database checks use rollback-only temporary users to verify revision rejection, history retention, cross-user isolation and anonymous denial. No real user records are used.
