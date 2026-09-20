# Running popup in Expo Go on your phone

1. **Install Expo Go** on your phone from the App Store (iOS) or Google Play (Android).

2. **Start the backend** (from the project root):
   ```bash
   cd backend
   npm run dev
   ```
   Leave this running. The API runs on port **5001** by default (5000 is avoided on macOS because AirPlay often uses it and can return HTTP 403).

3. **Start the frontend** (from the project root):
   ```bash
   cd frontend
   npm start
   ```
   Or: `npm run start:go`

4. **Connect your phone and computer to the same Wi‑Fi.**

5. **Open the project in Expo Go:**
   - **iPhone:** Open the Camera app and scan the QR code shown in the terminal.
   - **Android:** Open the Expo Go app and tap “Scan QR code,” then scan the QR code.

The app will load on your phone. API and socket connections are set to use your computer’s IP when running in Expo Go, so the app on your phone can talk to the backend on your machine.

---

### Stuck on “Opening project” or loading forever?

Expo Go is trying to download the app bundle from your computer. If it hangs, the phone often can’t reach Metro (different Wi‑Fi, firewall, or strict network).

**Try this first – use tunnel mode** (phone connects via the internet instead of LAN):

```bash
cd frontend
npm run start:tunnel
```

Then scan the **new** QR code with Expo Go. The first time may take a minute while the tunnel starts.

**If it still hangs:**

1. **Clear Metro cache and restart:**
   ```bash
   cd frontend
   npm run start:clear
   ```
   Then scan the QR code again.

2. **Same Wi‑Fi:** Phone and computer must be on the same network for non-tunnel mode.

3. **Firewall:** Allow Node/Metro on port **8081** (and **5001** for the API) so your phone can connect.

---

**If the app loads but can’t reach the backend:** Make sure your computer’s firewall allows incoming connections on ports **5001** (API) and **8081** (Metro). With tunnel mode, the app still talks to your backend over your LAN (same Wi‑Fi); for a fully remote setup you’d need the backend reachable too (e.g. deployed or tunneled).
