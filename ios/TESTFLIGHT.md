# TestFlight checklist

What the repo already handles and what still needs a human in a dashboard.

## Done in the repo

- Release builds read `API_BASE_URL_RELEASE` (HTTPS only, no localhost fallback) — `Config/SupabaseProject.xcconfig`, `Core/SquareConfig.swift`.
- Automatic signing with team `38BTDK54M3` — `generate_xcode_project.py` (override with `POPUP_DEVELOPMENT_TEAM=...`).
- Release entitlements are selectable via `POPUP_RELEASE_ENTITLEMENTS` (default has none, so Archive always works).
- `ITSAppUsesNonExemptEncryption = NO` in `Info.plist` (HTTPS only → exempt).
- `PrivacyInfo.xcprivacy` bundled (UserDefaults reason CA92.1, collected data types, no tracking).
- Backend deployable with `backend/Dockerfile` / `backend/render.yaml`.

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

## 3. Payments (can come after the first TestFlight build)

Apple Pay
1. Identifiers → Merchant IDs → `merchant.com.popup.app`.
2. App ID `com.popup.app` → enable Apple Pay → select that merchant.
3. Square dashboard → Apple Pay → upload the payment processing certificate for that merchant.
4. `Secrets.xcconfig`: `APPLE_PAY_MERCHANT_ID = merchant.com.popup.app`
   and `POPUP_RELEASE_ENTITLEMENTS = PopupApp.ApplePay.entitlements`.

Tap to Pay on iPhone (sellers collecting in person)
1. Request the entitlement: developer.apple.com → Account → "Tap to Pay on iPhone Entitlement".
   Requires an Organization (not Individual) team; approval takes days to weeks.
2. After approval, add the capability to the App ID and set
   `POPUP_RELEASE_ENTITLEMENTS = PopupApp.Payments.entitlements`.

Square production
- Swap `SQUARE_APPLICATION_ID` to the `sq0idp-...` production app ID and the backend
  `SQUARE_ENVIRONMENT=production` + production tokens before real money moves.

## 4. Archive and upload

```sh
cd ios && python3 generate_xcode_project.py && open PopupApp.xcodeproj
```

Xcode: scheme `PopupApp`, destination "Any iOS Device (arm64)" → Product → Archive →
Distribute App → TestFlight & App Store. Bump `CURRENT_PROJECT_VERSION` in
`generate_xcode_project.py` for every upload (App Store Connect rejects duplicate build numbers).

## Known caveats

- `MockReaderUI` (Square's simulated reader) is linked in all configurations. It is only used
  when the Square app ID is a sandbox ID; drop it from `generate_xcode_project.py` before App
  Store review if Square flags it.
- Square sandbox IDs work on TestFlight but only move test money.
