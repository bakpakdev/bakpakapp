# TestFlight checklist

What the repo already handles, and what still needs you in a dashboard. Payments run on
**Stripe Connect Express** (buyer checkout + seller payouts). Square is only used by the paused
Tap to Pay prototype and is not linked into the app (see `POST_LAUNCH_TAP_TO_PAY.md`).

## Done in the repo

- Release builds read `API_BASE_URL_RELEASE` (HTTPS only, no localhost fallback):
  `Config/SupabaseProject.xcconfig`, `Core/PaymentsConfig.swift`. Currently
  `https://popup-api-hwbg.onrender.com/api`.
- Automatic signing with team `38BTDK54M3` (`generate_xcode_project.py`; override with
  `POPUP_DEVELOPMENT_TEAM=...`).
- Release entitlements come from `POPUP_RELEASE_ENTITLEMENTS` (currently
  `PopupApp.ApplePay.entitlements`). `PopupApp.entitlements` has no entitlements at all, as a
  fallback that always archives.
- Only the permissions the app uses: camera and photo library. No Bluetooth, NFC, location or
  background modes.
- `ITSAppUsesNonExemptEncryption = NO` in `Info.plist` (HTTPS only, so exempt).
- `PrivacyInfo.xcprivacy` bundled: email, name, user ID, photos, user content and purchase
  history, all linked to the user, none used for tracking.
- Terms of Service and Privacy Policy are served by the API at `/legal/terms.html` and
  `/legal/privacy.html`, and linked from sign-in, signup and Help.
- Password reset and campus email confirm both email a landing page on the API host, so iOS Mail
  prefetch can't burn the link.
- The debug demo signup (`demo@popupdev.test`) is compiled out of Release, and the API refuses it
  when `NODE_ENV=production`.
- Backend deploys from `backend/Dockerfile` with `backend/render.yaml` (auto-deploy on push).

## 1. Hosted API (Render, `popup-api-hwbg`)

Set these in Render → Environment (the full list with comments is in `backend/render.yaml`):

| Key | Value |
|---|---|
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | Supabase project `mmmiywxemxwyikbysdop` |
| `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY` | `sk_test_…` / `pk_test_…` until launch |
| `STRIPE_WEBHOOK_SECRET` | signing secret of the platform webhook (step 2) |
| `STRIPE_CONNECT_WEBHOOK_SECRET` | signing secret of the Connected-accounts webhook (step 2) |
| `PUBLIC_BASE_URL` | `https://popup-api-hwbg.onrender.com` |
| `RESEND_API_KEY`, `RESEND_FROM` | email confirm + password reset mail |
| `OPENAI_API_KEY` | Sell tab clothing scanner |

Check after each deploy:

- `https://popup-api-hwbg.onrender.com/api/health` → `{"status":"OK"}`
- `https://popup-api-hwbg.onrender.com/api/payments/health` → `stripeConfigured: true`,
  `stripeEnvironment: "test"`, `missingStripeEnv: []`
- `https://popup-api-hwbg.onrender.com/legal/privacy.html` loads

## 2. Stripe (test mode until launch)

1. Connect → settings: Express accounts on, platform branding set (sellers see it in onboarding).
2. Developers → Webhooks → **two** endpoints, both at
   `https://popup-api-hwbg.onrender.com/api/payments/webhook`:
   - **Your account**: `payment_intent.succeeded`, `payment_intent.payment_failed`,
     `charge.refunded`, `charge.dispute.created`, `transfer.reversed` → `STRIPE_WEBHOOK_SECRET`
   - **Connected accounts**: `account.updated` → `STRIPE_CONNECT_WEBHOOK_SECRET` (moves a seller's
     popup balance to Stripe once they finish onboarding)
3. Settings → Payment methods → Apple Pay: register the domain / upload the Apple Pay certificate
   for `merchant.com.popup.app` (Stripe's Apple Pay guide walks through the CSR).
4. Local development: `backend/scripts/stripe-webhook-local.sh` writes a `whsec_…` for the CLI.

Fees: buyers pay the listed price + `PLATFORM_FEE_PERCENT` (8%) + `PLATFORM_FEE_FIXED_CENTS`
(30¢). Sellers receive the listed price.

## 3. Supabase (project `mmmiywxemxwyikbysdop`)

1. SQL Editor: run any `supabase/migrate_*.sql` not applied yet. Latest:
   `migrate_profile_privacy.sql` (Settings → Privacy switches stay hidden until it runs).
2. Authentication → URL Configuration:
   - **Site URL** → `https://popup-api-hwbg.onrender.com/auth/verified.html`
   - **Redirect URLs** → keep `popup://auth-callback`, add
     `https://popup-api-hwbg.onrender.com/auth/verified.html`

## 4. Apple Developer / App Store Connect (team 38BTDK54M3)

1. Identifiers → Merchant IDs → `merchant.com.popup.app`; App ID `com.popup.app` → Apple Pay on,
   that merchant selected.
2. App Store Connect → My Apps → `popup` (bundle `com.popup.app`, SKU `popup-ios`). Xcode won't
   create the app record for you.
3. App Information → **Privacy Policy URL**: `https://popup-api-hwbg.onrender.com/legal/privacy.html`.
4. App Privacy questionnaire: match `PrivacyInfo.xcprivacy` (no tracking, no location).
5. Accept the latest Program License Agreement if prompted (stale agreements block uploads).

Heads-up: 38BTDK54M3 is an **Individual** team. That's fine for TestFlight, the App Store and
Apple Pay. Tap to Pay on iPhone needs an Organization team (see `POST_LAUNCH_TAP_TO_PAY.md`).

## 5. Archive and upload

```sh
cd ios && python3 generate_xcode_project.py && open PopupApp.xcodeproj
```

1. Bump `CURRENT_PROJECT_VERSION` in `generate_xcode_project.py` (App Store Connect rejects a
   repeated build number), then regenerate. Help → footer shows "popup for iOS 1.0 (N)" so testers
   can report which build they're on.
2. Scheme `PopupApp`, destination "Any iOS Device (arm64)" → Product → Archive → Distribute App →
   TestFlight & App Store. Automatic signing makes the distribution certificate and profile on the
   first run.

## 6. Smoke test on two phones (TestFlight build)

1. Seller lists an item; buyer finds it and sends a meetup request; seller accepts.
2. Both open the meetup → seller **Receive**, buyer **Pay** (unlocks once the seller is waiting).
3. Buyer pays with Apple Pay (Stripe test mode accepts real cards without charging them) and
   sees price + service fee.
4. Seller sees "added to your earnings"; the listing moves to Sold.
5. Seller turns on 2FA, then Settings → Cash out setup → finishes Stripe onboarding; the balance
   moves to their Stripe account.
6. Sign out → **Forgot password?** → open the email on the phone → set a new password.

## Going live

- Swap Render to `sk_live_…` / `pk_live_…`, create live-mode webhooks (new signing secrets), and
  redo the Apple Pay certificate in live mode.
- Point `RESEND_FROM` at a verified domain.
