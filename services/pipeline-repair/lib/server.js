const express = require('express');
const bodyParser = require('body-parser');
const RepairService = require('./repair-service');

const app = express();
app.use(bodyParser.json());

const service = new RepairService();

app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.post('/analyze', async (req, res) => {
  try {
    const event = req.body || {};
    const result = await service.analyze(event);
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

if (require.main === module) {
  const port = process.env.PORT || 8081;
  app.listen(port, () => console.log(`repair-service HTTP API listening on ${port}`));
}

module.exports = app;
