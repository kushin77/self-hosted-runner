const express = require('express');
const cors = require('cors');
const data = require('./data');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3001;

app.get('/api/runners', (req, res) => {
  res.json(data.runners);
});

app.get('/api/events', (req, res) => {
  res.json(data.events);
});

app.get('/api/billing', (req, res) => {
  res.json(data.billing);
});

app.get('/api/cache', (req, res) => {
  res.json(data.cache);
});

app.get('/api/ai', (req, res) => {
  res.json(data.ai);
});

app.get('/api/agents', (req, res) => {
  res.json(data.agents);
});

app.listen(PORT, () => {
  console.log(`Portal mock server listening at http://localhost:${PORT}`);
});
