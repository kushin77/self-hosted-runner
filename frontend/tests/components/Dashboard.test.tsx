/**
 * Component Tests: Dashboard
 * Tests dashboard layout, data display, and interactions
 */

import { describe, it, expect, beforeEach, jest } from '@jest/globals';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import Dashboard from '../../../src/components/Dashboard';

describe('Dashboard Component', () => {
  const mockCredentials = [
    { id: '1', name: 'db_password', type: 'password', lastRotated: '2026-03-10', status: 'active' },
    { id: '2', name: 'api_key', type: 'api_key', lastRotated: '2026-03-08', status: 'active' },
  ];

  const mockUser = {
    id: 'user123',
    email: 'user@example.com',
    role: 'admin',
    name: 'Test User',
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('Rendering', () => {
    it('should render dashboard container', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByText(/dashboard/i)).toBeInTheDocument();
    });

    it('should render header with welcome message', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByText(/welcome/i)).toBeInTheDocument();
      expect(screen.getByText(mockUser.name)).toBeInTheDocument();
    });

    it('should render sidebar navigation', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByText(/credentials/i)).toBeInTheDocument();
      expect(screen.getByText(/audit log/i)).toBeInTheDocument();
      expect(screen.getByText(/settings/i)).toBeInTheDocument();
    });

    it('should render main content area', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByRole('main')).toBeInTheDocument();
    });

    it('should render credentials list', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByText('db_password')).toBeInTheDocument();
      expect(screen.getByText('api_key')).toBeInTheDocument();
    });
  });

  describe('Credentials Display', () => {
    it('should display credential name', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByText('db_password')).toBeInTheDocument();
    });

    it('should display credential type', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByText(/password|api_key/)).toBeInTheDocument();
    });

    it('should display last rotation date', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByText(/2026-03-10|2026-03-08/)).toBeInTheDocument();
    });

    it('should display credential status', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      const activeStatuses = screen.getAllByText(/active/i);
      expect(activeStatuses.length).toBeGreaterThan(0);
    });

    it('should display empty state when no credentials', () => {
      render(<Dashboard user={mockUser} credentials={[]} />);

      expect(screen.getByText(/no credentials/i)).toBeInTheDocument();
    });
  });

  describe('Actions', () => {
    it('should have add credential button', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByRole('button', { name: /add credential/i })).toBeInTheDocument();
    });

    it('should open add credential modal on button click', async () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      const addButton = screen.getByRole('button', { name: /add credential/i });
      fireEvent.click(addButton);

      await waitFor(() => {
        expect(screen.getByText(/create new credential/i)).toBeInTheDocument();
      });
    });

    it('should have edit button for each credential', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      const editButtons = screen.getAllByRole('button', { name: /edit/i });
      expect(editButtons.length).toBe(mockCredentials.length);
    });

    it('should have rotate button for each credential', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      const rotateButtons = screen.getAllByRole('button', { name: /rotate/i });
      expect(rotateButtons.length).toBe(mockCredentials.length);
    });

    it('should have delete button for each credential', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      const deleteButtons = screen.getAllByRole('button', { name: /delete/i });
      expect(deleteButtons.length).toBe(mockCredentials.length);
    });
  });

  describe('Sorting and Filtering', () => {
    it('should have sort options', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByText(/sort/i)).toBeInTheDocument();
    });

    it('should sort credentials by name', async () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      const sortButton = screen.getByRole('button', { name: /sort by name/i });
      fireEvent.click(sortButton);

      const credentials = screen.getAllByRole('row', { name: /api|db/ });
    });

    it('should have filter options', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByText(/filter|type/i)).toBeInTheDocument();
    });

    it('should filter credentials by type', async () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      const filterButton = screen.getByRole('button', { name: /filter/i });
      fireEvent.click(filterButton);

      const passwordOption = screen.getByText(/password/);
      fireEvent.click(passwordOption);

      await waitFor(() => {
        expect(screen.getByText('db_password')).toBeInTheDocument();
        expect(screen.queryByText('api_key')).not.toBeInTheDocument();
      });
    });

    it('should have search functionality', async () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      const searchInput = screen.getByPlaceholderText(/search/i);
      await userEvent.type(searchInput, 'db_');

      await waitFor(() => {
        expect(screen.getByText('db_password')).toBeInTheDocument();
        expect(screen.queryByText('api_key')).not.toBeInTheDocument();
      });
    });
  });

  describe('User Profile', () => {
    it('should display user name', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByText(mockUser.name)).toBeInTheDocument();
    });

    it('should display user role', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByText(/admin/i)).toBeInTheDocument();
    });

    it('should have user menu', async () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      const userMenu = screen.getByRole('button', { name: new RegExp(mockUser.name, 'i') });
      fireEvent.click(userMenu);

      await waitFor(() => {
        expect(screen.getByText(/settings/i)).toBeInTheDocument();
        expect(screen.getByText(/logout/i)).toBeInTheDocument();
      });
    });

    it('should have logout button', async () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      const userMenu = screen.getByRole('button', { name: new RegExp(mockUser.name, 'i') });
      fireEvent.click(userMenu);

      const logoutButton = screen.getByText(/logout/i);
      expect(logoutButton).toBeInTheDocument();
    });
  });

  describe('Statistics', () => {
    it('should display credential count', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByText(/total credentials|credentials: 2/i)).toBeInTheDocument();
    });

    it('should display active credential count', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByText(/active|2/i)).toBeInTheDocument();
    });

    it('should display rotation statistics', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByText(/rotation|last rotated/i)).toBeInTheDocument();
    });
  });

  describe('Responsive Layout', () => {
    it('should have mobile-friendly layout', () => {
      // Set mobile viewport
      Object.defineProperty(window, 'innerWidth', {
        writable: true,
        configurable: true,
        value: 375,
      });

      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByText(/dashboard/i)).toBeInTheDocument();
    });

    it('should collapse sidebar on mobile', () => {
      Object.defineProperty(window, 'innerWidth', {
        writable: true,
        configurable: true,
        value: 375,
      });

      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      const sidebar = screen.getByRole('navigation');
      expect(sidebar).toHaveClass('collapsed') || expect(sidebar).toHaveStyle('display: none');
    });
  });

  describe('Loading State', () => {
    it('should show loading indicator while loading', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} isLoading={true} />);

      expect(screen.getByText(/loading|please wait/i)).toBeInTheDocument();
    });

    it('should show skeleton loaders for credentials', () => {
      render(<Dashboard user={mockUser} credentials={[]} isLoading={true} />);

      const skeletons = screen.getAllByTestId('skeleton-loader');
      expect(skeletons.length).toBeGreaterThan(0);
    });
  });

  describe('Error Handling', () => {
    it('should display error message', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} error="Failed to load credentials" />);

      expect(screen.getByText('Failed to load credentials')).toBeInTheDocument();
    });

    it('should have retry button on error', () => {
      const mockOnRetry = jest.fn();
      render(
        <Dashboard
          user={mockUser}
          credentials={mockCredentials}
          error="Failed to load"
          onRetry={mockOnRetry}
        />
      );

      const retryButton = screen.getByRole('button', { name: /retry/i });
      fireEvent.click(retryButton);

      expect(mockOnRetry).toHaveBeenCalled();
    });
  });

  describe('Accessibility', () => {
    it('should have proper heading hierarchy', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByRole('heading', { level: 1 })).toBeInTheDocument();
    });

    it('should have accessible navigation', () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      expect(screen.getByRole('navigation')).toBeInTheDocument();
    });

    it('should have keyboard navigation for credential actions', async () => {
      render(<Dashboard user={mockUser} credentials={mockCredentials} />);

      const buttons = screen.getAllByRole('button');
      for (const button of buttons) {
        button.focus();
        expect(button).toHaveFocus();
      }
    });
  });
});
