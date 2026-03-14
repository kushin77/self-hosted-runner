// JavaScript/React Client SDK for SSO Platform
// Usage: npm install @nexus/sso-client

import React, { useEffect, useState } from 'react';

class KeycloakClient {
  constructor(config) {
    this.keycloakUrl = config.keycloakUrl || 'http://keycloak:8080/auth';
    this.realm = config.realm || 'master';
    this.clientId = config.clientId;
    this.redirectUri = config.redirectUri || window.location.origin + '/callback';
    this.scopes = config.scopes || ['openid', 'profile', 'email'];
    this.token = localStorage.getItem('sso_token');
    this.refreshToken = localStorage.getItem('sso_refresh_token');
  }

  getOidcConfig() {
    return fetch(`${this.keycloakUrl}/realms/${this.realm}/.well-known/openid-configuration`)
      .then(r => r.json());
  }

  async login() {
    const config = await this.getOidcConfig();
    const state = this.generateRandomString(16);
    const nonce = this.generateRandomString(16);
    
    localStorage.setItem('sso_state', state);
    localStorage.setItem('sso_nonce', nonce);

    const params = new URLSearchParams({
      client_id: this.clientId,
      response_type: 'code',
      scope: this.scopes.join(' '),
      redirect_uri: this.redirectUri,
      state: state,
      nonce: nonce,
    });

    window.location.href = `${config.authorization_endpoint}?${params}`;
  }

  async handleCallback() {
    const params = new URLSearchParams(window.location.search);
    const code = params.get('code');
    const state = params.get('state');

    if (state !== localStorage.getItem('sso_state')) {
      throw new Error('State mismatch - possible CSRF attack');
    }

    const config = await this.getOidcConfig();
    const tokenResponse = await fetch(config.token_endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code: code,
        redirect_uri: this.redirectUri,
        client_id: this.clientId,
        client_secret: process.env.REACT_APP_CLIENT_SECRET,
      }),
    });

    const data = await tokenResponse.json();
    localStorage.setItem('sso_token', data.access_token);
    localStorage.setItem('sso_refresh_token', data.refresh_token);
    this.token = data.access_token;
    this.refreshToken = data.refresh_token;

    return data;
  }

  async getUser() {
    const config = await this.getOidcConfig();
    const response = await fetch(config.userinfo_endpoint, {
      headers: { Authorization: `Bearer ${this.token}` },
    });
    return response.json();
  }

  async logout() {
    const config = await this.getOidcConfig();
    localStorage.removeItem('sso_token');
    localStorage.removeItem('sso_refresh_token');
    window.location.href = `${config.end_session_endpoint}?redirect_uri=${this.redirectUri}`;
  }

  async refreshAccessToken() {
    const config = await this.getOidcConfig();
    const response = await fetch(config.token_endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'refresh_token',
        refresh_token: this.refreshToken,
        client_id: this.clientId,
      }),
    });

    const data = await response.json();
    localStorage.setItem('sso_token', data.access_token);
    this.token = data.access_token;
    return data;
  }

  generateRandomString(length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    let result = '';
    for (let i = 0; i < length; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
  }
}

// React Hook
export function useSSOAuth(config) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const client = new KeycloakClient(config);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    if (params.has('code')) {
      client.handleCallback()
        .then(() => client.getUser())
        .then(setUser)
        .catch(setError)
        .finally(() => setLoading(false));
    } else if (client.token) {
      client.getUser()
        .then(setUser)
        .catch(() => {
          client.refreshAccessToken()
            .then(() => client.getUser())
            .then(setUser)
            .catch(setError);
        })
        .finally(() => setLoading(false));
    } else {
      setLoading(false);
    }
  }, []);

  return {
    user,
    loading,
    error,
    login: () => client.login(),
    logout: () => client.logout(),
    token: client.token,
  };
}

// Protected Route Component
export function ProtectedRoute({ component: Component, ...rest }) {
  const { user, loading } = useSSOAuth(rest.authConfig);

  if (loading) return <div>Loading...</div>;
  if (!user) return <div onClick={() => window.location.href = '/login'}>Login Required</div>;

  return <Component {...rest} user={user} />;
}

export default KeycloakClient;
