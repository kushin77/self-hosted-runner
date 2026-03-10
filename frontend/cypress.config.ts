import { defineConfig } from 'cypress'

export default defineConfig({
  e2e: {
    baseUrl: process.env.CYPRESS_BASE_URL || process.env.REACT_APP_API_URL || 'http://localhost:5173',
    specPattern: 'cypress/e2e/**/*.cy.{js,ts}' ,
    supportFile: 'cypress/support/e2e.ts',
    setupNodeEvents(on, config) {
      return config
    }
  },
  video: false,
  screenshotsFolder: 'cypress/screenshots'
})
