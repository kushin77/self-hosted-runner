import { test as setup, chromium } from '@playwright/test';

/**
 * Global setup for E2E tests
 * This runs once before all tests start
 */
async function globalSetup() {
  console.log('🔧 Running global setup...');

  const baseURL = process.env.API_BASE_URL || 'http://localhost:3000';
  
  // Check if the mock server is running
  try {
    const response = await fetch(`${baseURL}/health`);
    if (!response.ok) {
      console.warn(`⚠️  Mock server health check failed: ${response.status}`);
    } else {
      console.log('✅ Mock server is running');
    }
  } catch (error) {
    console.warn(`⚠️  Cannot connect to mock server at ${baseURL}`);
    console.warn('Make sure to start the mock server before running tests:');
    console.warn('  WORKER_HOST=<hostname> node tests/e2e/mock-server.js');
  }

  // Check for required environment variables
  const requiredEnvVars = ['WORKER_HOST'];
  const missingEnvVars = requiredEnvVars.filter(v => !process.env[v]);
  
  if (missingEnvVars.length > 0) {
    console.warn(`⚠️  Missing environment variables: ${missingEnvVars.join(', ')}`);
  }

  console.log('✅ Global setup complete');
}

export default globalSetup;
