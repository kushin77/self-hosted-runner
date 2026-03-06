const express = require('express');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');

const app = express();
app.use(cors());
app.use(express.json());

// In-memory runner store (mimics portal Runner model)
const runners = [];

app.get('/api/runners', (req, res) => {
  res.json({ runners });
});

app.post('/api/runners', (req, res) => {
  const { name, labels } = req.body;
  if (!name) return res.status(400).json({ error: 'name is required' });
  const runner = { id: uuidv4(), name, labels: labels || [], createdAt: new Date().toISOString() };
  runners.push(runner);
  res.status(201).json(runner);
});

app.delete('/api/runners/:id', (req, res) => {
  const idx = runners.findIndex(r => r.id === req.params.id);
  if (idx === -1) return res.status(404).json({ error: 'not found' });
  const [removed] = runners.splice(idx, 1);
  res.json(removed);
});

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => console.log(`Portal runner server listening on port ${PORT}`));
