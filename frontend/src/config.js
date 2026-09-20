/**
 * API base URL for backend. When running in Expo Go on a device, the app
 * loads from your computer's IP (e.g. 192.168.1.x:8081). "localhost" on the
 * phone is the phone itself, so we use the same host as the dev server for
 * API and socket connections.
 *
 * Backend port: app.json `extra.apiPort`, or EXPO_PUBLIC_API_PORT, or 5001.
 * Default 5001: macOS AirPlay Receiver often binds 5000 and returns HTTP 403,
 * so login/register appear to "fail" with status 403 if the app points at 5000.
 */
function resolveApiPort(extra) {
  if (extra && extra.apiPort != null && extra.apiPort !== '') {
    const p = Number(extra.apiPort);
    if (Number.isFinite(p)) return p;
  }
  if (typeof process !== 'undefined' && process.env && process.env.EXPO_PUBLIC_API_PORT) {
    const p = parseInt(process.env.EXPO_PUBLIC_API_PORT, 10);
    if (Number.isFinite(p)) return p;
  }
  return 5001;
}

let apiPort = 5001;
try {
  const Constants = require('expo-constants').default;
  const extra = (Constants.expoConfig && Constants.expoConfig.extra) || (Constants.manifest && Constants.manifest.extra) || {};
  apiPort = resolveApiPort(extra);
} catch (_) {
  apiPort = resolveApiPort({});
}

let API_BASE_URL = `http://localhost:${apiPort}/api`;
let SOCKET_URL = `http://localhost:${apiPort}`;

try {
  const Constants = require('expo-constants').default;
  const extra = (Constants.expoConfig && Constants.expoConfig.extra) || (Constants.manifest && Constants.manifest.extra) || {};
  if (extra.apiUrl) API_BASE_URL = extra.apiUrl;
  if (extra.socketUrl) SOCKET_URL = extra.socketUrl;

  if (typeof __DEV__ !== 'undefined' && !__DEV__) {
    API_BASE_URL = 'https://your-api.com/api';
    SOCKET_URL = 'https://your-api.com';
  } else {
    const host = getDevServerHost(Constants);
    if (host) {
      API_BASE_URL = `http://${host}:${apiPort}/api`;
      SOCKET_URL = `http://${host}:${apiPort}`;
    }
  }
} catch (_) {
  // keep defaults if anything fails (e.g. expo-constants not available)
}

function getDevServerHost(Constants) {
  try {
    const hostUri = (Constants.expoConfig && Constants.expoConfig.hostUri)
      || (Constants.manifest && Constants.manifest.hostUri)
      || (Constants.manifest && Constants.manifest.debuggerHost);
    if (!hostUri || typeof hostUri !== 'string') return null;
    // hostUri can be "192.168.1.5:8081" or "exp://192.168.1.5:8081"
    const withoutProtocol = hostUri.replace(/^[a-z][a-z0-9+.-]*:\/\//i, '');
    const host = withoutProtocol.split(':')[0];
    return host || null;
  } catch (_) {
    return null;
  }
}

export { API_BASE_URL, SOCKET_URL };
