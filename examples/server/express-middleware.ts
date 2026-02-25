/**
 * x401 Express.js Middleware Example
 *
 * Verify agent authorization on any Express endpoint with a single middleware call.
 * The middleware decodes the ACT from the Authorization header, verifies the signature
 * chain, checks capabilities and limits, and either passes the request through or
 * returns HTTP 401.
 */

import express from 'express';
import { verifyACT } from '@x401/verify';

const app = express();
app.use(express.json());

// ── Public endpoint — no authorization needed ──

app.get('/api/status', (req, res) => {
  res.json({ status: 'ok' });
});

// ── Protected endpoint — requires ACT with read capability ──

app.get('/api/data',
  verifyACT({ require: 'https://api.example.com/data:read' }),
  (req, res) => {
    // req.act contains the verified token
    // req.act.sub — the human who authorized the agent
    // req.act.iss — the agent's identity
    res.json({
      data: getMarketData(),
      authorized_by: req.act.sub,
    });
  }
);

// ── Protected POST — proof-of-possession verifies body hash ──

app.post('/api/data',
  verifyACT({ require: 'https://api.example.com/data:write' }),
  (req, res) => {
    updateData(req.body);
    res.json({ success: true });
  }
);

// ── Internal endpoint — opt out of proof for trusted networks ──

app.get('/internal/status',
  verifyACT({
    require: 'internal:status',
    requireProof: false,
  }),
  (req, res) => res.json({ status: 'ok' })
);

// ── Middleware configuration options ──

app.get('/api/advanced',
  verifyACT({
    require: 'https://api.example.com/data:read',
    audience: 'https://api.example.com',  // verify the ACT is intended for this service
    maxChainDepth: 3,                      // max delegation hops
    requireProof: true,                    // require proof-of-possession (default)
  }),
  (req, res) => res.json({ ok: true })
);

app.listen(3000, () => {
  console.log('Server running on :3000');
});
