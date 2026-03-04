#!/usr/bin/env node
const express = require('express');
const url = require('url');
const app = express();
const port = process.env.PORT || 4000;

app.get('/', (req, res) => res.send('RunnerCloud Managed Auth Skeleton'));

// Redirect user to GitHub OAuth (placeholder)
app.get('/auth/github', (req, res) => {
  // In real impl: redirect to https://github.com/login/oauth/authorize?client_id=...
  res.redirect('https://github.com/login/oauth/authorize?client_id=YOUR_CLIENT_ID&scope=repo');
});

// OAuth callback (placeholder)
app.get('/auth/github/callback', (req, res) => {
  // In real impl: exchange code for token, register runner, create user session
  const q = url.parse(req.url, true).query;
  res.json({ message: 'OAuth callback received (skeleton)', query: q });
});

app.listen(port, () => console.log(`Managed Auth skeleton listening on ${port}`));
