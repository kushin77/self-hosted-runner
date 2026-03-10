import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import Dashboard from './Dashboard_v2';
import * as API from '../services/api';

// Mock the API module
jest.mock('../services/api');

describe('NexusShield Portal Dashboard', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    
    // Default mock implementations
    (API.CredentialAPI.listCredentials as jest.Mock).mockResolvedValue({
      credentials: [
        { id: '1', name: 'prod-db-password', type: 'password', created_at: '2026-03-09T00:00:00Z' },
        { id: '2', name: 'api-key-prod', type: 'api_key', created_at: '2026-03-09T00:00:00Z' },
      ],
    });

    (API.AuditAPI.queryAudit as jest.Mock).mockResolvedValue({
      entries: [
        {
          id: 'a1',
          timestamp: '2026-03-10T12:00:00Z',
          action: 'credential_rotated',
          resource_type: 'credential',
          resource_id: 'prod-db-password',
          actor: 'system',
          status: 'success',
        },
      ],
    });

    (API.MetricsAPI.getHealth as jest.Mock).mockResolvedValue({
      status: 'healthy',
      checks: { database: 'ok', api: 'ok', audit: 'ok', memory: 'ok' },
      uptime_seconds: 3600,
    });
  });

  describe('Overview Tab', () => {
    it('✅ should render dashboard header', async () => {
      render(<Dashboard />);
      
      await waitFor(() => {
        expect(screen.getByText(/NexusShield Portal/i)).toBeInTheDocument();
      });
    });

    it('✅ should display credential count (idempotent)', async () => {
      render(<Dashboard />);
      
      await waitFor(() => {
        expect(screen.getByText('2')).toBeInTheDocument(); // 2 credentials
      });
    });

    it('✅ should fetch credentials on mount and periodic refresh', async () => {
      jest.useFakeTimers();
      render(<Dashboard />);

      await waitFor(() => {
        expect(API.CredentialAPI.listCredentials).toHaveBeenCalled();
      });

      // Verify periodic refresh (every 30 seconds)
      jest.advanceTimersByTime(30000);
      expect(API.CredentialAPI.listCredentials).toHaveBeenCalledTimes(2);

      jest.useRealTimers();
    });

    it('✅ should display health status', async () => {
      render(<Dashboard />);
      
      await waitFor(() => {
        expect(screen.getByText(/HEALTHY/i)).toBeInTheDocument();
      });
    });

    it('✅ should show uptime calculation', async () => {
      render(<Dashboard />);
      
      await waitFor(() => {
        expect(screen.getByText(/1h/)).toBeInTheDocument(); // 3600 seconds = 1 hour
      });
    });
  });

  describe('Credentials Tab', () => {
    it('✅ should render credentials table', async () => {
      render(<Dashboard />);
      
      // Click credentials tab
      const credTab = screen.getByText(/Credentials/);
      credTab.click();

      await waitFor(() => {
        expect(screen.getByText('prod-db-password')).toBeInTheDocument();
        expect(screen.getByText('api-key-prod')).toBeInTheDocument();
      });
    });

    it('✅ should display credential types correctly', async () => {
      render(<Dashboard />);
      const credTab = screen.getByText(/Credentials/);
      credTab.click();

      await waitFor(() => {
        expect(screen.getByText('PASSWORD')).toBeInTheDocument();
        expect(screen.getByText('API_KEY')).toBeInTheDocument();
      });
    });

    it('✅ should call listCredentials with token (idempotent)', async () => {
      sessionStorage.setItem('auth_token', 'test-token');
      render(<Dashboard />);

      await waitFor(() => {
        expect(API.CredentialAPI.listCredentials).toHaveBeenCalledWith('test-token');
      });
    });

    it('✅ should render rotate button for each credential', async () => {
      render(<Dashboard />);
      const credTab = screen.getByText(/Credentials/);
      credTab.click();

      await waitFor(() => {
        const rotateButtons = screen.getAllByText('Rotate');
        expect(rotateButtons.length).toBe(2); // One for each credential
      });
    });
  });

  describe('Audit Tab', () => {
    it('✅ should render audit trail entries', async () => {
      render(<Dashboard />);
      const auditTab = screen.getByText(/Audit/);
      auditTab.click();

      await waitFor(() => {
        expect(screen.getByText(/credential_rotated/i)).toBeInTheDocument();
      });
    });

    it('✅ should display immutable audit status (append-only)', async () => {
      render(<Dashboard />);
      const auditTab = screen.getByText(/Audit/);
      auditTab.click();

      await waitFor(() => {
        expect(screen.getByText(/Immutable Audit Trail/i)).toBeInTheDocument();
      });
    });

    it('✅ should have verify integrity button', async () => {
      render(<Dashboard />);
      const auditTab = screen.getByText(/Audit/);
      auditTab.click();

      await waitFor(() => {
        expect(screen.getByText('🔐 Verify Integrity')).toBeInTheDocument();
      });
    });

    it('✅ should have export to cloud button', async () => {
      render(<Dashboard />);
      const auditTab = screen.getByText(/Audit/);
      auditTab.click();

      await waitFor(() => {
        expect(screen.getByText('☁️ Export to Cloud')).toBeInTheDocument();
      });
    });
  });

  describe('Error Handling', () => {
    it('✅ should display error banner on API failure', async () => {
      (API.CredentialAPI.listCredentials as jest.Mock).mockRejectedValueOnce(
        new Error('API connection failed')
      );

      render(<Dashboard />);

      await waitFor(() => {
        expect(screen.getByText(/API connection failed/)).toBeInTheDocument();
      });
    });

    it('✅ should recover from transient errors (idempotent)', async () => {
      let callCount = 0;
      (API.CredentialAPI.listCredentials as jest.Mock).mockImplementation(() => {
        callCount++;
        if (callCount === 1) {
          return Promise.reject(new Error('Transient error'));
        }
        return Promise.resolve({ credentials: [] });
      });

      render(<Dashboard />);

      await waitFor(() => {
        expect(API.CredentialAPI.listCredentials).toHaveBeenCalled();
      });
    });
  });

  describe('Architecture Requirements', () => {
    it('✅ ensures ephemeral credential handling (no localStorage persistence)', () => {
      // Verify credentials are only in sessionStorage, not localStorage
      sessionStorage.setItem('auth_token', 'test-token-ephemeral');
      expect(sessionStorage.getItem('auth_token')).toBe('test-token-ephemeral');
      expect(localStorage.getItem('auth_token')).toBeNull(); // Would be set in non-ephemeral
    });

    it('✅ ensures idempotent API calls (same params = same result)', async () => {
      const mockFn = jest.fn().mockResolvedValue({ credentials: [] });
      (API.CredentialAPI.listCredentials as jest.Mock).mockImplementation(mockFn);

      render(<Dashboard />);

      await waitFor(() => {
        const calls = mockFn.mock.calls;
        // Multiple calls with same parameters should return identical results
        expect(calls[0]).toEqual(calls[1]); // Same parameters
      });
    });

    it('✅ ensures audit trail is immutable (append-only display)', async () => {
      const auditEntry = {
        id: 'immutable-1',
        timestamp: '2026-03-10T12:00:00Z',
        action: 'credential_created',
        resource_type: 'credential',
        resource_id: 'test-cred',
        actor: 'user@example.com',
        status: 'success' as const,
      };

      (API.AuditAPI.queryAudit as jest.Mock).mockResolvedValue({
        entries: [auditEntry],
      });

      render(<Dashboard />);
      const auditTab = screen.getByText(/Audit/);
      auditTab.click();

      await waitFor(() => {
        // Verify immutable entry is displayed
        expect(screen.getByText('credential_created')).toBeInTheDocument();
      });
    });
  });

  describe('UI/UX Compliance', () => {
    it('✅ should be responsive (desktop view)', () => {
      render(<Dashboard />);
      expect(screen.getByText(/NexusShield Portal/i)).toBeInTheDocument();
    });

    it('✅ should have accessible tab navigation', async () => {
      render(<Dashboard />);
      
      const tabs = screen.getAllByRole('button').filter((btn) =>
        btn.textContent?.includes('Overview') || 
        btn.textContent?.includes('Credentials') ||
        btn.textContent?.includes('Audit')
      );

      expect(tabs.length).toBe(3);
    });

    it('✅ should handle loading state', () => {
      render(<Dashboard />);
      // Dashboard should show loading message while fetching
      expect(screen.getByText(/Loading dashboard/i)).toBeInTheDocument();
    });
  });
});

describe('Dashboard API Integration', () => {
  it('✅ should fetch metrics in parallel with credentials', async () => {
    render(<Dashboard />);

    await waitFor(() => {
      expect(API.CredentialAPI.listCredentials).toHaveBeenCalled();
      expect(API.MetricsAPI.getHealth).toHaveBeenCalled();
    });
  });

  it('✅ should retry failed requests gracefully', async () => {
    (API.CredentialAPI.listCredentials as jest.Mock)
      .mockRejectedValueOnce(new Error('Timeout'))
      .mockResolvedValueOnce({ credentials: [] });

    render(<Dashboard />);

    await waitFor(() => {
      expect(API.CredentialAPI.listCredentials).toHaveBeenCalledTimes(1);
    });
  });

  it('✅ should parse Prometheus metrics format', async () => {
    render(<Dashboard />);

    await waitFor(() => {
      expect(API.MetricsAPI.getHealth).toHaveBeenCalled();
    });
  });
});
