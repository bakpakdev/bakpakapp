# Post-launch update: Tap to Pay on iPhone (seller Receive)

> **Payments moved to Stripe (Oct 2026).** Buyer checkout and seller payouts now run on
> Stripe Connect Express, so money taken with this Square Tap to Pay prototype would land in
> Square where popup can't pay it out. Before turning Tap to Pay on, rebuild it on Stripe
> Terminal's Tap to Pay on iPhone (StripeTerminal SDK) so it charges popup's Stripe account
> like the buyer checkout does. The steps below describe the old Square version.

**Status:** Paused until Popup has an **LLC / Organization** Apple Developer team.  
In-person pay ships today as **seller Receive session + buyer Apple Pay** (no Tap to Pay).  
Tap to Pay remains an optional later Receive path once Apple grants the entitlement.

Use this checklist when you’re ready to ship Tap to Pay as an app update.

---

## Why it’s paused

- Apple’s **Tap to Pay on iPhone** entitlement requires an Organization developer account (LLC, Inc., etc.), not Individual.
- Without that entitlement, calling Square’s reader APIs freezes or fails on device.
- Keep `TAP_TO_PAY_ENABLED = NO`. Receive already works via `payment_sessions` + buyer Apple Pay.

---

## Already built (do not rewrite)

| Piece | Where |
|--------|--------|
| Tap to Pay collector + timeouts + settle delay | `BakpakApp/Core/TapToPayCollector.swift` |
| Setup blocker when not entitled | `SquareConfig.tapToPayBlocker` / `TapToPayCollector.setupBlocker` |
| Seller Receive UI → payment flow | `MeetupPayFlowView`, `MeetupDetailView`, `MeetupCard` (Pay / Receive) |
| Listing “Collect payment” / Receive sheet | `ProductDetailView` |
| Backend charge + credit `seller_balances` | `backend/routes/payments.js` → `meetupFulfill.js` → `sellerBalance.js` |
| Entitlements file (Apple Pay + Tap to Pay) | `BakpakApp/PopupApp.Payments.entitlements` |
| Feature flag in Info.plist | `TAP_TO_PAY_ENABLED` ← `$(TAP_TO_PAY_ENABLED)` in xcconfig |

Money path after a successful Tap to Pay (or buyer Apple Pay/card):

1. Create `payment_requests`  
2. Square charge completes  
3. `POST /payments/meetup/:id/confirm`  
4. Listing marked sold + `seller_balances.available_cents` credited  

---

## Flip-on checklist (after LLC + Apple approval)

### A. Apple Developer (Organization team)

1. Move / enroll App ID `com.popup.app` under the **Organization** team (or create a new Org team and transfer).
2. Request: [Tap to Pay on iPhone entitlement](https://developer.apple.com/contact/request/tap-to-pay-on-iphone/) (Account → tap to pay request). Wait for approval (days–weeks).
3. App ID `com.popup.app` → enable **Tap to Pay on iPhone** (keep **Apple Pay** + `merchant.com.popup.app`).
4. Regenerate provisioning profiles / let Xcode Automatic Signing refresh.

### B. Square

1. Confirm sandbox/production Square app supports Mobile Payments / Tap to Pay.
2. Keep platform access token + location ID on the hosted API (already used for seller Receive).
3. Production launch: swap to `sq0idp-…` app ID + `SQUARE_ENVIRONMENT=production` on Render.

### C. iOS config (one Release flip)

In `ios/Config/Secrets.xcconfig` (gitignored) **and/or** `SupabaseProject.xcconfig`:

```xcconfig
POPUP_RELEASE_ENTITLEMENTS = PopupApp.Payments.entitlements
TAP_TO_PAY_ENABLED = YES
APPLE_PAY_MERCHANT_ID = merchant.com.popup.app
```

Keep buyer Apple Pay merchant as-is. `PopupApp.Payments.entitlements` includes both Apple Pay and Tap to Pay.

### D. Ship the update

```sh
cd ios && python3 generate_xcode_project.py
# bump CURRENT_PROJECT_VERSION in generate_xcode_project.py
open PopupApp.xcodeproj
```

Archive → TestFlight → device smoke test:

1. Confirmed meetup → seller taps **Receive**  
2. Phone enters Tap to Pay / “ready for tap”  
3. Buyer taps card or phone  
4. Listing sold; seller **balance** increases  

---

## What not to change when flipping on

- Do **not** remove the settle-delay / entitlement check in `TapToPayCollector` (prevents TestFlight freezes).
- Do **not** start Tap to Pay in the same frame as presenting the SwiftUI sheet — keep `onAppear` + delay.
- Buyer Pay (Apple Pay / card) stays on `PopupApp.ApplePay.entitlements` until you switch Release to `Payments`.

---

## Related docs

- Buyer Apple Pay / TestFlight archive: `ios/TESTFLIGHT.md`
- Square sandbox + Render URLs: `ios/TESTFLIGHT.md` § payments  
- Production scanner model reminder: set `OPENAI_MODEL=openai-sol` on Render when going live (separate from Tap to Pay)
