const express = require('express');
const bodyParser = require('body-parser');
const RepairService = require('./repair-service');
const approvals = require('./approvals');

const app = express();
app.use(bodyParser.json());

const approvalThreshold = parseFloat(process.env.REPAIR_APPROVAL_THRESHOLD || '0.7');
const service = new RepairService({ threshold: approvalThreshold });

app.get('/health', (req, res) => res.json({ status: 'ok' }));

/**
 * POST /analyze - Analyze a failure event and identify repair strategy
 */
app.post('/analyze', async (req, res) => {
  try {
    const event = req.body || {};
    const result = await service.analyze(event);

    // Allow test harness to force approval for specific events
    if (event.forceApproval) result.requiresApproval = true;

    // If recommendation requires approval, check if an approval exists for this event
    if (result.requiresApproval) {
      if (event.id && approvals.hasApproval(event.id)) {
        // Attach approval info and return recommendation
        result.approval = approvals.getApproval(event.id);
        res.json(result);
      } else {
        res.status(202).json({ status: 'PENDING_APPROVAL', recommendation: result.recommendation });
      }
      return;
    }

    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Approval endpoints (simple API-key protected)
app.post('/approve', (req, res) => {
  const apiKey = req.header('X-API-Key') || '';
  const adminKey = process.env.ADMIN_API_KEY || '';
  if (adminKey && apiKey !== adminKey) return res.status(403).json({ error: 'forbidden' });

  const { eventId, approver, note } = req.body || {};
  if (!eventId) return res.status(400).json({ error: 'missing eventId' });

  approvals.addApproval(eventId, { approver: approver || 'manual', note: note || '', at: new Date().toISOString() });
  res.json({ status: 'approved', eventId });
});

app.get('/approvals', (req, res) => res.json(approvals.list()));

/**
 * POST /approve - Approve a pending repair request
 */
app.post('/approve', async (req, res) => {
  try {
    const { eventId, approver, reason } = req.body;
    
    if (!eventId || !approver) {
      return res.status(400).json({ 
        error: 'Missing required fields: eventId, approver' 
      });
    }

    const result = await service.approvalEngine.approveRepair(eventId, approver, reason);
    res.json(result);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

/**
 * POST /reject - Reject a pending repair request
 */
app.post('/reject', async (req, res) => {
  try {
    const { eventId, rejector, reason } = req.body;
    
    if (!eventId || !rejector) {
      return res.status(400).json({ 
        error: 'Missing required fields: eventId, rejector' 
      });
    }

    const result = await service.approvalEngine.rejectRepair(eventId, rejector, reason);
    res.json(result);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

/**
 * GET /approval-status/:eventId - Check approval status for event
 */
app.get('/approval-status/:eventId', (req, res) => {
  try {
    const { eventId } = req.params;
    const status = service.approvalEngine.getApprovalStatus(eventId);
    res.json(status);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /execute - Execute an approved repair action
 */
app.post('/execute', async (req, res) => {
  try {
    const { eventId, approvalId } = req.body;
    
    if (!eventId) {
      return res.status(400).json({ error: 'Missing required field: eventId' });
    }

    const result = await service.executeRepair(eventId, approvalId);
    res.json(result);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

/**
 * GET /strategies - List available repair strategies
 */
app.get('/strategies', (req, res) => {
  try {
    const strategies = service.getStrategies();
    res.json({ strategies });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

if (require.main === module) {
  const port = process.env.PORT || 8081;
  app.listen(port, () => console.log(`repair-service HTTP API listening on ${port}`));
}

module.exports = app;
