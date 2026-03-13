/**
 * Specification Inventory
 * Defines all API endpoints, CLI functions, and UI elements that need test coverage
 */

export interface SpecItem {
  id: string;
  name: string;
  category: string;
  description: string;
  testStatus?: 'complete' | 'partial' | 'untested' | 'missing';
  testId?: string;
}

/**
 * API Endpoints that need test coverage
 */
export const API_ENDPOINTS: SpecItem[] = [
  // Auth endpoints
  { id: 'api-auth-login', name: 'POST /api/v1/auth/login', category: 'api', description: 'User login endpoint' },
  { id: 'api-auth-validate', name: 'POST /api/v1/auth/validate', category: 'api', description: 'Validate token endpoint' },
  { id: 'api-auth-refresh', name: 'POST /api/v1/auth/refresh', category: 'api', description: 'Refresh token endpoint' },

  // Credentials endpoints
  { id: 'api-credentials-list', name: 'GET /api/v1/credentials', category: 'api', description: 'List all credentials' },
  { id: 'api-credentials-create', name: 'POST /api/v1/credentials', category: 'api', description: 'Create new credential' },
  { id: 'api-credentials-get', name: 'GET /api/v1/credentials/:id', category: 'api', description: 'Get credential by ID' },
  { id: 'api-credentials-update', name: 'PUT /api/v1/credentials/:id', category: 'api', description: 'Update credential' },
  { id: 'api-credentials-delete', name: 'DELETE /api/v1/credentials/:id', category: 'api', description: 'Delete credential' },
  { id: 'api-credentials-rotate', name: 'POST /api/v1/credentials/:id/rotate', category: 'api', description: 'Rotate credential' },
  { id: 'api-credentials-rotations', name: 'GET /api/v1/credentials/:id/rotations', category: 'api', description: 'Get rotation history' },

  // Audit endpoints
  { id: 'api-audit-list', name: 'GET /api/v1/audit', category: 'api', description: 'List audit entries' },
  { id: 'api-audit-verify', name: 'POST /api/v1/audit/verify', category: 'api', description: 'Verify audit trail' },

  // Health check
  { id: 'api-health', name: 'GET /health', category: 'api', description: 'Health check endpoint' },
];

/**
 * CLI Functions that need test coverage
 */
export const CLI_FUNCTIONS: SpecItem[] = [
  { id: 'cli-help', name: '--help', category: 'cli', description: 'Display help information' },
  { id: 'cli-version', name: '--version', category: 'cli', description: 'Display version information' },
  { id: 'cli-init', name: 'init', category: 'cli', description: 'Initialize configuration' },
  { id: 'cli-deploy', name: 'deploy', category: 'cli', description: 'Deploy resources' },
  { id: 'cli-destroy', name: 'destroy', category: 'cli', description: 'Destroy resources' },
  { id: 'cli-status', name: 'status', category: 'cli', description: 'Check deployment status' },
  { id: 'cli-logs', name: 'logs', category: 'cli', description: 'View logs' },
  { id: 'cli-config', name: 'config', category: 'cli', description: 'Manage configuration' },
];

/**
 * UI Elements that need test coverage
 */
export const UI_ELEMENTS: SpecItem[] = [
  // Login page
  { id: 'ui-login-form', name: 'Login Form', category: 'ui', description: 'User login form' },
  { id: 'ui-login-button', name: 'Login Button', category: 'ui', description: 'Submit login button' },
  { id: 'ui-login-error', name: 'Login Error Message', category: 'ui', description: 'Error message display' },

  // Dashboard
  { id: 'ui-dashboard-overview', name: 'Dashboard Overview', category: 'ui', description: 'Main dashboard view' },
  { id: 'ui-dashboard-stats', name: 'Dashboard Statistics', category: 'ui', description: 'Statistics display' },

  // Credentials management
  { id: 'ui-credentials-list', name: 'Credentials List', category: 'ui', description: 'List credentials table' },
  { id: 'ui-credentials-create', name: 'Create Credential Form', category: 'ui', description: 'Create credential form' },
  { id: 'ui-credentials-edit', name: 'Edit Credential Form', category: 'ui', description: 'Edit credential form' },
  { id: 'ui-credentials-delete', name: 'Delete Credential', category: 'ui', description: 'Delete credential action' },
  { id: 'ui-credentials-rotate', name: 'Rotate Credential', category: 'ui', description: 'Rotate credential action' },

  // Audit log
  { id: 'ui-audit-list', name: 'Audit Log Table', category: 'ui', description: 'Audit log display' },
  { id: 'ui-audit-filter', name: 'Audit Log Filter', category: 'ui', description: 'Filter audit entries' },

  // Navigation
  { id: 'ui-nav-main', name: 'Main Navigation', category: 'ui', description: 'Main navigation menu' },
  { id: 'ui-nav-sidebar', name: 'Sidebar Navigation', category: 'ui', description: 'Sidebar navigation' },
];
