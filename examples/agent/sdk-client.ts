/**
 * x401 Agent Integration — SDK (Deep Integration)
 *
 * The SDK handles proof-of-possession generation automatically on every request.
 * Wrap your agent's HTTP calls with the X401Client and auth is transparent.
 */

import { X401Client, Agent } from '@x401/sdk';

// ── Basic usage ──

const client = new X401Client({
  act: myACT,           // the signed ACT JWT
  privateKey: agentKey,  // agent's private key for proof generation
});

// Proof generated and attached automatically on every request
const response = await client.fetch('https://gateway.x401.dev/gmail/send', {
  method: 'POST',
  body: JSON.stringify({
    to: 'bob@company.com',
    subject: 'Daily update',
    body: '...',
  }),
});


// ── Request authorization from human ──

const agent = new Agent({ keyfile: './agent-key.json' });

const act = await agent.requestAuthorization({
  capabilities: [
    {
      uri: 'github:acme/backend/push:branch:staging',
      lim: { cnt: 20, per: 86400 },
    },
    {
      uri: 'gmail:alice@example.com/send:domain:example.com',
      lim: { cnt: 50, per: 86400 },
    },
  ],
  reason: 'Deploy hotfix and notify team',
  expiry: '24h',
  // consent mode: 'interactive' | 'device' | 'agent-native' | 'pre-signed'
  mode: 'device',
});

// act is now a signed JWT ready to use


// ── Sub-delegation ──

const orchestratorACT = await agent.loadACT('./act.jwt');

// Delegate narrower permissions to a worker agent
const workerACT = agent.delegate(orchestratorACT, {
  to: 'did:key:z6MkWorker...',
  capabilities: [
    {
      uri: 'solana:mainnet/program:JUP6Lk.../call:route',
      lim: { amt: '100000000', per: 86400, tx: '50000000' },
    },
  ],
  reason: 'DCA execution — SOL-USDC only',
});

// Worker carries this ACT. Any service verifies the full chain:
// Human (500 USDC/day) → Orchestrator (500 USDC/day) → Worker (100 USDC/day, 50/swap)
