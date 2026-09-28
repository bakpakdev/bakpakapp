# popup iOS app

Native SwiftUI app. **Open this one project only:**

```
ios/PopupApp.xcodeproj
```

Do **not** look for `BakpakApp.xcodeproj` — that duplicate was removed.

## Folder map

| Path | What it is |
|------|------------|
| `PopupApp.xcodeproj` | The Xcode project — open this |
| `BakpakApp/` | All Swift source, assets, entitlements |
| `Config/` | Supabase / API / Square settings (`Secrets.xcconfig` is local-only) |
| `generate_xcode_project.py` | Rebuilds the `.xcodeproj` if you add new Swift files |
| `run-simulator.sh` | Optional CLI build + install to Simulator |
| `QA_CHECKLIST.md` | Manual test checklist |

## Open in Xcode (best way)

1. Quit Xcode if it’s already open.
2. In Finder go to `Documents/bakpakapp/ios/`.
3. Double-click **`PopupApp.xcodeproj`** (blue icon).
4. Wait for Swift packages (Supabase / Square) to finish resolving.
5. Top scheme should be **PopupApp**.
6. Pick a simulator (e.g. iPhone 17 Pro) or your iPhone.
7. Press **Run** (▶).

### First time / after cloning

Make sure `ios/Config/Secrets.xcconfig` exists (gitignored). Copy from the example comments in `Config/Supabase.example.xcconfig` and fill in:

- `SUPABASE_ANON_KEY`
- `SQUARE_APPLICATION_ID` (optional until payments)
- `APPLE_PAY_MERCHANT_ID` (optional)

Backend for payments/cash-out: run `backend` on port `5001` (`npm start`).

### If you add new `.swift` files

Either:
- Add them in Xcode to the PopupApp target, **or**
- From Terminal: `cd ios && python3 generate_xcode_project.py` then reopen/rebuild.

## What not to open

- `frontend/` — old Expo web/mobile code, not this Swift app
- `backend/` — Node API (needed for Square/cash-out, not opened in Xcode)
- `supabase/` — SQL migrations for the database
