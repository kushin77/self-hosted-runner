describe('NexusShield Portal E2E', () => {
  it('loads the dashboard and shows overview', () => {
    cy.visit('/')
    cy.contains('NexusShield Portal')
    cy.get('button').contains('Overview')
  })

  it('navigates to Credentials and lists items', () => {
    cy.visit('/')
    cy.contains('Credentials').click()
    cy.get('table').should('exist')
  })

  it('navigates to Audit and verifies integrity button exists', () => {
    cy.visit('/')
    cy.contains('Audit').click()
    cy.contains('Verify Integrity')
  })
})
