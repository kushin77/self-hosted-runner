/**
 * Minimal auth manager for portal frontend.
 * Provides a lightweight in-memory token store and refresh scheduling.
 */

// Minimal AuthToken shape used by the frontend auth manager
type AuthToken = {
  accessToken: string;
  refreshToken?: string;
  expiresAt?: number;
  tokenType?: string;
};

class AuthManager {
  private token: AuthToken | null = null;
  private refreshTimer: ReturnType<typeof setTimeout> | null = null;

  getAuthHeader(): Record<string, string> {
    if (!this.token) return {};
    return { Authorization: `${this.token.tokenType} ${this.token.accessToken}` };
  }

  saveToken(token: AuthToken) {
    this.token = token;
    try {
      localStorage.setItem('RC_AUTH', JSON.stringify(token));
    } catch (_) {}
    this.scheduleRefresh();
  }

  loadToken(): AuthToken | null {
    if (this.token) return this.token;
    try {
      const raw = localStorage.getItem('RC_AUTH');
      if (!raw) return null;
      this.token = JSON.parse(raw) as AuthToken;
      this.scheduleRefresh();
      return this.token;
    } catch (_) {
      return null;
    }
  }

  clearToken() {
    this.token = null;
    try {
      localStorage.removeItem('RC_AUTH');
    } catch (_) {}
    if (this.refreshTimer) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = null;
    }
  }

  async refreshToken(): Promise<void> {
    // In mock mode, fabricate a new token. In production, callers should
    // call a backend refresh endpoint.
    if (!this.token) return;
    try {
      // simplistic refresh: extend expiry
      this.token.expiresAt = Date.now() + 60 * 60 * 1000;
      this.saveToken(this.token);
    } catch (_) {}
  }

  private scheduleRefresh() {
    if (!this.token || !this.token.expiresAt) return;
    const msUntil = this.token.expiresAt - Date.now() - 60_000; // refresh 60s early
    if (this.refreshTimer) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = null;
    }
    if (msUntil <= 0) return;
    this.refreshTimer = setTimeout(() => void this.refreshToken(), Math.max(1000, msUntil));
  }
}

export const authManager = new AuthManager();

// Auto-load token if present
authManager.loadToken();
