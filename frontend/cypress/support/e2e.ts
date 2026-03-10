// Cypress support file
import './commands'

Cypress.on('uncaught:exception', (err, runnable) => {
  return false
})
