#!/usr/bin/env node
const express = require('express');
const crypto = require('crypto');
const { Octokit } = require('octokit');

const app = express();
const port = process.env.PORT || 3000;

app.use(express.json());

// Initialize Octokit with token from environment (will be fetched from GSM at runtime)
const getOctokit = () => {
  const token = process.env.GITHUB_TOKEN;
  if (!token) throw new Error('GITHUB_TOKEN not set');
  return new Octokit({ auth: token });
};

// Webhook signature verification
const verifySignature = (req, secret) => {
  const signature = req.headers['x-hub-signature-256'];
  if (!signature) return false;
  const hash = crypto.createHmac('sha256', secret).update(JSON.stringify(req.body)).digest('hex');
  return crypto.timingSafeEqual(`sha256=${hash}`, signature);
};

// Webhook endpoint
app.post('/api/webhooks', (req, res) => {
  const secret = process.env.GITHUB_WEBHOOK_SECRET;
  if (!secret || !verifySignature(req, secret)) {
    return res.status(401).send('Unauthorized');
  }

  const event = req.headers['x-github-event'];
  const { action, repository, release, ref, ref_type } = req.body;

  if (!repository) return res.status(400).send('No repository');

  const { owner, repo } = repository;
  const octokit = getOctokit();

  (async () => {
    try {
      if (event === 'release' && (action === 'created' || action === 'published')) {
        const releaseId = release.id;
        const tagName = release.tag_name;
        console.log(`Removing release: ${tagName}`);

        await octokit.rest.repos.deleteRelease({ owner: owner.login, repo, release_id: releaseId });
        await octokit.rest.issues.create({
          owner: owner.login,
          repo,
          title: `Auto-removal: release ${tagName}`,
          body: `Release '${tagName}' was automatically removed by repository governance policy (releases disallowed).`,
        });
      }

      if (event === 'create' && ref_type === 'tag') {
        console.log(`Removing tag: ${ref}`);
        await octokit.rest.git.deleteRef({ owner: owner.login, repo, ref: `tags/${ref}` });
        await octokit.rest.issues.create({
          owner: owner.login,
          repo,
          title: `Auto-removal: tag ${ref}`,
          body: `Tag '${ref}' was automatically removed by repository governance policy (tags disallowed).`,
        });
      }
    } catch (err) {
      console.error(err);
    }
  })();

  res.status(200).send('OK');
});

// Poll endpoint for scheduled enforcement (no GitHub signature required).
// This is intended to be called from Cloud Scheduler using OIDC service account.
app.post('/api/poll', async (req, res) => {
  try {
    const octokit = getOctokit();
    // List releases for the repo provided in request body or default to env override
    const owner = req.body?.owner || process.env.POLL_OWNER;
    const repo = req.body?.repo || process.env.POLL_REPO;
    if (!owner || !repo) return res.status(400).send('owner and repo required');

    // Remove releases
    const releases = await octokit.rest.repos.listReleases({ owner, repo, per_page: 100 });
    for (const r of releases.data) {
      try {
        console.log(`Polling removal: release ${r.tag_name} (${r.id})`);
        await octokit.rest.repos.deleteRelease({ owner, repo, release_id: r.id });
        await octokit.rest.issues.create({ owner, repo, title: `Auto-removal: release ${r.tag_name}`, body: `Release '${r.tag_name}' removed by governance poll.` });
      } catch (err) {
        console.error('release delete error', err.message || err);
      }
    }

    // Remove tags
    const refs = await octokit.rest.git.listRefs({ owner, repo, per_page: 100 });
    for (const ref of refs.data) {
      if (ref.ref && ref.ref.startsWith('refs/tags/')) {
        const tag = ref.ref.replace('refs/tags/', '');
        try {
          console.log(`Polling removal: tag ${tag}`);
          await octokit.rest.git.deleteRef({ owner, repo, ref: `tags/${tag}` });
          await octokit.rest.issues.create({ owner, repo, title: `Auto-removal: tag ${tag}`, body: `Tag '${tag}' removed by governance poll.` });
        } catch (err) {
          console.error('tag delete error', err.message || err);
        }
      }
    }

    return res.status(200).send('Poll complete');
  } catch (err) {
    console.error('poll error', err.message || err);
    return res.status(500).send('poll failed');
  }
});

// Reminder endpoint: create an issue prompting rotation of the GitHub token
// Intended to be called by Cloud Scheduler (OIDC-authenticated service account)
app.post('/api/reminder', async (req, res) => {
  try {
    const octokit = getOctokit();
    const owner = req.body?.owner || process.env.POLL_OWNER;
    const repo = req.body?.repo || process.env.POLL_REPO;
    const frequency = req.body?.frequency || 'weekly';
    if (!owner || !repo) return res.status(400).send('owner and repo required');

    const title = `Rotation reminder: rotate github-token (${frequency})`;
    const body = `This is an automated reminder to rotate the repository GitHub token stored in GSM (secret: \`github-token\`).\n\nFollow the playbook in docs/ROTATE_GITHUB_TOKEN.md to perform rotation and verification.\n\nIf rotation is already scheduled or performed, close this issue.`;

    const issue = await octokit.rest.issues.create({ owner, repo, title, body });
    console.log(`Created rotation reminder issue: ${issue.data.html_url}`);
    return res.status(200).json({ url: issue.data.html_url });
  } catch (err) {
    console.error('reminder error', err.message || err);
    return res.status(500).send('reminder failed');
  }
});

app.get('/health', (req, res) => {
  res.status(200).send('OK');
});

app.listen(port, () => {
  console.log(`Prevent-releases GitHub App listening on port ${port}`);
});

