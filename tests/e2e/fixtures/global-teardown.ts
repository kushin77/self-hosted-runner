/**
 * Global teardown for E2E tests
 * This runs once after all tests complete
 */
async function globalTeardown() {
  console.log('🔧 Running global teardown...');
  
  // Clean up any test artifacts
  // Note: We keep reports for analysis
  
  console.log('✅ Global teardown complete');
}

export default globalTeardown;
