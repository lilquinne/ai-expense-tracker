# Transaction entry, split bills, documents and chart refresh

24 October 2026. Agreed scope: saved participant names/open slots, Evenly or Custom splits, no shares, no app-friend linking, and no separate tax/service-charge fields.

## Entry and layout

- Home + opens manual expense entry immediately. Spendly Coach remains accessible, and a Split bills shortcut is added alongside it.
- Four visible entry modes: Expenses, Income, Transfer and Insert Doc. Expense/income category selection is grouped under main categories; optional subcategory menus include Food, Breakfast, Lunch, Dinner and Snacks. Parent selection works by tapping its icon or label without opening the menu.
- Main category icons use consistent Material symbols with category colours. Custom subcategories remain available under their main category. Income/expense and parent budget grouping retain the existing enum-based calculations.
- The manual Shop field is removed. Manual titles derive from the chosen category, while receipt merchants remain editable. Notes, account selection, dates, recurring controls and receipt-account confirmation remain available. A changed signed-in account requires reopening the transaction form.
- Category grid, amount field, spacing, transaction rows and receipt preview are more compact. No global text scaling override is used.

## Split accounting

- One parent transaction stores the user's own expense amount plus local split metadata containing the bill total, payer and participant allocations. Integer-sen allocations must sum exactly to the bill total. Even splits distribute remainder sen in participant order; Custom requires exact amounts.
- If you pay RM46.50 for two equal portions, your selected account falls by RM46.50, your reported expense is RM23.25 and the other RM23.25 is outstanding. Home displays your own expense, a Split badge and the original total below it.
- If someone else pays, your own portion counts as your expense, with no initial debit to your account. You can subsequently record your repayment from a selected account.
- Split bills shows People owe you and You owe people. All participants remain visible. Open slots can be named later, including an unknown original payer; renamed people can be reused through saved-name search.
- Full/partial repayments require an account and cannot exceed the outstanding portion. They change account balances and settlement history, without adding expense/income ledger rows. Repeating a payment ID is idempotent. Undo reverses it once.
- Bill/account changes and repayments commit in SQLite transactions. A bill with recorded repayments cannot be edited until those repayments are undone. Deleting a split reverses its original cash effect and recorded repayments together. Renaming a participant preserves its ID and allocation.
- The first participant is Me and one participant pays the original bill. Multiple original payers, online collection, shared links, friends/invitations and tax calculations are outside this agreed simple split scope.

## Transfers

- From/to accounts, amount, date and optional note. Both balance changes commit together, using existing asset/liability account semantics. The older separate lending/borrow account type is excluded from these new flows because its legacy balance rules are different. Same-account transfers and missing/foreign accounts are rejected.
- Transfers are stored separately from income/expense totals. Transfer history includes Undo, which reverses both balances atomically and requires both accounts to remain available.
- This records an account movement; it does not initiate a real bank transfer or schedule future payments.

## PDF and receipt capture

- Insert Doc accepts one PDF invoice, 1–10 pages and at most 25 MB. Android PdfRenderer renders each page locally at a maximum dimension of 2400 pixels; existing OCR processes the pages and the combined invoice enters the existing review flow as one expense. Users must confirm the final total, particularly for multi-page documents.
- Imported rendered pages and captured photos are copied to application documents so saved receipts do not depend on a temporary camera file. The saved receipt preview uses the first rendered page. The original PDF is not attached as a separately browsable file.
- Home Scan launches capture directly. Android uses Google ML Kit's full document scanner with page-edge detection, cropping and perspective adjustment. A normal full-quality camera fallback remains available if the scanner cannot start. Gallery import remains available.
- Existing local OCR, optional AI enhancement, field/item corrections and account confirmation remain. Review is required before any transaction is saved.
- Native implementation is Android-specific. Google Play services/document-scanner components may need downloading on first use. Camera quality and detection must be checked on a physical device. PDF import errors are shown rather than inventing extracted values.
- Scanner API reference: https://developers.google.com/ml-kit/vision/doc-scanner/android . The pinned Android dependency is `play-services-mlkit-document-scanner:16.0.0`.

## Spending chart

- Week, Month and Year views, previous/next period navigation, exact-amount touch tooltips and animated period/view transitions. Month uses the actual calendar day count, including February/leap years. Chart padding/height is reduced.

## Storage and compatibility

- Local schema version 10 adds split metadata, saved people, settlement history and transfer history. Verified legacy-account migration includes the new owner-scoped tables. Existing records/balances are not retroactively rewritten.
- Personal transaction amounts and accounts continue using the existing cloud synchronization. Participant identities, split/repayment details and transfer history are currently local-only; cross-device split management is not implemented.
- Zero personal portions remain valid local split records; existing Coach arithmetic already supports zero. No cloud cleanup, backend schema change or production operation was needed. An initially proposed zero-row cleanup was rejected by automatic review and was not executed or retained.

## Verification

- Final full Flutter suite: **127 passed** (`tmp/redesign-delivery-tests.log`).
- Backend receipt/Coach suite: **36 passed** (`tmp/redesign-backend-tests.log`).
- Final full analysis: **0 errors and 4 existing warnings** (`tmp/redesign-delivery-analysis.log`); **137 informational style notices** remain.
- Financial checks cover full cash debit vs own expense, someone-else-paid flows, exact sen/remainders, zero own share, partial/full repayments, retry idempotence, overpayment rejection, settlement undo/deletion, transfer rollback/undo/owner isolation, legacy-account migration, and rejection of unsupported lending-account signs.
- UI checks cover optional parent-category selection, account confirmation, narrow screens, all four entry modes, payer identity after removing another participant, Home split display, and Month chart navigation. Visual preview: `output/manual-entry-preview.png`; desktop test rendering is not a physical-phone screenshot.
- The initial test mock needed the new optional split field. A date-row overflow and a payer-index removal edge case were found and corrected before final passing checks.
- Android native scanner/PDF integration compiled in a successful release-mode testing build. The final frozen-source build also succeeded; details follow.

## Phone acceptance checks

1. Update in place and verify existing accounts, records and jars.
2. Home +: select Food directly, then optionally select Breakfast/Lunch; test Income, notes and date/account selection.
3. Split RM46.50 evenly between Me and another participant. Verify cash -RM46.50, expense RM23.25, outstanding RM23.25. Record RM10, verify outstanding RM13.25 and no new income. Test Undo.
4. Choose another payer and verify the initial bank balance does not change. Record your repayment and check its balance effect. Rename an open slot used as payer.
5. Transfer between two accounts and undo it; income/expense totals must remain unchanged.
6. Scan a real receipt from Home and verify detection/cropping, cancellation and gallery fallback. Import a one-page and a multi-page PDF invoice; review totals and save only once.
7. Browse Week/Month/Year, move periods and tap values. Confirm light/dark themes and readable phone text sizes.

Physical camera/PDF accuracy, OS permission behaviour and live-cloud behaviour remain device acceptance checks. No phone installation was performed during this change.

## Delivery artifact

- APK: `output/android/Spendly-1.1.0-EntryUpdate-24Oct2026.apk`.
- Version **1.1.0**, version code **2**, package `com.example.expense_tracker`.
- Size **98,503,976 bytes** (about 93.9 MiB).
- SHA-256: `496D0BA90438375AB5E93D6E7997A8B3E0C25118B2CAFC0D65726741571DDFD5` (companion `.sha256` file included).
- Frozen-source release-mode build succeeded in approximately 193.5 seconds (`tmp/redesign-ready-build.log`), with build marker `entry-20261024-final-v3`.
- APK Signature Scheme v2 **verified**, using the existing Android Debug test certificate (`tmp/redesign-signature.log`). This is a testing APK, not a store publishing configuration.
- Minimum Android API 24, target API 34; arm64-v8a, armeabi-v7a and x86_64 (`tmp/redesign-package.log`).
- Later targeted analysis of account-switch guards and plain-language error handling found no errors/warnings. Final full checks include those changes and the account-type guard.
- The app was not installed on the phone. Previous APKs were retained.
