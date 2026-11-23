# Spendly online accounts — setup and where to see users

Project: **Spendly Expense Tracker** (`afpsinydrrvzhzvmkfrl`).
This is the project used by the app. There is another project named Spendly; do not configure that one for this build.

## Already deployed on 13 October 2026

- Owner-only access to profiles, transactions, accounts, categories, budgets and receipts.
- A server trigger creates `public.app_users` when a Supabase Auth user registers.
- Legacy cloud PIN column removed. New passwords are handled by Supabase Auth, never by the profile table or local user table.
- Updated `extract-receipt` version 3. Its handler validates the user's session before quota/Groq requests.
- Database isolation checked using two temporary test users and a rollback; no test users remain.

The app code now supports email/password signup/sign-in, confirmation resend, password reset, and Google OAuth. Google is not enabled until you complete the provider setup below. Real signup/email delivery and Google login still require a phone test.

## 1. Allow the phone to receive sign-in links

1. Open https://supabase.com/dashboard/project/afpsinydrrvzhzvmkfrl/auth/url-configuration
2. Under **Redirect URLs**, add exactly:
   `com.spendly.app://auth-callback/`
3. Save. This callback is already registered in the Android and iOS app code.

## 2. Email ID and password

Email signup and email confirmation are currently enabled on your project.

1. In Supabase, open **Authentication → Sign In / Providers → Email** and keep email confirmation enabled.
2. Configure **Authentication → Email / SMTP Settings** with an email provider for use beyond your Supabase project team. Supabase's default sender is restricted and rate-limited; do not assume it sends to arbitrary new users. See https://supabase.com/docs/guides/auth/auth-smtp
3. In the updated app choose **New here? Sign up**, enter your name, email ID and a password of at least 8 characters.
4. Open the confirmation email on the same phone, confirm, then return to Spendly. If the app does not reopen, return manually and sign in.
5. If an offline account on this phone uses the same email, Spendly offers to move its records after you enter its existing PIN. No records are attached based on matching email alone. Choose Keep separate to leave them in the offline account.

## 3. Create Google OAuth credentials

This implementation uses browser-based Google OAuth through Supabase, so create a **Web application** OAuth client, even though Spendly is an Android app.

1. Open https://console.cloud.google.com/ and create/select a Google Cloud project for Spendly.
2. Open **Google Auth Platform → Branding** (older menus may call this OAuth consent screen). Enter app name Spendly and your support/contact email.
3. Under **Audience**, choose External if you are using a personal Gmail account. While testing, add your own Gmail address as a test user.
4. Under **Data Access**, use only `openid`, `email`, and `profile` scopes. Spendly does not need Gmail inbox access.
5. Under **Clients**, choose **Create client → Web application** and name it Spendly Supabase.
6. Add this **Authorized redirect URI**:
   `https://afpsinydrrvzhzvmkfrl.supabase.co/auth/v1/callback`
7. Create the client. Copy the client ID and client secret directly into Supabase in the next section. Do not paste the secret into chat or the Flutter app.

## 4. Enable Google in Supabase

1. Open https://supabase.com/dashboard/project/afpsinydrrvzhzvmkfrl/auth/providers
2. Open **Google**, enable the provider, and enter the Google client ID and secret.
3. Keep normal nonce checking enabled. Save.
4. Confirm the app redirect in section 1 is saved.
5. In Spendly, tap **Continue with Google**, choose your Gmail account and approve Google's sign-in prompt.

Google verifies your Google account/email during sign-in. There is no separate Gmail inbox code in this flow, and Spendly does not read your mail.

Official guide: https://supabase.com/docs/guides/auth/social-login/auth-google
Mobile redirect guide: https://supabase.com/docs/guides/auth/native-mobile-deep-linking?platform=flutter

## 5. Where to see user data

- **Online login accounts and email confirmation:** https://supabase.com/dashboard/project/afpsinydrrvzhzvmkfrl/auth/users
- **Profiles and uploaded app records:** https://supabase.com/dashboard/project/afpsinydrrvzhzvmkfrl/editor
  - `app_users`: ID, name, email, creation and login timestamps.
  - `transactions`: uploaded expenses and income.
  - `accounts`, `budgets`, `categories`: uploaded app records.
  - `receipt_scan_usage`: daily AI scan counts.
- A profile's `id` matches its Auth user's UUID. Other tables use that value in `user_id`.
- Old `SP-...` rows are legacy prototype profiles, not new authenticated accounts. They remain for admin reference, but clients cannot claim them.
- The database is prepared, but your actual phone records upload only after online sign-in and, for old records, the optional PIN-verified move.
- This is an upload/backup path. Downloading and merging records onto a second device is not implemented in this change. Receipt image files remain on the phone; a stored path does not upload the image.

## 6. Install and test

Install the new app over the existing installation; do not uninstall it first, because that can erase local data.

Sign up using the same email as the old offline account if you want the import prompt. Confirm the email, sign in, import records using the old PIN, and check the tables above. Then scan the Bataras receipt and check for **AI receipt details**.

The local parser now repairs the specific `(ER) ATARAS` header and tolerates decimal spacing. If shop or total is missing, it retries OCR locally with a higher-contrast image. It does not hardcode RM46.50. Truly unreadable fields still need manual review.
