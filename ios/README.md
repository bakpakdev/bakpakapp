# Bakpak iOS (SwiftUI)

This directory contains the iOS rewrite of the app using Swift + SwiftUI.

## Project structure

- `BakpakApp/` app source
  - `Core/` networking, models, keychain, view models
  - `Views/` screen implementations for auth, home, search, listing, messages, profile, cart, checkout, and orders

## Backend compatibility

The app is wired to the same backend routes used by the React Native app:

- `/auth/*`
- `/products/*`
- `/discover`
- `/search`
- `/messages/*`
- `/users/*`
- `/social/*`
- `/cart/*`
- `/orders/*`

## Run notes

1. Open this folder in Xcode and create an iOS App target named `BakpakApp`.
2. Add all Swift files from `BakpakApp/` into that target.
3. Set deployment target to iOS 16+.
4. Run backend on `http://localhost:5000`.
5. In Login screen, set API URL to your machine API endpoint (example: `http://192.168.1.20:5000/api`) when testing on a physical device.

## Stripe and sockets

- The current rewrite includes order fetching and order creation placeholder UI.
- To complete payment parity, integrate Stripe iOS SDK and connect to `/orders` flow.
- For realtime message parity, integrate Socket.IO iOS client (polling fallback currently supported by REST refresh flow).
