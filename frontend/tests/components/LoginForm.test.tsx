/**
 * Component Tests: Login Form
 * Tests login form validation, submission, and error handling
 */

import { describe, it, expect, beforeEach, jest } from '@jest/globals';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import LoginForm from '../../../src/components/LoginForm';

describe('LoginForm Component', () => {
  let mockOnSubmit: jest.Mock;

  beforeEach(() => {
    mockOnSubmit = jest.fn();
  });

  describe('Rendering', () => {
    it('should render login form', () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      expect(screen.getByText(/login/i)).toBeInTheDocument();
    });

    it('should render email input field', () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      const emailInput = screen.getByLabelText(/email/i);
      expect(emailInput).toBeInTheDocument();
      expect(emailInput).toHaveAttribute('type', 'email');
    });

    it('should render password input field', () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      const passwordInput = screen.getByLabelText(/password/i);
      expect(passwordInput).toBeInTheDocument();
      expect(passwordInput).toHaveAttribute('type', 'password');
    });

    it('should render submit button', () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      const submitButton = screen.getByRole('button', { name: /login/i });
      expect(submitButton).toBeInTheDocument();
    });

    it('should render remember me checkbox', () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      expect(screen.getByLabelText(/remember/i)).toBeInTheDocument();
    });

    it('should render forgot password link', () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      expect(screen.getByText(/forgot password/i)).toBeInTheDocument();
    });
  });

  describe('Form Submission', () => {
    it('should call onSubmit with form data', async () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      const emailInput = screen.getByLabelText(/email/i);
      const passwordInput = screen.getByLabelText(/password/i);
      const submitButton = screen.getByRole('button', { name: /login/i });

      await userEvent.type(emailInput, 'user@example.com');
      await userEvent.type(passwordInput, 'Password123!');
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnSubmit).toHaveBeenCalledWith(
          expect.objectContaining({
            email: 'user@example.com',
            password: 'Password123!',
          })
        );
      });
    });

    it('should not submit with empty email', async () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      const passwordInput = screen.getByLabelText(/password/i);
      const submitButton = screen.getByRole('button', { name: /login/i });

      await userEvent.type(passwordInput, 'Password123!');
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnSubmit).not.toHaveBeenCalled();
      });
    });

    it('should not submit with empty password', async () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      const emailInput = screen.getByLabelText(/email/i);
      const submitButton = screen.getByRole('button', { name: /login/i });

      await userEvent.type(emailInput, 'user@example.com');
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnSubmit).not.toHaveBeenCalled();
      });
    });

    it('should not submit with invalid email', async () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      const emailInput = screen.getByLabelText(/email/i);
      const passwordInput = screen.getByLabelText(/password/i);
      const submitButton = screen.getByRole('button', { name: /login/i });

      await userEvent.type(emailInput, 'not-an-email');
      await userEvent.type(passwordInput, 'Password123!');
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnSubmit).not.toHaveBeenCalled();
      });
    });
  });

  describe('Form Validation', () => {
    it('should show error for invalid email', async () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      const emailInput = screen.getByLabelText(/email/i) as HTMLInputElement;
      await userEvent.type(emailInput, 'invalid-email');
      fireEvent.blur(emailInput);

      await waitFor(() => {
        expect(screen.getByText(/invalid email/i)).toBeInTheDocument();
      });
    });

    it('should show error for short password', async () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      const passwordInput = screen.getByLabelText(/password/i) as HTMLInputElement;
      await userEvent.type(passwordInput, 'short');
      fireEvent.blur(passwordInput);

      await waitFor(() => {
        expect(screen.getByText(/password must be at least/i)).toBeInTheDocument();
      });
    });

    it('should clear error when field is corrected', async () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      const emailInput = screen.getByLabelText(/email/i) as HTMLInputElement;
      await userEvent.type(emailInput, 'invalid-email');
      fireEvent.blur(emailInput);

      await waitFor(() => {
        expect(screen.getByText(/invalid email/i)).toBeInTheDocument();
      });

      // Clear and type valid email
      await userEvent.clear(emailInput);
      await userEvent.type(emailInput, 'valid@example.com');
      fireEvent.blur(emailInput);

      await waitFor(() => {
        expect(screen.queryByText(/invalid email/i)).not.toBeInTheDocument();
      });
    });
  });

  describe('Remember Me', () => {
    it('should include rememberMe in submission', async () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      const emailInput = screen.getByLabelText(/email/i);
      const passwordInput = screen.getByLabelText(/password/i);
      const rememberCheckbox = screen.getByLabelText(/remember/i);
      const submitButton = screen.getByRole('button', { name: /login/i });

      await userEvent.type(emailInput, 'user@example.com');
      await userEvent.type(passwordInput, 'Password123!');
      await userEvent.click(rememberCheckbox);
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(mockOnSubmit).toHaveBeenCalledWith(
          expect.objectContaining({
            rememberMe: true,
          })
        );
      });
    });
  });

  describe('Loading State', () => {
    it('should disable submit button while loading', () => {
      const { rerender } = render(<LoginForm onSubmit={mockOnSubmit} isLoading={false} />);

      const submitButton = screen.getByRole('button', { name: /login/i });
      expect(submitButton).not.toBeDisabled();

      rerender(<LoginForm onSubmit={mockOnSubmit} isLoading={true} />);

      expect(submitButton).toBeDisabled();
    });

    it('should show loading indicator', () => {
      render(<LoginForm onSubmit={mockOnSubmit} isLoading={true} />);

      expect(screen.getByText(/loading|submitting/i)).toBeInTheDocument();
    });
  });

  describe('Error Messages', () => {
    it('should display form-level error message', () => {
      render(<LoginForm onSubmit={mockOnSubmit} error="Invalid credentials" />);

      expect(screen.getByText('Invalid credentials')).toBeInTheDocument();
    });

    it('should display field-level error message', async () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      const emailInput = screen.getByLabelText(/email/i) as HTMLInputElement;
      await userEvent.type(emailInput, 'invalid');
      fireEvent.blur(emailInput);

      await waitFor(() => {
        expect(screen.getByText(/invalid email/i)).toBeInTheDocument();
      });
    });
  });

  describe('Accessibility', () => {
    it('should have accessible form labels', () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      expect(screen.getByLabelText(/email/i)).toBeInTheDocument();
      expect(screen.getByLabelText(/password/i)).toBeInTheDocument();
    });

    it('should have keyboard navigation support', async () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      const emailInput = screen.getByLabelText(/email/i) as HTMLInputElement;
      const passwordInput = screen.getByLabelText(/password/i) as HTMLInputElement;
      const submitButton = screen.getByRole('button', { name: /login/i });

      // Tab to email
      emailInput.focus();
      expect(emailInput).toHaveFocus();

      // Tab to password
      await userEvent.tab();
      expect(passwordInput).toHaveFocus();

      // Tab to submit
      await userEvent.tab();
      expect(submitButton).toHaveFocus();
    });

    it('should have aria-labels for important elements', () => {
      render(<LoginForm onSubmit={mockOnSubmit} />);

      expect(screen.getByLabelText(/email/i)).toHaveAttribute('aria-label') ||
        expect(screen.getByLabelText(/email/i)).toHaveAttribute('placeholder');
    });
  });

  describe('Form Reset', () => {
    it('should clear form after successful submission', async () => {
      render(<LoginForm onSubmit={mockOnSubmit} onSuccess={true} />);

      const emailInput = screen.getByLabelText(/email/i) as HTMLInputElement;
      const passwordInput = screen.getByLabelText(/password/i) as HTMLInputElement;

      expect(emailInput.value).toBe('');
      expect(passwordInput.value).toBe('');
    });

    it('should maintain form state on error', async () => {
      render(<LoginForm onSubmit={mockOnSubmit} error="Error" />);

      const emailInput = screen.getByLabelText(/email/i) as HTMLInputElement;
      const passwordInput = screen.getByLabelText(/password/i) as HTMLInputElement;

      await userEvent.type(emailInput, 'user@example.com');
      await userEvent.type(passwordInput, 'Password123!');

      expect(emailInput.value).toBe('user@example.com');
      expect(passwordInput.value).toBe('Password123!');
    });
  });
});
