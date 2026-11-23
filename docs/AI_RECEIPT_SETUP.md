# Enable AI receipt extraction with Groq

The Flutter integration and Supabase function are included. Cloud extraction needs
a Groq API key and deployment to your Supabase project before it works.
Until then, the scan screen shows the existing local parser results.

## 1. Configure the secret

Create an account at https://console.groq.com/ and stay on the **Free** plan.
Open **API Keys** (https://console.groq.com/keys) and create a key for this app.
Do not upgrade to the paid Developer plan if your goal is no inference charges.
In your Supabase project's **Edge Functions → Secrets**, add:

- `GROQ_API_KEY`: your private Groq API key.

The backend uses `openai/gpt-oss-20b` hosted by Groq. The `openai/` prefix is part
of the model name; requests go only to `api.groq.com`, not the OpenAI API.
There is no paid-provider fallback. The API cannot force an account onto a free
plan: verify the Groq account owning the key is on Free before enabling scans.

If you followed the previous OpenAI setup, replace the function deployment with
this version. `OPENAI_API_KEY` and `OPENAI_RECEIPT_MODEL` are no longer read.
Remove those secrets if they are not used by another function. Keep the same
Supabase URL, publishable key, and existing quota table.

Do not put the key in Flutter, source control, transaction notes, or chat.
The function also uses Supabase's built-in `SUPABASE_URL` and `SUPABASE_ANON_KEY`.

## 2. Add the usage counter

Open the Supabase SQL Editor for the same project configured in
`lib/config/supabase_config.dart`. Run the contents of
`supabase/migrations/202610090001_receipt_scan_quota.sql`.

Open that local file, copy all its SQL code, paste it into a new query in the
Supabase SQL Editor, then click **Run**. Do not paste the file path into the editor.
If you already ran this migration for the OpenAI version, skip this step.

This adds an atomic limit of 30 attempts per user per UTC day. Failed AI calls
after quota reservation also count. Users cannot read or edit the counters directly.
The function fails closed if the quota migration is missing.

## 3. Deploy the function

With the Supabase CLI installed, run from the project root:

```powershell
supabase login
supabase functions deploy extract-receipt --project-ref YOUR_PROJECT_REF
```

Replace `YOUR_PROJECT_REF` with the project reference from your Supabase dashboard.
The checked-in function configuration disables gateway legacy JWT verification:
the handler instead verifies the user's bearer token through Supabase Auth's
`/auth/v1/user` endpoint before reserving quota or making a Groq API request.
Keep that verification in place. A publishable key alone cannot authorize a scan.

Alternatively, create `extract-receipt` in the dashboard editor and upload the
three source files `index.ts`, `handler.mjs`, and `receipt.mjs`. Disable the
gateway's legacy JWT verification for this function, retaining the handler's
own authentication. Do not upload `receipt.test.mjs` as the entry point.

## 4. Try it in the app

1. Sign in with a real Supabase account; local-only login cannot use the API.
2. Open Scan Receipt. AI extraction runs automatically when signed in, with local fallback.
3. Scan a receipt. Only OCR text is sent, not the photo.
4. Review the **Receipt details** summary. A sign-in button
   appears when an online account is needed.
5. Use **Edit receipt details** to correct shop, items, quantity, unit price,
   line total, currency, receipt number, payment, date/time, or category.
6. Continue to Add Transaction, confirm the paying account, and review before saving. Missing dates use the
   existing transaction form's default date, so check it when the receipt has none.

This first version uses the built-in expense categories. New receipt notes contain
only a numbered list of readable item names and available line prices. Notes show
a three-line preview with Show more / Show less in transaction details. Existing
notes are preserved. The receipt image remains attached; raw OCR is available
during scan review but is no longer copied into new notes. It does not yet
create a separate receipt-item database or split one receipt into transactions.
Foreign-currency receipts are not converted automatically: when the detected
currency differs from the app currency, the transaction amount is left blank.

The main preview shows category, shop, total, date and payment method. Expand
**Receipt details** for the invoice number and items. **Home appliances** includes
household supplies such as wet tissues, following this app's category preference.
The Ninso wet kitchen towel description is displayed as **Ninso Wet Tissue**;
the original wording remains available during OCR review and in the receipt image.

For blurry receipts, extraction prioritizes the shop header, final total and
category. Readable grocery words can suggest a category even without matched
prices. Unreadable items can be omitted; unknown prices remain missing. The local
parser tolerates common total-label OCR substitutions but never substitutes cash,
change or subtotal for a missing total.

MYDEBIT is recognized as **Debit card / bank**. One matching Spendly bank account
can be suggested; multiple matching accounts or an unknown payment require a
selection. The receipt cannot identify a specific bank from MYDEBIT alone.
Saving records the expense against the selected account and updates its Spendly
balance; it does not move money through a real bank. Scanning alone changes no balance.

After updating this receipt flow, rebuild/install the updated phone app and
redeploy **extract-receipt** with all three source files from step 3. Both the app
and backend now support the new category. No additional SQL migration is needed
for this change. Local text/widget tests do not verify live device OCR or Groq output.

Use **Edit receipt details** for corrections. Dates use DD-MM-YYYY with a calendar; time is not required. Known shop names are normalized, and saved shop corrections are remembered per user on this device. New notes filter receipt headings and total lines. From Account → + Add opens the existing Add Account page.

## Validation and costs

Input is limited to 20,000 characters/64 KB, output to 100 items and a 4,000-token
completion budget (including reasoning). Reasoning effort is set to low.
The backend checks the schema, dates, categories and amounts. Arithmetic mismatches
produce review messages rather than overwriting the receipt total. Missing fields
stay null. Model output can still be wrong; always review before saving.

Groq's free plan has request and token limits shared by all users of your backend
key; these are separate from the app's 30-attempt per-user limit. Long receipts
can exceed the provider token limits even when the app accepts their size.
Rate limits, timeouts, invalid output, or truncated responses use the local parser,
without automatic retries or a switch to a paid provider. A limit message means
you can continue locally or try again after the provider's quota window resets.

Free-plan availability and limits are controlled by Groq, not by this code.
Supabase hosting quotas/billing are separate. Receipt content is not logged by
this function. Review Groq's data controls before processing sensitive receipts.

Run local checks:

```powershell
flutter test
flutter analyze --no-pub
node --test supabase/functions/extract-receipt/receipt.test.mjs
```

Before launch, verify real scans on a device with your deployed function, including
signed-out access, expired sessions, quota exhaustion, offline fallback, long
receipts, mixed baskets and Malay/English receipts. The SQL migration and live
provider integration require your Supabase project and API credentials to verify.

References:
- https://console.groq.com/docs/structured-outputs
- https://console.groq.com/docs/rate-limits
- https://console.groq.com/docs/your-data
- https://supabase.com/docs/guides/functions/secrets
- https://supabase.com/docs/reference/javascript/auth-getuser

