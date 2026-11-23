# Dashboard and Treasure Jar — 21 October 2026

## Implemented

- Home chart switches between a seven-day bar chart and a calendar-year line chart. Both show exact RM amounts on touch. Previous-year navigation is available. Queries use the user's entire local ledger, so week boundaries and yearly totals are not limited by the currently selected month. Completed ledger writes invalidate the chart cache, including backdated entries.
- Recent Transactions → See all opens the existing Records screen.
- Main navigation: Home, Accounts, a larger central Scan action, Analytics, Treasure Jar. Scan opens receipt capture and returns to the previous tab. Manual income and expense entry remain accessible from Home. Spending budgets remain accessible from Treasure Jar's budget icon and Notifications.
- Jars support names, targets, optional dates, source asset accounts, reservations, releases, editing and activity history. Accounts show reserved and available amounts. See TRANSACTION_INTEGRITY.md for the ledger rules and limitations.

## Verification

73 Flutter tests passed, including real SQLite checks for concurrent reservations, release bounds, owner isolation, goal edits preserving savings, protected source accounts, manual transactions, receipt notes, category/calendar/budget reconciliation and chart month/year boundaries. Dashboard widget tests cover narrow-screen navigation, Records access, chart tooltips, Week/Year switching and refreshing earlier-month records. The latter tests were rerun after the final chart invalidation change and passed.

## Onboarding: held for discussion

Recommend a skippable setup after sign-up. Ask whether income is a fixed salary, allowance, variable income or none; then amount, frequency, expected payment date and receiving account. Keep this expected-income profile separate from recorded income. Never add future salary to current balance. Decide with the user whether a scheduled payment should require confirmation of receipt or be posted automatically on its due date; the conservative default is confirmation. Existing records should be checked to avoid creating the same salary twice.

Favourite categories should be pinned first in the expense picker while an All categories option remains available. This setup can be completed or changed later. Neither onboarding flow is implemented in this update.
