---
layout: doc
title: Examples
description: Implementation examples for x401 agent authorization
permalink: /examples
---

# Examples

Standalone implementation examples for x401. All code lives in the [`examples/`](https://github.com/Shehryar/x401/tree/main/examples) directory.

---

## Server: Verify Agent Authorization

Add x401 verification to any Express endpoint with a single middleware call.

```typescript
import { verifyACT } from '@x401/verify';

// One line to protect any endpoint
app.get('/api/data',
  verifyACT({ require: 'https://api.example.com/data:read' }),
  (req, res) => {
    res.json({ data: getMarketData(), authorized_by: req.act.sub });
  }
);
```

The middleware decodes the ACT from the `Authorization` header, verifies the signature chain, checks capabilities and limits, and either passes the request through or returns HTTP 401.

[Full example: `examples/server/express-middleware.ts`](https://github.com/Shehryar/x401/blob/main/examples/server/express-middleware.ts)

---

## Agent: Three Integration Paths

### Path 1 — HTTP API (Zero Dependencies)

Any agent can request authorization using plain HTTP. No SDK, no dependencies.

```bash
# Request authorization
curl -X POST https://api.x401.dev/authorize \
  -H "Content-Type: application/json" \
  -d '{
    "agent_did": "did:key:z6MkAgent...",
    "cap": [
      { "uri": "github:acme/backend/push:branch:staging", "lim": { "cnt": 20, "per": 86400 } }
    ],
    "reason": "Deploy hotfix",
    "exp": 86400
  }'

# Poll until human approves
curl https://api.x401.dev/poll/abc123
# → { "status": "authorized", "act": "eyJhbGciOiJFZERTQSIs..." }

# Use the ACT
curl https://api.example.com/data \
  -H "Authorization: ACT eyJhbGciOiJFZERTQSIs..."
```

[Full example: `examples/agent/http-api.sh`](https://github.com/Shehryar/x401/blob/main/examples/agent/http-api.sh)

### Path 2 — CLI (Shell Out)

Any agent framework can shell out to the `x401` CLI for authorization flows and proof generation.

```bash
# Interactive: opens browser, waits for approval, prints ACT to stdout
x401 authorize \
  --cap "github:acme/backend/push:branch:staging" \
  --lim "cnt:20,per:86400" \
  --exp 24h \
  --reason "Deploy hotfix"

# Pre-signed: create ACT offline for CI/CD
x401 grant \
  --to did:key:zQ3shAgent... \
  --cap "solana:mainnet/spl:EPjFW.../transfer" \
  --limit "amt:100000000,per:86400" \
  --exp 24h \
  --sign-with ~/.x401/key.json \
  --output act.jwt
```

[Full example: `examples/agent/cli.sh`](https://github.com/Shehryar/x401/blob/main/examples/agent/cli.sh)

### Path 3 — SDK (Deep Integration)

The SDK handles proof-of-possession automatically on every request. Auth becomes transparent.

```typescript
import { X401Client } from '@x401/sdk';

const client = new X401Client({ act: myACT, privateKey: agentKey });

// Proof generated and attached automatically
const response = await client.fetch('https://gateway.x401.dev/gmail/send', {
  method: 'POST',
  body: JSON.stringify({ to: 'bob@co.com', subject: 'Update', body: '...' }),
});
```

[Full example: `examples/agent/sdk-client.ts`](https://github.com/Shehryar/x401/blob/main/examples/agent/sdk-client.ts)

---

## On-Chain Verification

### Solana (Anchor/Rust)

Smart contracts verify ACTs natively on Solana using the Ed25519 native program. ~5,000-6,000 compute units for a 2-signature delegation chain.

```rust
pub fn verify_and_execute(
    ctx: Context<VerifyAndExecute>,
    act_data: ACTData,
    human_sig: [u8; 64],
    agent_sig: [u8; 64],
) -> Result<()> {
    let clock = Clock::get()?;

    require!(!ctx.accounts.act_state.revoked, X401Error::Revoked);
    require!(clock.unix_timestamp <= act_data.exp, X401Error::Expired);

    // Verify delegation chain (~2,280 CU per signature)
    verify_ed25519(&ctx.accounts.human.key(), &delegation_msg, &human_sig)?;
    verify_ed25519(&ctx.accounts.agent.key(), &payload_msg, &agent_sig)?;

    // Enforce spending limits with per-capability counters
    let state = &mut ctx.accounts.act_state;
    state.spent = state.spent.checked_add(act_data.amount)
        .ok_or(X401Error::Overflow)?;
    require!(state.spent <= state.max_amount, X401Error::ExceedsLimit);

    transfer_spl_tokens(ctx, act_data.amount)?;
    Ok(())
}
```

[Full example: `examples/onchain/solana-verifier.rs`](https://github.com/Shehryar/x401/blob/main/examples/onchain/solana-verifier.rs)

### EVM/Base (Solidity)

Per-capability counters on EVM that enforce quantitative limits. Gasless on Base via paymasters. Off-chain services can read the chain for a global source of truth on agent usage.

```solidity
function increment(
    bytes32 jti,
    bytes32 capHash,
    uint256 count
) external returns (uint256 remaining) {
    LimitAccount storage acc = limits[jti];
    require(!acc.revoked, "revoked");
    require(msg.sender == acc.agent, "unauthorized");

    // Reset period if expired
    CapabilityCounter storage ctr = counters[keccak256(abi.encodePacked(jti, capHash))];
    if (block.timestamp >= ctr.periodStart + ctr.periodLength) {
        ctr.currentCount = 0;
        ctr.periodStart = block.timestamp;
    }

    ctr.currentCount += count;
    require(ctr.currentCount <= ctr.maxCount, "limit exceeded");
    return ctr.maxCount - ctr.currentCount;
}
```

[Full example: `examples/onchain/evm-limit-enforcer.sol`](https://github.com/Shehryar/x401/blob/main/examples/onchain/evm-limit-enforcer.sol)

---

## Token Structure

### Agent Capability Token (ACT)

A signed JWT carrying capabilities, quantitative limits, delegation chain, and expiry.

```json
{
  "iss": "did:key:zQ3shAgent...",
  "sub": "did:key:zQ3shHuman...",
  "exp": 1740672154,
  "jti": "0xdeadbeef1234567890abcdef",
  "cap": [
    {
      "uri": "solana:mainnet/spl:EPjFW.../transfer",
      "lim": { "amt": "100000000", "per": 86400 }
    },
    {
      "uri": "gmail:alice@example.com/send:domain:example.com",
      "lim": { "cnt": 50, "per": 86400 }
    },
    {
      "uri": "github:acme/backend/push:branch:staging",
      "lim": { "cnt": 20, "per": 86400 }
    }
  ],
  "dlg": {
    "iss": "did:key:zQ3shHuman...",
    "sig": "base64-ed25519-sig...",
    "cap": [
      { "uri": "solana:mainnet/spl:EPjFW.../transfer", "lim": { "amt": "500000000", "per": 86400 } },
      { "uri": "gmail:alice@example.com/send", "lim": { "cnt": 200, "per": 86400 } },
      { "uri": "github:acme/*/push", "lim": { "cnt": 100, "per": 86400 } }
    ]
  },
  "rsn": "Daily portfolio rebalancing and status reporting"
}
```

[Full example: `examples/tokens/act-example.json`](https://github.com/Shehryar/x401/blob/main/examples/tokens/act-example.json)

### Proof of Possession

A short-lived JWT proving the agent holds its private key. Bound to the specific request.

```json
{
  "typ": "act-pop+jwt",
  "ath": "sha256-of-the-ACT",
  "htm": "POST",
  "htu": "https://gateway.x401.dev/gmail/send",
  "htb": "sha256-of-request-body",
  "iat": 1708300000,
  "jti": "unique-nonce-abc123"
}
```

[Full example: `examples/tokens/proof-of-possession.json`](https://github.com/Shehryar/x401/blob/main/examples/tokens/proof-of-possession.json)

---

## Capability URI Examples

x401 uses a universal capability URI scheme across all services. One grammar, everywhere.

```
# On-chain (CAIP-2)
solana:mainnet/spl:EPjFW.../transfer
eip155:8453/erc20:0x833589.../transfer
solana:mainnet/program:JUP6Lk.../call:route

# Email
gmail:alice@example.com/send:domain:example.com
gmail:alice@example.com/read:label:inbox

# Code
github:acme/backend/push:branch:staging
github:acme/*/read

# Messaging
slack:acme/post:engineering
slack:acme/dm:bob@acme.com

# Calendar
gcal:alice@example.com/create
gcal:alice@example.com/read

# APIs
https://api.example.com/data:read
https://api.example.com/data:write

# Healthcare
fhir:hospital/Patient/123/DiagnosticReport:read
```

## Quantitative Limits

First-class primitives in every token. The human defines the budget.

```json
{ "amt": "100000000", "per": 86400 }                    // 100 USDC/day
{ "amt": "100000000", "per": 86400, "tx": "50000000" }  // 100/day, 50 max per swap
{ "cnt": 50, "per": 86400 }                              // 50 actions/day
{ "cnt": 1 }                                              // one-shot
{ "rate": [1000, 3600] }                                  // 1000 requests/hour
{ "cost": "50000", "cur": "USD", "per": 86400 }          // $500/day
```
