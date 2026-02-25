# x401

An open standard for internet-native agent authorization.

x401 lets AI agents carry verifiable, scoped proof of human authorization. One token format that works on-chain and off-chain. No centralized vault, no per-service API keys, no human in the loop per request.

## the problem

agents are taking actions everywhere — sending emails, pushing code, making trades, calling APIs. but there's no standard way for an agent to prove *what* it's authorized to do.

OAuth requires a human to click "Allow." API keys are skeleton keys with no scoping. token vaults are single points of failure. every service invented its own authorization model. none of them compose across services, carry quantitative limits, or support delegation chains.

## what x401 does

the human signs one authorization with scoped capabilities. the agent carries it as a self-contained token. any service verifies locally.

```
POST /gmail/send HTTP/1.1
Authorization: ACT eyJhbGciOiJFZERTQSIs...
```

the token carries everything: who authorized the agent, what it can do, spending limits, expiry, the full delegation chain. verification is a local crypto check — no callbacks, no external dependencies.

## quick start

### verify agent authorization (server)

```bash
npm install @x401/verify
```

```typescript
import { verifyACT } from '@x401/verify';

app.get('/api/data',
  verifyACT({ require: 'https://api.example.com/data:read' }),
  (req, res) => {
    // req.act.sub — the human who authorized the agent
    // req.act.iss — the agent's identity
    res.json({ data: getMarketData() });
  }
);
```

### request authorization (agent)

```bash
# HTTP API — zero dependencies
curl -X POST https://api.x401.dev/authorize \
  -H "Content-Type: application/json" \
  -d '{
    "agent_did": "did:key:z6MkAgent...",
    "cap": [
      { "uri": "github:acme/backend/push:branch:staging", "lim": { "cnt": 20, "per": 86400 } },
      { "uri": "gmail:alice@example.com/send:domain:example.com", "lim": { "cnt": 50, "per": 86400 } }
    ],
    "reason": "Deploy hotfix and notify team",
    "exp": 86400
  }'
```

```typescript
// SDK — proof-of-possession handled automatically
import { X401Client } from '@x401/sdk';

const client = new X401Client({ act: myACT, privateKey: agentKey });

const response = await client.fetch('https://gateway.x401.dev/gmail/send', {
  method: 'POST',
  body: JSON.stringify({ to: 'bob@co.com', subject: 'Update', body: '...' }),
});
```

### on-chain verification

smart contracts verify ACTs natively. no oracles, no gateways.

```rust
// Solana — ~5,000 CU for a 2-signature delegation chain
pub fn verify_and_execute(
    ctx: Context<VerifyAndExecute>,
    act_data: ACTData,
    human_sig: [u8; 64],
    agent_sig: [u8; 64],
) -> Result<()> {
    require!(!ctx.accounts.act_state.revoked, X401Error::Revoked);
    require!(clock.unix_timestamp <= act_data.exp, X401Error::Expired);

    verify_ed25519(&ctx.accounts.human.key(), &delegation_msg, &human_sig)?;
    verify_ed25519(&ctx.accounts.agent.key(), &payload_msg, &agent_sig)?;

    // enforce spending limits with per-capability counters
    let state = &mut ctx.accounts.act_state;
    state.spent = state.spent.checked_add(act_data.amount).ok_or(X401Error::Overflow)?;
    require!(state.spent <= state.max_amount, X401Error::ExceedsLimit);

    transfer_spl_tokens(ctx, act_data.amount)
}
```

## token structure

an Agent Capability Token (ACT) is a signed JWT carrying capabilities across any number of services, with quantitative limits and a delegation chain.

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

each delegation narrows the parent's permissions. the agent gets `staging` only from the human's `*` wildcard. the agent gets 50 emails/day from the human's 200. attenuation is enforced cryptographically at every hop.

## capability URIs

one grammar across all services. learn it once, use it everywhere.

```
# on-chain
solana:mainnet/spl:EPjFW.../transfer
eip155:8453/erc20:0x833589.../transfer

# email
gmail:alice@example.com/send:domain:example.com

# code
github:acme/backend/push:branch:staging

# messaging
slack:acme/post:engineering

# APIs
https://api.example.com/data:read

# healthcare
fhir:hospital/Patient/123/DiagnosticReport:read
```

## quantitative limits

first-class primitives in every token.

```json
{ "amt": "100000000", "per": 86400 }                    // 100 USDC/day
{ "amt": "100000000", "per": 86400, "tx": "50000000" }  // 100/day, 50 max per swap
{ "cnt": 50, "per": 86400 }                              // 50 actions/day
{ "cnt": 1 }                                              // one-shot
{ "rate": [1000, 3600] }                                  // 1000 requests/hour
{ "cost": "50000", "cur": "USD", "per": 86400 }          // $500/day
```

## how it works

```
1. Agent requests access to a service
2. Service responds with HTTP 401 + required capabilities
3. Agent attaches its ACT in the Authorization header
4. Service verifies locally and serves the request
```

the same flow works for an API endpoint, a smart contract, a capability gateway. HTTP 401 is the internet's standard "unauthorized" response — x401 just tells the agent how to fix it.

## vs existing approaches

| | API keys | OAuth 2.0 | Auth0 for AI | x401 |
|---|---|---|---|---|
| verification | database lookup | JWKS (per-service) | JWKS + vault API | local JWT verify |
| scoping | none or service-defined | coarse, per-service | OAuth scopes | fine-grained + quantitative |
| cross-service | separate key per service | separate token per service | vault manages | one token, many services |
| delegation | not possible | not possible | not possible | inline chains with attenuation |
| on-chain | no | no | no | native (Solana, EVM) |
| revocation | per-service dashboard | per-service | per-service | one kill switch |

## examples

full implementation examples in [`examples/`](examples/):

| | |
|---|---|
| [`server/express-middleware.ts`](examples/server/express-middleware.ts) | verify ACTs on any Express endpoint |
| [`agent/http-api.sh`](examples/agent/http-api.sh) | zero-dependency integration via curl |
| [`agent/cli.sh`](examples/agent/cli.sh) | CLI for interactive, headless, and pre-signed flows |
| [`agent/sdk-client.ts`](examples/agent/sdk-client.ts) | SDK with automatic proof-of-possession |
| [`onchain/solana-verifier.rs`](examples/onchain/solana-verifier.rs) | Anchor program with Ed25519 verification + spending limits |
| [`onchain/evm-limit-enforcer.sol`](examples/onchain/evm-limit-enforcer.sol) | Solidity per-capability counters, gasless on Base |
| [`tokens/act-example.json`](examples/tokens/act-example.json) | full ACT JWT structure with delegation chain |
| [`tokens/proof-of-possession.json`](examples/tokens/proof-of-possession.json) | DPoP-style proof-of-possession format |

## docs

- [white paper](https://shehryar.github.io/x401/whitepaper) — the full protocol rationale and design
- [design doc](https://shehryar.github.io/x401/design) — technical specification (v0.2)
- [examples](https://shehryar.github.io/x401/examples) — implementation walkthrough

## related

- [x402](https://www.x402.org/) — HTTP-native payments. x401 + x402 compose: authorization and payment in a single roundtrip.
- [UCAN](https://ucan.xyz/) — capability-based authorization that inspired x401's delegation model.
- [ERC-7710](https://eips.ethereum.org/EIPS/eip-7710) — delegation framework for smart accounts. x401 integrates as a caveat enforcer.
