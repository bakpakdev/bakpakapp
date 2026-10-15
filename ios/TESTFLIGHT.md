# TestFlight checklist

What the repo already handles and what still needs a human in a dashboard.

## Done in the repo

- Release builds read `API_BASE_URL_RELEASE` (HTTPS only, no localhost fallback) — `Config/SupabaseProject.xcconfig`, `Core/SquareConfig.swift`.
- Automatic signing with team `38BTDK54M3` — `generate_xcode_project.py` (override with `POPUP_DEVELOPMENT_TEAM=...`).
- Release entitlements are selectable via `POPUP_RELEASE_ENTITLEMENTS` (default has none, so Archive always works).
- `ITSAppUsesNonExemptEncryption = NO` in `Info.plist` (HTTPS only → exempt).
- `PrivacyInfo.xcprivacy` bundled (UserDefaults reason CA92.1, collected data types, no tracking).
- Backend deployable with `backend/Dockerfile` / `backend/render.yaml`.
- Square `setup` run-script is the last build phase, and User Script Sandboxing is off
  (Apple rejects Square's nested Frameworks + unsigned `setup` without this). Build number is 2.

## 1. Host the backend

1. Render → New → Blueprint → this repo (`backend/render.yaml`). Any Docker host works too.
2. Set the env vars from `backend/.env.example` in the dashboard. `PUBLIC_BASE_URL`,
   `SQUARE_OAUTH_REDIRECT_URI`, and `SQUARE_WEBHOOK_NOTIFICATION_URL` must use the new HTTPS host,
   and the last two must be registered in the Square developer dashboard.
3. Check `https://<host>/api/health` returns `{"status":"OK"}`.
4. In `ios/Config/Secrets.xcconfig` (or `SupabaseProject.xcconfig`):
   `API_BASE_URL_RELEASE = https:/$()/<host>/api`

## 1b. Supabase auth redirect (one-time, project `mmmiywxemxwyikbysdop`)

Sign-up confirmation and password-reset emails send users to `popup://auth-callback`
(`SUPABASE_AUTH_REDIRECT_URL` in `Config/SupabaseProject.xcconfig`, handled by
`AuthViewModel.handleAuthRedirect`). Supabase silently falls back to the Site URL if the
redirect isn't allowlisted, which looks like "the email link opens a dead localhost page".

Status as of 2026-10-05: `popup://auth-callback` is allowlisted (done via Management API).
Site URL and the other allow-list entry still point at the local server:
`http://127.0.0.1:5001/auth/verified.html` (a bridge page in `backend/public/auth/` that
forwards to the app; also used by the Square OAuth return).

When the backend is hosted, Dashboard → Authentication → URL Configuration:
1. **Site URL** → `https://<host>/auth/verified.html`.
2. **Redirect URLs** → add `https://<host>/auth/verified.html`; keep `popup://auth-callback`.
3. Verify on a device: register with a fresh .edu email, tap the link in the email, and confirm
   the app opens straight to onboarding instead of Safari.

## 2. Apple Developer / App Store Connect (team 38BTDK54M3)

Status as of 2026-10-04: paid membership active, Xcode signed in to team 38BTDK54M3,
`Apple Development` cert present, **no `Apple Distribution` cert yet** (Xcode makes it).

Your to-do when you're ready to ship:
1. App Store Connect → My Apps → **+** → New App: iOS, name `popup`, bundle ID `com.popup.app`,
   SKU `popup-ios`. Xcode will NOT create this for you; without it the upload fails with
   "no suitable application records found". If `com.popup.app` isn't in the bundle-ID dropdown,
   register it first under Certificates, Identifiers & Profiles → Identifiers (explicit App ID).
2. developer.apple.com → Account: accept the latest Program License Agreement if prompted
   (stale agreements block TestFlight uploads). Banking/Tax only matter for paid apps or IAP.
3. Xcode → Product → Archive → Distribute App → TestFlight & App Store. Automatic signing creates
   the distribution certificate and App Store profile on this first run. Do not make them by hand.

Heads-up: 38BTDK54M3 is an **Individual** team. That's fine for TestFlight, App Store, and
Apple Pay, but Apple only grants **Tap to Pay on iPhone** to Organization teams (needs a
D-U-N-S number / legal entity). Ship with the default `PopupApp.entitlements` until that's sorted.

## 3. Payments (sandbox on Render — do this before TestFlight pay smoke)

Live API host: `https://popup-api-hwbg.onrender.com`

### 3a. Render environment (copy from local `backend/.env`)

In Render → `popup-api-hwbg` → Environment, set:

| Key | Value |
|---|---|
| `SQUARE_ENVIRONMENT` | `sandbox` |
| `SQUARE_APPLICATION_ID` | from local `.env` |
| `SQUARE_APPLICATION_SECRET` | from local `.env` |
| `SQUARE_ACCESS_TOKEN` | from local `.env` |
| `SQUARE_LOCATION_ID` | from local `.env` |
| `PUBLIC_BASE_URL` | `https://popup-api-hwbg.onrender.com` |
| `SQUARE_OAUTH_REDIRECT_URI` | `https://popup-api-hwbg.onrender.com/api/payments/square/oauth/callback` |
| `SQUARE_WEBHOOK_NOTIFICATION_URL` | `https://popup-api-hwbg.onrender.com/api/payments/square/webhook` |
| `SQUARE_WEBHOOK_SIGNATURE_KEY` | from Square webhook (after 3b) |

Redeploy, then open `https://popup-api-hwbg.onrender.com/api/payments/health`.
Expect `squareConfigured: true`, `squareCanTakePayments: true`, and `publicBaseUrl` = the hwbg host.
`missingSquareEnv` should be `[]`.

### 3b. Square Developer Dashboard (sandbox app)

1. OAuth → Redirect URL:  
   `https://popup-api-hwbg.onrender.com/api/payments/square/oauth/callback`
2. Webhooks → `payment.created` + `payment.updated` →  
   `https://popup-api-hwbg.onrender.com/api/payments/square/webhook`  
   Paste the signature key into Render `SQUARE_WEBHOOK_SIGNATURE_KEY`.

### 3c. Smoke test (card entry; Apple Pay optional)

1. iOS Secrets already has `API_BASE_URL_RELEASE` → hwbg `/api` and sandbox `SQUARE_APPLICATION_ID`.
2. Buyer meetup pay → **Pay with card** → Square sandbox test card.
3. Expect charge `COMPLETED`, listing sold, seller wallet credited.
4. Cash out is **ledger-only** for now (wallet reserved; no bank push yet).

Apple Pay (buyer meetup Pay — enabled for TestFlight)
1. Identifiers → Merchant IDs → `merchant.com.popup.app`.
2. App ID `com.popup.app` → enable Apple Pay → select that merchant.
3. Square dashboard → Apple Pay → upload the payment processing certificate for that merchant.
4. Config already set: `APPLE_PAY_MERCHANT_ID = merchant.com.popup.app` and
   `POPUP_RELEASE_ENTITLEMENTS = PopupApp.ApplePay.entitlements`.
5. Archive a new build (bump `CURRENT_PROJECT_VERSION`) and upload to TestFlight.
6. On device (two accounts / two devices): seller meetup → **Receive** (waiting session) →
   buyer meetup → **Pay** → Apple Pay only unlocks while the seller session is active.
7. Seller balance credits after Square confirm; session marks `paid` in realtime.

Tap to Pay on iPhone — **paused until LLC / Organization team** (not used for Receive now)
- Full flip-on checklist for a post-launch update: **`ios/POST_LAUNCH_TAP_TO_PAY.md`**
- Leave `TAP_TO_PAY_ENABLED = NO` and Release on `PopupApp.ApplePay.entitlements` until then.
- Code + `PopupApp.Payments.entitlements` are already in the repo; after Apple approves Tap to Pay,
  it’s a config flip + new Archive (not a rewrite).

How money reaches the seller balance
1. Seller taps **Receive** → backend creates `payment_sessions` (waiting) + `payment_requests`.
2. Buyer Apple Pay unlocks only while that session is active (server-gated).
3. Buyer completes Apple Pay; app confirms with Square nonce (amount from DB; idempotent).
4. Backend marks the listing sold, session paid, and credits `seller_balances.available_cents`.
5. Cash out later reserves that wallet (ledger); bank push ships separately.

Square production
- Swap `SQUARE_APPLICATION_ID` to the `sq0idp-...` production app ID and the backend
  `SQUARE_ENVIRONMENT=production` + production tokens before real money moves.
  Also switch scanner `OPENAI_MODEL=openai-sol` on Render when you go live.

## 4. Archive and upload

```sh
cd ios && python3 generate_xcode_project.py && open PopupApp.xcodeproj
```

Xcode: scheme `PopupApp`, destination "Any iOS Device (arm64)" → Product → Archive →
Distribute App → TestFlight & App Store. Bump `CURRENT_PROJECT_VERSION` in
`generate_xcode_project.py` for every upload (App Store Connect rejects duplicate build numbers).
Clean (Shift+Cmd+K) before this Archive if Apple just rejected a Square nested-bundle / unsigned
`setup` upload — the last-phase Square SDK setup script must have run on that archive.

## Known caveats

- `MockReaderUI` (Square's simulated reader) is linked in all configurations. It is only used
  when the Square app ID is a sandbox ID; drop it from `generate_xcode_project.py` before App
  Store review if Square flags it.
- Square sandbox IDs work on TestFlight but only move test money.
