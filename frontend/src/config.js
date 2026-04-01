/**
 * API base URL for backend. When running in Expo Go on a device, the app
 * loads from your computer's IP (e.g. 192.168.1.x:8081). "localhost" on the
 * phone is the phone itself, so we use the same host as the dev server for
 * API and socket connections.
 */
let API_BASE_URL = 'http://localhost:5000/api';
let SOCKET_URL = 'http://localhost:5000';

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
      API_BASE_URL = `http://${host}:5000/api`;
      SOCKET_URL = `http://${host}:5000`;
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
