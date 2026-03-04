/**
 * Authentication Manager
 * Handles token storage, rotation, and refresh
 */

import type { AuthToken, AuthContext } from './types';

const TOKEN_STORAGE_KEY = 'runnercloud:auth:token';
const REFRESH_THRESHOLD = 5 * 60 * 1000; // Refresh 5 min before expiry

export class AuthManager {
  private token: AuthToken | null = null;
  private refreshTimer: number | null = null;
  private listeners: Set<(context: AuthContext) => void> = new Set();

  constructor() {
    this.loadToken();
  }

  /**
   * Load token from local storage
   */
  private loadToken(): void {
    try {
      const stored = localStorage.getItem(TOKEN_STORAGE_KEY);
      if (stored) {
        const parsed = JSON.parse(stored) as AuthToken;
        if (parsed.expiresAt > Date.now()) {
          this.token = parsed;
          this.scheduleRefresh();
        } else {
          this.clearToken();
        }
      }
    } catch {
      this.clearToken();
    }
  }

  /**
   * Save token to local storage
   */
  private saveToken(token: AuthToken): void {
    this.token = token;
    localStorage.setItem(TOKEN_STORAGE_KEY, JSON.stringify(token));
    this.scheduleRefresh();
    this.notifyListeners();
  }

  /**
   * Schedule token refresh
   */
  private scheduleRefresh(): void {
    if (this.refreshTimer) {
      clearTimeout(this.refreshTimer);
    }

    if (this.token) {
      const now = Date.now();
      const refreshAt = this.token.expiresAt - REFRESH_THRESHOLD;
      const delay = Math.max(0, refreshAt - now);

      if (delay > 0) {
        this.refreshTimer = window.setTimeout(() => this.refreshToken(), delay) as unknown as number;
      }
    }
  }

  /**
   * Set new token (from login)
   */
  setToken(token: AuthToken): void {
    this.saveToken(token);
  }

  /**
   * Get current token
   */
  getToken(): AuthToken | null {
    return this.token;
  }

  /**
   * Get auth header for API requests
   */
  getAuthHeader(): Record<string, string> {
    if (!this.token) {
      return {};
    }
    return {
      Authorization: `${this.token.tokenType} ${this.token.accessToken}`,
    };
  }

  /**
   * Refresh token
   */
  async refreshToken(): Promise<void> {
    if (!this.token?.refreshToken) {
      this.clearToken();
      return;
    }

    try {
      const response = await fetch('/api/auth/refresh', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          refreshToken: this.token.refreshToken,
        }),
      });

      if (response.ok) {
        const newToken = (await response.json()) as AuthToken;
        this.saveToken(newToken);
      } else {
        this.clearToken();
      }
    } catch {
      // Continue with expired token, let API handle it
      this.scheduleRefresh();
    }
  }

  /**
   * Clear token (logout)
   */
  clearToken(): void {
    this.token = null;
    localStorage.removeItem(TOKEN_STORAGE_KEY);
    if (this.refreshTimer) {
      window.clearTimeout(this.refreshTimer as number);
      this.refreshTimer = null;
    }
    this.notifyListeners();
  }

  /**
   * Get auth context
   */
  getContext(): AuthContext {
    return {
      token: this.token,
      isAuthenticated: this.token !== null,
      expiresIn: this.token ? Math.max(0, this.token.expiresAt - Date.now()) : 0,
    };
  }

  /**
   * Subscribe to auth changes
   */
  subscribe(listener: (context: AuthContext) => void): () => void {
    this.listeners.add(listener);
    listener(this.getContext());

    return () => {
      this.listeners.delete(listener);
    };
  }

  /**
   * Notify all listeners of auth state change
   */
  private notifyListeners(): void {
    const context = this.getContext();
    this.listeners.forEach(listener => listener(context));
  }
}

// Singleton instance
export const authManager = new AuthManager();
