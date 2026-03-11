#!/usr/bin/env node
const { Probot } = require('@probot/framework')
const { Octokit } = require('@octokit/rest')

const app = new Probot({})

app.load((app) => {
  // Delete releases when created/published
  app.on(['release.created', 'release.published'], async (context) => {
    const { owner, repo } = context.repo()
    const releaseId = context.payload.release && context.payload.release.id
    if (!releaseId) return
    try {
      await context.octokit.rest.repos.deleteRelease({ owner, repo, release_id: releaseId })
      await context.octokit.rest.issues.create({
        owner,
        repo,
        title: `Automated removal: release ${context.payload.release.tag_name}`,
        body: `A release (id: ${releaseId}, tag: ${context.payload.release.tag_name}) was automatically removed by repository governance. Releases are disallowed.`
      })
    } catch (err) {
      app.log && app.log.error && app.log.error(err)
    }
  })

  // Delete tags when created (create event with ref_type=tag)
  app.on('create', async (context) => {
    const { ref_type, ref } = context.payload
    const { owner, repo } = context.repo()
    if (ref_type !== 'tag') return
    try {
      // delete ref: refs/tags/<tag>
      await context.octokit.rest.git.deleteRef({ owner, repo, ref: `tags/${ref}` })
      await context.octokit.rest.issues.create({
        owner,
        repo,
        title: `Automated removal: tag ${ref}`,
        body: `A tag (${ref}) was automatically removed by repository governance. Tag pushes are disallowed.`
      })
    } catch (err) {
      app.log && app.log.error && app.log.error(err)
    }
  })
})

app.start().catch((err) => {
  console.error(err)
  process.exit(1)
})
