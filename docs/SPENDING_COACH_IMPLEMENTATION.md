# Spendly Coach implementation

## Status

The app UI is built and `spending-coach` version 1 is ACTIVE in the Spendly project. The user explicitly approved Groq processing of spending summaries and chat on 15 October 2026, and deployment succeeded after that approval. A live request without an authorization header returned HTTP 401. Authenticated end-to-end AI responses still need verification from a signed-in app session; no user credentials were requested or extracted for testing.

## User flow

- Open the sparkle button on Home or Analytics.
- Sign in with an online Spendly account. Legacy local-only accounts cannot call the AI endpoint.
- Before the first question, accept a dialog explaining that questions, recent chat and spending summaries are sent to Groq.
- Ask about spending, income or changes. The selected Analytics month and the preceding five months are available; future transactions are excluded.
- Use Savings plan to confirm the target, number of months, existing saved amount, expected take-home income, total expenses, essential expenses, and extra buffer. Historical salary/expense averages are suggestions and require confirmation. Blank fields are not treated as zero.
- Expand Numbers used to inspect calculated amounts. New chat, leaving the screen, sign-out or account changes clear the in-memory conversation. A pending answer from a previous account is discarded.

The coach never moves money or writes budgets/goals. Current offers and market data are explicitly unavailable in this version. Saved recurring flags are described as recorded activity, not guaranteed future bills.

## Data and security

The app uploads the relevant six-month local transaction range before asking; upload failures stop the request. The backend validates the bearer token with Supabase Auth, rejects anonymous identities, and queries transactions/categories using the caller's JWT plus an explicit verified-owner filter. Existing owner-only row policies remain in effect. No service-role key, new table, or new database grants are used.

Only aggregate monthly/category evidence, confirmed plan estimates, the current question and up to ten recent chat messages reach Groq. Raw merchant titles, receipt notes/images, account IDs and user identity are not included in the evidence. A user may still put personal details in a question. Spendly does not persist chat messages in its database or device storage; provider processing is separate from this in-app retention behavior.

The function shares the existing atomic daily AI allowance with receipt scans (currently thirty requests per user per UTC day). Quota failure blocks the AI request. Body size, history length, amount ranges, pagination, provider output length and timeouts are bounded. Logs do not include financial content, questions, credentials or upstream response bodies.

## Calculations

Amounts are converted to integer minor units before aggregation. Current-month comparisons use the previous month through the same calendar day, not a complete previous month. Historical averages use up to three completed months that contain records; absent months are not automatically zero-spend months. Salary is tracked separately from refunds, gifts and other income.

Remaining goal = max(target - saved, zero).
Monthly saving = remaining / months, rounded up to a cent.
Expected surplus = income - expenses - extra buffer.
Additional gap = max(monthly saving - surplus, zero), or zero if already achieved.
Flexible spending = expenses - essentials.
A plan is feasible under the entered assumptions when the additional gap fits within flexible spending. This is an estimate, not a promise.

AI answers must reference named evidence placeholders for numeric facts. Unknown placeholders, raw digits and unverified URLs trigger a calculated fallback. The model is instructed not to invent amounts in words, compare incomplete months as full months, cut essentials, claim current offers, or recommend investments. Free-form qualitative guidance still requires user judgment.

## Deployment

Deployed `supabase/functions/spending-coach/index.ts`, `handler.mjs` and `coach.mjs` to the existing Spendly project. `verify_jwt = true` is configured, and the handler also verifies the token itself. The endpoint uses the existing GROQ_API_KEY secret without exposing it in the app or chat.

An unauthenticated request was rejected with HTTP 401. Next, test an authenticated question and confirmed plan in the app. Confirm the response uses the intended user's records and the AI answer is grounded. Receipt extraction deployment was not changed.

## Verification

Direct goal suggestions (cloud v4): an unambiguous RM/MYR target and month count in the latest question now produce an exact monthly target and category-based starting suggestions without requiring the form or a provider response. Zero saved is an explicit starting assumption; current recorded net cash flow is not treated as disposable income. Ambiguous goals still need clarification. A newly stated different goal does not reuse an old confirmed plan. Numbered-list prefixes are allowed by the AI numeric validator while ungrounded monetary digits remain rejected. All 23 backend tests pass; live signed-in interaction remains a phone check.

18 October presentation update: category questions return a numbered list of all recorded categories, exact shares and an overall total directly from the ledger calculations (cloud function v3). These successful calculated answers no longer trigger the AI-unavailable banner. Coach text renders bold spans instead of literal markdown markers; provider fallback notices use neutral styling and distinguish calculated records from unavailable AI commentary. Verified with 19 backend tests, 6 Coach Flutter tests, and a signed debug APK build.

On 18 October 2026, live sync failed because categories/accounts used signed PostgreSQL `integer` for Flutter unsigned ARGB values (for example 4281255094). Applied the cloud migration `widen_colour_values_to_bigint` to widen both `color_value` columns to `bigint`, preserving records and ownership policies. Updated the bootstrap schema to match. This server-side fix works with the existing installed APK.

- Backend unit/integration mocks cover exact arithmetic, missing history, future dates, same-day comparison, negative cash flow, cent rounding, essential-expense protection, impossible/achieved goals, owner binding, JWT propagation, pagination, quota rejection, malformed input and provider failure.
- Flutter tests cover bounded request history, malformed/time-out responses, chatting, evidence expansion, clear chat, pending-response isolation on account changes, signed-out access and form validation.
- A live database query under the authenticated role returned zero cross-owner transaction rows. Existing policy definitions use `auth.uid()` ownership in both USING and WITH CHECK.
- Existing quota-table access restrictions are intentional. The advisor notes about the quota SECURITY DEFINER function and table without public read policies predate this feature. The function binds its counter to auth.uid(), accepts no owner argument and denies unauthenticated use. Existing leaked-password protection settings are unchanged.

Remaining checks after deployment: real provider output and latency, phone keyboard/scroll behavior, expired-session recovery, and confirmed empty/partial datasets in a real signed-in session.
