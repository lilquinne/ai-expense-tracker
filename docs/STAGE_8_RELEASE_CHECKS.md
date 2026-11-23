# Stage 8 — Android testing build and release checks

24 October 2026.

## Verification

- Full Flutter regression: **115 passed** (`tmp/stage8-tests.log`).
- Receipt extraction and spending Coach backend regression: **36 passed** (`tmp/stage8-backend-tests.log`). These are local test runs, not live service verification.
- Full Dart analysis: **0 errors, 4 existing warnings, 99 informational notices** (`tmp/stage8-analysis.log`).
- Android release-mode testing APK build: **succeeded** (`tmp/stage8-build.log`), approximately 478 seconds. Kotlin incremental compilation encountered cross-drive cache errors and the fallback compiler completed successfully. The build also reported future Kotlin-plugin compatibility and Java/deprecation warnings; these are recorded for maintenance.
- APK signature verification: **Verifies**, APK Signature Scheme v2, one Android Debug signer (`tmp/stage8-apk-signature.log`).
- Package metadata: Spendly, `com.example.expense_tracker`, version `1.0.0` / code `1`, minimum Android API 24, target API 34. Includes arm64-v8a, armeabi-v7a and x86_64 (`tmp/stage8-apk-metadata.log`).

## Testing artifact

- APK: `output/android/Spendly-24Oct2026.apk`
- Size: **97,879,011 bytes** (about 93.3 MiB).
- SHA-256: `22E470443BA9AC238B473EDCB338AC4068734F9887EA2120D61ECB00B3F2706E`
- Checksum file: `output/android/Spendly-24Oct2026.apk.sha256`
- This stage changed documentation and generated build artifacts only. The APK has not been installed on the phone during this stage.

## Phone acceptance checks

Use a test account and small amounts. Existing records should remain available after an update; no data clearing or uninstall is required.

1. Open the app and confirm the expected account, account balances and saved jars.
2. Create, edit and delete a manual expense; verify the account balance and category budget update once each.
3. Scan a real receipt, review merchant/date/total/items, choose the account, save once and verify one transaction. Compare unclear scans with the paper receipt.
4. Check Budget Tracker totals, unbudgeted spending, spending pace and the previous-month comparison. Future-dated entries should appear in recorded views but be excluded from pace evidence.
5. In Coach, ask about remaining budget and jar progress with network access disabled but the cached signed-in session present. Verify local answers. Then reconnect and test a general advice question.
6. View a dated jar and check weekly/monthly alternatives. Merely viewing must not change saved money. Add/release a small amount, reopen the app and verify the reservation/history.
7. Test an offline transaction deletion, reconnect and refresh or prepare Coach; verify the deletion reaches the cloud. Live sync/RLS behavior still requires this check.
8. Test notification permission and budget thresholds on the phone; automated headless tests do not prove OS delivery.

## Known limits

- Android uses the existing development application ID and debug signing key. The generated APK is for testing, not a store publishing configuration.
- No backend deployment, production data change, live Supabase/AI request or phone installation is part of these automated build checks.
- Cloud updates are eventually consistent. Transaction deletion retries are durable from Stage 4 onward, but older cloud-only orphan rows and budget/category/account deletion queues remain unresolved. Cross-device conflict resolution is absent.
- Receipt item categories are not structured budget allocations. A receipt remains one parent expense. Physical duplicate-receipt detection and historical balance repair are absent.
- Forecasts are linear estimates from saved records and exclude future entries. Missing data and irregular bills can affect accuracy. Local Coach supports bounded English question types; general advice and confirmed-plan evaluation still require the online path.
- Jar contributions are estimates, not scheduled transfers or proof of future affordability. Jar data remains local.
- Existing static-analysis warnings/style notices remain. Onboarding changes remain on hold.

## Completion boundary

Automated regression, backend tests and successful APK/signature verification establish a build ready for device acceptance testing. They do not establish that the app has passed camera, OS-notification, live-cloud or phone upgrade checks.
