#!/usr/bin/env node
// AI Failure Oracle service prototype
// Accepts job logs, forwards to Claude API (simulated), stores result
// Issue #10

import express from 'express';
import fetch from 'node-fetch';
const app = express();
const port = process.env.PORT || 4101;
app.use(express.json());

// in-memory store for analyses
const analyses = [];

// health
app.get('/health', (req, res) => res.send('ok'));

// submit logs for analysis
app.post('/analyze', async (req, res) => {
  const { jobId, logs } = req.body || {};
  if (!jobId || !logs) return res.status(400).json({ error: 'jobId and logs required' });

  // call Claude API - for now simulate
  let rootCause = 'unknown';
  let confidence = 0.5;
  if (logs.includes('ERROR')) {
    rootCause = 'runtime error detected';
    confidence = 0.85;
  }

  const result = { jobId, rootCause, confidence, timestamp: new Date().toISOString() };
  analyses.push(result);

  // optionally post to GitHub comment (omitted)

  res.json(result);
});

// list recent analyses
app.get('/results', (req, res) => {
  res.json(analyses.slice(-10));
});

app.listen(port, () => console.log(`AI Oracle service listening on ${port}`));
