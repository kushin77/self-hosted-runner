#!/bin/bash
set -e

# SSO Platform Load Testing with k6
# Load testing scenarios for OAuth2, Keycloak, and downstream services

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const authDuration = new Trend('auth_duration');
const cacheDuration = new Trend('cache_duration');

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://oauth2-proxy.local';
const KEYCLOAK_URL = __ENV.KEYCLOAK_URL || 'http://keycloak.local';
const LOAD_USERS = parseInt(__ENV.LOAD_USERS) || 100;
const DURATION = __ENV.DURATION || '5m';
const SPIKE_USERS = parseInt(__ENV.SPIKE_USERS) || 500;
const SPIKE_DURATION = __ENV.SPIKE_DURATION || '30s';

// Scenarios
export const options = {
  stages: [
    // Ramp-up: gradually increase to target load
    { duration: '2m', target: LOAD_USERS },
    // Stay at target load
    { duration: DURATION, target: LOAD_USERS },
    // Spike test
    { duration: SPIKE_DURATION, target: SPIKE_USERS },
    { duration: '2m', target: LOAD_USERS },
    // Ramp-down
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    'http_req_duration': ['p(95)<1000', 'p(99)<3000'],
    'http_req_failed': ['rate<0.05'],
    'errors': ['rate<0.1'],
  },
};

export function setup() {
  // Get auth token from Keycloak
  const params = {
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
  };

  const loginRes = http.post(
    `${KEYCLOAK_URL}/auth/realms/master/protocol/openid-connect/token`,
    {
      grant_type: 'client_credentials',
      client_id: 'test-client',
      client_secret: 'test-secret',
    },
    params
  );

  check(loginRes, {
    'login status is 200': (r) => r.status === 200,
  });

  const token = loginRes.json('access_token');
  return {
    token: token,
    baseUrl: BASE_URL,
  };
}

export default function (data) {
  const authCookie = data.token;
  const headers = {
    Authorization: `Bearer ${authCookie}`,
    'Content-Type': 'application/json',
  };

  // Test 1: OAuth2 token validation
  group('OAuth2-Proxy Token Validation', () => {
    const startTime = new Date();
    const res = http.get(`${data.baseUrl}/oauth2/auth`, {
      headers: headers,
    });
    const duration = new Date() - startTime;

    authDuration.add(duration);
    check(res, {
      'auth status is 200 or 401': (r) => r.status === 200 || r.status === 401,
      'auth response time < 500ms': (r) => r.timings.duration < 500,
    }) || errorRate.add(1);
  });

  sleep(0.5);

  // Test 2: Downstream API endpoint (protected)
  group('Protected Endpoint Access', () => {
    const res = http.get(`${data.baseUrl}/api/v1/users`, {
      headers: headers,
    });

    check(res, {
      'endpoint status is 200': (r) => r.status === 200,
      'endpoint response time < 2000ms': (r) => r.timings.duration < 2000,
    }) || errorRate.add(1);
  });

  sleep(1);

  // Test 3: Session cache hit (should be fast)
  group('Session Cache Performance', () => {
    const startTime = new Date();
    const res = http.get(`${data.baseUrl}/oauth2/userinfo`, {
      headers: headers,
    });
    const duration = new Date() - startTime;

    cacheDuration.add(duration);
    check(res, {
      'cache hit response time < 100ms': (r) => r.timings.duration < 100,
      'cache status is 200': (r) => r.status === 200,
    }) || errorRate.add(1);
  });

  sleep(1);

  // Test 4: Concurrent login attempts
  group('Concurrent Login Load', () => {
    const batch = http.batch([
      ['GET', `${data.baseUrl}/oauth2/sign_in`],
      ['GET', `${data.baseUrl}/oauth2/auth`],
      ['GET', `${data.baseUrl}/oauth2/userinfo`],
    ]);

    check(batch[0], {
      'sign_in status is 200/302': (r) => r.status === 200 || r.status === 302,
    }) || errorRate.add(1);
  });

  sleep(2);
}

export function teardown(data) {
  // Cleanup if needed
}

export function handleSummary(data) {
  return {
    '/tmp/k6-summary.json': JSON.stringify(data),
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
  };
}
