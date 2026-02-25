---
layout: doc
title: "x401: Agent Authorization Protocol — Design Document"
description: Design document v0.2 for the x401 agent authorization protocol
permalink: /design
---

# x401: Agent Authorization Protocol

## Design Document v0.2

**One-liner**: A universal protocol for scoped agent authorization. One credential format that a smart contract can verify on-chain, an API can verify off-chain, and any service in between can verify independently — no callbacks, no vaults, no per-service tokens.

**The name**: HTTP 401 means "you need to prove you're authorized." x401 is the protocol that lets agents do that. Same naming convention as x402 (HTTP 402 = "you need to pay"), same composability. A service can challenge with both: x401 for authorization, x402 for payment.

**The gap**: MCP handles agent-to-tool. x402 handles agent payments. A2A handles agent-to-agent communication. Nobody handles the fundamental question: "is this agent authorized by a human to do this specific thing?" On-chain, agents submit transactions with wallet keys but smart contracts have no way to verify a human's scoped intent — just that a key signed something. Off-chain, agents use OAuth tokens and API keys with no portable proof of what they're authorized to do across services. The authorization layer is missing everywhere.

**Where x401 is strongest**: On-chain is where the protocol is purest. A smart contract verifies the ACT natively in the VM — no oracles, no gateways, no external infrastructure. The human's scoped authorization is enforced by the chain's own math. Combined with x402, an agent can prove authorization and pay in a single HTTP roundtrip. Nothing else in the ecosystem does this.

Off-chain, x401 works natively with any new service that adds the middleware (one line of code). For existing services that won't change (Gmail, GitHub, Slack), capability gateways bridge the gap — verifying ACTs on the agent-facing side and calling native APIs on the service side. The gateway story is pragmatic, not pure. OAuth agent extensions (AAuth, OBO drafts) are credible competitors for simple off-chain agent identity. x401's advantage off-chain is in what the token carries: capabilities, quantitative limits, delegation chains, cross-service scope — things OAuth extensions don't address.

**The analogy**: OAuth gave every app a standard way to say "this user authorized me to access their data." x401 gives every agent a standard way to say "this human authorized me to do these specific things, within these specific limits, until this specific time" — and any service can verify that independently, on-chain or off-chain. Auth0 built a $6.5B business by making OAuth easy to implement. The same opportunity exists for agent authorization, and it's an order of magnitude larger because agents interact with more services, more autonomously, more frequently than apps ever did.

---

## 0. Why This Needs to Exist

### What you can't do today

**1. An agent can't prove it's authorized to a third party.**

You give your agent an API key or OAuth token. The agent calls someone's service. That service sees a valid credential but has zero information about: who authorized this agent, what specifically it's allowed to do, or when its access expires. The credential is a skeleton key with no context.

This applies everywhere. Your agent sends an email — the recipient's server can't verify a human authorized that message. Your agent pushes code — GitHub sees a valid token but doesn't know the human only authorized changes to one repo. Your agent books a flight — the airline API has no way to verify spending limits or traveler authorization.

Today's workaround: each service builds its own authorization layer. Privy has its policy engine. Lit has Vincent policies. Coinbase has AgentKit guardrails. Google has OAuth scopes. None of them talk to each other. An agent authorized via one system can't prove anything to another.

**2. Services can't verify that an action was human-authorized at the point of execution.**

An agent submits a transaction on-chain, calls an API, sends a message. The receiving service sees a valid credential from the agent's key. That's it. It has no way to verify whether a human actually authorized this specific action with these specific limits.

On-chain this means smart contracts are blind to human intent. Off-chain it means APIs trust whatever token they're given with no way to verify scope or delegation. If the agent is compromised or exceeds its intended authority, the service has no mechanism to catch it.

**3. Agents can't sub-delegate with verifiable attenuation.**

You have an orchestrator agent that manages worker agents. The orchestrator has your credentials. When it calls a worker, it either (a) shares your full credentials (worker has same access as orchestrator, massive over-privilege) or (b) creates separate credentials for the worker (no link back to your authorization, no proof of delegation chain).

This isn't just a crypto problem. Your travel agent delegates to a flight-booking agent which delegates to a seat-selection agent. Your coding agent delegates to a testing agent which delegates to a deployment agent. There's no way for the final agent in the chain to present a credential that traces back to the human's original scoped authorization with cryptographic proof at every step.

**4. You can't kill an agent's access across all services at once.**

Your agent has credentials for 15 different APIs, 3 DeFi protocols, your email, your calendar, and a code repository. Something goes wrong. You need to revoke everything. You log into each service individually. Some don't have programmatic revocation. By the time you've revoked 8 of them, the agent has already done damage with the other 7.

There's no single "kill switch" that instantly invalidates an agent's access everywhere, across every service and every chain.

**5. Authorization, payment, and identity don't compose.**

x402 lets an agent pay for an API. OAuth lets an agent prove its identity. But there's no defined way to link them. A service can't verify "this agent is authorized by Alice AND is paying from Alice's wallet AND is limited to $50/day" in a single, cryptographically linked flow.

More broadly, every agent interaction today involves separate, disconnected auth mechanisms. An agent that needs to read your email, check your calendar, and book a meeting uses 3 different OAuth tokens with no common authorization root. No single credential says "this human authorized this agent to do these specific things across these specific services."

**6. There's no audit trail from action to human intent.**

An agent sent a bad email. An agent made a bad trade. An agent pushed broken code. Who authorized it? What were the limits? Was it acting within bounds? Did a sub-agent do it? You check each service's logs individually. They're all separate systems with no common thread linking "human intention" to "agent action."

**7. Multi-agent workflows are authorization black boxes.**

Agent A calls Agent B calls Agent C. Each hop either passes the full credential forward (every agent is equally privileged) or operates in its own auth silo (no connection between the human's original intent and the final action). In a chain of 4 agents, by the time the last one acts, nobody can verify what the first human actually authorized.

This is the fundamental scaling problem for agentic systems. As workflows get more complex and agents delegate to other agents, the authorization story completely falls apart.

**8. OAuth wasn't designed for autonomous agents (and extensions have limits).**

OAuth assumes a human is present to click "Allow" for each service, each time. Agents operate autonomously, across many services, sometimes for days. OAuth scopes are coarse ("read email" vs "read emails from this sender, in this date range, containing these topics"). There's no concept of quantitative limits, delegation chains, or cross-service authorization in a single credential.

The IETF is working on this — AAuth and the OAuth On-Behalf-Of draft add agent identity claims to existing flows. These are useful steps (especially for compatibility with the massive OAuth ecosystem) but they extend the framework rather than rethinking what the token should carry. Adding `act.sub` to a JWT tells you *which* agent is acting but doesn't carry *what* it's authorized to do, *how much*, or *who delegated to whom*. See "Related work: OAuth agent extensions" in the Design Principles section for a detailed comparison.

### What this enables

*Ordered by protocol strength: on-chain first (where x401 is purest), then cross-cutting capabilities, then off-chain expansion.*

#### On-chain (zero infrastructure, maximum differentiation)

```
                        x401: Core Protocol Flow

  ┌──────────┐                                        ┌──────────────┐
  │  Human   │                                        │   Service    │
  │          │                                        │  (API / SC)  │
  └────┬─────┘                                        └──────┬───────┘
       │                                                     │
       │  1. Sign delegation                                 │
       │     (wallet / passkey)                              │
       │                                                     │
       ▼                                                     │
  ┌──────────┐         2. Request access              ┌──────┴───────┐
  │  Agent   │ ──────────────────────────────────────▶ │   Service    │
  │          │                                        │              │
  │ carries  │         3. HTTP 401 + required caps    │  "what auth  │
  │  ACT     │ ◀────────────────────────────────────── │   do you     │
  │          │                                        │   need?"     │
  │          │         4. ACT in Authorization header  │              │
  │          │ ──────────────────────────────────────▶ │  verify      │
  │          │            Authorization: ACT eyJ...    │  locally ✓   │
  │          │                                        │              │
  │          │         5. Response                     │  execute ✓   │
  │          │ ◀────────────────────────────────────── │              │
  └──────────┘                                        └──────────────┘
```

**1. Trustless on-chain agent execution.**

A DeFi protocol's smart contract can verify, on-chain, that a transaction was authorized by a specific human with specific limits. Not "trust the wallet provider." Actual cryptographic verification at the point of execution. The spending limits are enforced by the protocol's math, not by hoping the agent's infrastructure works correctly. No oracles, no gateways, no external services. The chain IS the verifier.

```
               On-Chain: Zero Infrastructure, Native Verification

  ┌──────────┐        ┌──────────┐        ┌─────────────────────────────┐
  │  Human   │        │  Agent   │        │  Smart Contract (On-Chain)  │
  └────┬─────┘        └────┬─────┘        └──────────────┬──────────────┘
       │                   │                             │
       │  sign delegation  │                             │
       │  (Phantom/MM)     │                             │
       │──────────────────▶│                             │
       │                   │                             │
       │                   │  submit tx with ACT         │
       │                   │────────────────────────────▶│
       │                   │                             │
       │                   │                   ┌─────────┴─────────┐
       │                   │                   │ verify human sig ✓│
       │                   │                   │ verify agent sig ✓│
       │                   │                   │ check expiry     ✓│
       │                   │                   │ check limits     ✓│
       │                   │                   │ execute           │
       │                   │                   └─────────┬─────────┘
       │                   │                             │
       │                   │  tx confirmed               │
       │                   │◀────────────────────────────│
       │                   │                             │

          ~5,000 CU on Solana  /  ~50K gas on EVM
          No oracles. No gateways. The chain IS the verifier.
```

**2. Authorization + payment in one request.**

Combined with x402, an agent can prove it's authorized AND pay for a service in a single HTTP roundtrip. The authorization (ACT) and payment (x402) are cryptographically linked via the same wallet. No separate auth flow, no separate payment flow. This enables agent-to-agent commerce, paid API access, and micropayments without any human in the loop per transaction. This is uniquely possible because x401 and x402 share the same wallet-native, HTTP-native design.

**3. On-chain limit enforcement as global source of truth.**

On-chain limit accounts serve as shared counters even for off-chain services. An agent's usage is tracked on Solana or Base, and off-chain services read the chain to verify the agent hasn't exceeded its limits. Gasless on Base via paymasters. See Section 5 for the full design.

#### Cross-cutting (works everywhere)

**4. Any agent action is verifiable back to human consent.**

An agent makes a trade, sends an email, pushes code, books a flight. In every case, the receiving service can independently verify: a specific human authorized this specific agent to do this specific thing, within these specific limits, until this specific time. One credential format, one verification step, on-chain or off-chain.

**5. Verifiable delegation chains for multi-agent systems.**

Human → orchestrator → worker → sub-worker. Each hop carries a cryptographic proof of delegation with provable attenuation. Works for any workflow:
- Human → portfolio manager (500 USDC/day) → DCA bot (100 USDC/day Jupiter) → swap executor (10 USDC/swap)
- Human → coding agent (push to staging) → test agent (read-only) → deploy agent (deploy to staging only, not prod)
- Human → travel agent ($2K budget) → flight booker ($1K, domestic) → seat selector ($50 upgrade limit)

```
                 Delegation Chain with Attenuation

  ┌──────────┐      ┌──────────────┐      ┌──────────┐      ┌──────────┐
  │  Human   │─────▶│ Orchestrator │─────▶│  Worker  │─────▶│ Executor │
  │          │ sign │              │ sign │          │ sign │          │
  └──────────┘      └──────────────┘      └──────────┘      └──────────┘
   500 USDC/day      500 USDC/day          100 USDC/day      10 USDC/swap
   any Jupiter       any Jupiter           SOL-USDC only     SOL-USDC only
   ─────────────────────────────────────────────────────────────────────▶
                     each hop narrows, never widens

  Executor tries 15 USDC?  → tx reverts (exceeds 10/swap)
  Worker tries SOL-ETH?    → verification fails (not in capability URI)
  Human revokes the root?  → every sub-delegation dies instantly
```

Any service receiving a request from the final agent can verify the entire chain in one step.

**6. One-click agent shutdown.**

One revocation call and every service that verifies ACTs immediately rejects the agent. Revoke the root delegation and all sub-delegations die too. Doesn't matter if the agent has access to 15 APIs, 3 chains, your email, and your calendar. One kill switch, everything stops.

**7. A foundation for agent-to-agent trust.**

When Agent A calls Agent B, Agent B can verify Agent A's authorization chain before doing anything. This is the missing primitive for multi-agent systems. Agents can trust each other not because they're in the same framework, but because they can verify each other's human-authorized capabilities. This works across frameworks, across services, across chains.

#### Off-chain (gateway-enabled today, native adoption over time)

**8. Scoped authorization across any domain, not just financial.**

Not just "this agent can spend $100/day" but the full spectrum of agent actions:
- "this agent can send emails from my address, but only to @company.com recipients, max 50/day"
- "this agent can push code to these 2 repos, but can't delete branches or force-push"
- "this agent can book flights under $500 for domestic travel only, in my name"
- "this agent can read my medical records at this provider, but can't share them or write"
- "this agent can post to my Slack in #engineering, but not #general or DMs"

The human sets precise boundaries once. The agent operates freely within them. For new services with x401 middleware, this works natively. For existing services (Gmail, GitHub, Slack), capability gateways enforce these constraints at the translation layer — finer-grained than the native services themselves support.

**9. Cross-platform agent portability.**

An agent authorized via x401 can prove its capabilities to any service, any chain, any framework. Not locked into Google's OAuth, or Privy's policies, or MetaMask's delegation. The credential is self-verifying and portable. This is what makes it a protocol and not a product.

**10. The universal "agent passport."**

Today, an agent needs separate credentials for every service: an API key here, an OAuth token there, a wallet signature somewhere else. ACTs replace all of these with one credential that carries the human's scoped authorization. For new services, the migration path is one middleware line. For existing services, the capability gateway provides the same unified credential experience while the protocol builds adoption toward native support.

---

## Design Principles

1. **JWT format** — every language has JWT libraries. DAG-CBOR (UCAN) is technically superior but adoption-hostile. Pragmatism over purity.
2. **Domain-agnostic** — the same token format authorizes on-chain transactions, API calls, email sending, code pushes, calendar access, and anything else an agent does. The capability URI scheme is extensible to any domain.
3. **Chain-agnostic, signature-native** — the token format works across any blockchain. The signature algorithm follows the target chain: secp256k1 for EVM, Ed25519 for Solana. Off-chain verification supports both.
4. **Self-contained tokens** — one JWT carries the full delegation chain inline. No external resolution. One token, one verification call.
5. **Quantitative limits as primitives** — not just "read/write" but measurable constraints: spending limits, rate limits, count limits, time bounds. "Send up to 50 emails/day" and "transfer up to 100 USDC/day" use the same limit structure.
6. **Dual-mode verification** — same token verified off-chain (JWT signature check) or on-chain (native sig verification in the target chain's VM). No other protocol does this.
7. **x402 composition** — authorization in `Authorization` header, payment in `PAYMENT-SIGNATURE`. Cryptographic link via shared wallet address. Agent commerce in one HTTP roundtrip.
8. **OAuth successor, not OAuth extension** — designed from scratch for autonomous agents, not bolted onto a human-interactive framework. Supports headless operation, delegation chains, cross-service authorization, and quantitative limits natively.

### Prior art: UCAN and the capability model

x401's delegation model is directly inspired by [UCAN](https://ucan.xyz/specification/) (User Controlled Authorization Networks). UCAN pioneered several ideas that x401 builds on:

- **Capability-based authorization** — tokens carry what the holder can do, not who the holder is. UCAN got this right first.
- **Delegation chains with attenuation** — each hop narrows capabilities, never widens. The proof chain is inline in the token. This is UCAN's core innovation.
- **Self-verifying credentials** — no callback to an auth server. The token carries its own proof. UCAN demonstrated this was practical.
- **Decentralized issuance** — any key holder can delegate to any other. No central authority required.

Where x401 diverges from UCAN, and why:

| Decision | UCAN | x401 | Why x401 diverged |
|---|---|---|---|
| **Format** | DAG-CBOR | JWT | Every language has JWT libraries. DAG-CBOR requires CBOR + CID + multihash dependencies. Adoption trumps technical elegance. |
| **Proof references** | CID content-addressed links (may require external resolution) | Inline in the token (no resolution step) | One token, one verification call. No IPFS dependency, no CID resolution latency. Tradeoff: larger tokens for deep chains. |
| **Quantitative limits** | Not first-class (extensible via facts/caveats) | First-class primitives (`amt`, `cnt`, `rate`, `cost`, `per`) | Agent authorization is fundamentally about "how much" not just "what." Spending limits, rate limits, and count limits need to be in the core spec, not extensions. |
| **On-chain verification** | Expensive on EVM (DAG-CBOR parsing), not designed for it | Native per chain (Ed25519 on Solana, ecrecover on EVM) | x401 targets on-chain use cases as a primary scenario, not an afterthought. Signature algorithm follows the chain. |
| **Payment composition** | None | x402 integration defined | Agent commerce (authorization + payment in one request) is a core use case. |
| **Consent flow** | No standard flow | Interactive, device grant, agent-tool-native, pre-signed | UCAN is a token format. x401 is a token format + consent protocol + verification standard. |
| **Domain specificity** | General-purpose capability URIs | Domain-specific URI grammar with formal ABNF | Agent use cases need well-defined patterns for common services (email, code, calendar, on-chain). |

UCAN is the intellectual ancestor. x401 is a pragmatic adaptation of UCAN's capability model for the specific problem of AI agent authorization, with additions for quantitative limits, on-chain verification, payment composition, and consent flows.

The UCAN community's work on [ucanto](https://github.com/storacha/ucanto) (Storacha's UCAN implementation) and the broader capability-based security literature (Mark Miller's object-capability model, KeyKOS, E language) inform the design. x401 wouldn't exist without this prior art.

### Related work: OAuth agent extensions (IETF)

The IETF is actively working on agent authorization within the OAuth framework. Two drafts are worth acknowledging:

**[AAuth (Agentic Authorization)](https://datatracker.ietf.org/doc/html/draft-rosenberg-oauth-aauth-01)** — extends OAuth 2.1 for scenarios where users interact via voice or SMS and can't do traditional browser-based OAuth flows. The agent collects PII from the user, submits it to the authorization server, and gets a scoped token. Includes a human-in-the-loop mechanism for elevated privileges (agent requests authorization, AS pushes consent to user, agent polls for token). Still early — sections are marked "details to be filled in."

**[OAuth On-Behalf-Of for AI Agents](https://datatracker.ietf.org/doc/html/draft-oauth-ai-agents-on-behalf-of-user-01)** — extends the OAuth Authorization Code Grant with two new parameters: `requested_actor` (identifies which agent needs delegation) and `actor_token` (authenticates the agent during code exchange). The resulting JWT includes an `act.sub` claim identifying the specific agent alongside the user's `sub` claim. Standard OAuth scope handling. Actor token acquisition method is explicitly left out of scope.

Both drafts are individual Internet-Drafts with no formal IETF standing yet. They represent the right impulse — agents need better authorization — using a different approach from x401.

| | OAuth agent extensions (AAuth, OBO) | x401 |
|---|---|---|
| **Approach** | Extend OAuth from within. Add agent identity claims to existing token flows. | New token format and protocol designed for agents from scratch. |
| **Compatibility** | Works with existing OAuth infrastructure. Every service with an OAuth AS can adopt incrementally. | Requires new middleware or capability gateways. No existing infrastructure to piggyback on. |
| **Scope mechanism** | Standard OAuth scopes (per-service, string-based, coarse). | Capability URIs with formal grammar, constraints, wildcard matching. Fine-grained and cross-service. |
| **Quantitative limits** | Not addressed. Limits live in the AS policy layer, not the token. | First-class (`amt`, `cnt`, `rate`, `cost`, `per`). Carried in the token. |
| **Delegation chains** | OBO draft adds `act.sub` for one level (user → agent). No multi-hop delegation. | Inline delegation chains with attenuation. Human → agent → sub-agent → worker, with cryptographic proof at every hop. |
| **On-chain verification** | Not addressed. | Native per chain (Ed25519 on Solana, ecrecover on EVM). |
| **Cross-service credential** | Per-service tokens from per-service authorization servers. | One ACT across all services. |
| **Human-in-the-loop** | AAuth has HITL for elevated ops. OBO uses standard consent screen. | Progressive authorization with capability grants (not per-action approval). Standing grants for predictable patterns. |

The honest assessment: OAuth extensions have a massive **compatibility advantage**. The OAuth ecosystem is enormous — every major service has an authorization server, every developer knows the flow, every framework has middleware. An OAuth extension that adds `act.sub` to existing JWTs is adoptable tomorrow with minimal changes. That's a real strength x401 can't match on day one.

Where OAuth extensions fall short is on the features that matter specifically for autonomous agents: quantitative limits in the token, multi-hop delegation chains, cross-service portable credentials, and on-chain verification. These aren't things you can bolt onto OAuth without fundamentally changing what the token carries, which is what x401 does.

The two approaches aren't necessarily in conflict. A world where OAuth extensions handle simple agent identity ("this is Agent X acting on behalf of User Y") and x401 handles complex agent authorization ("Agent X can do these specific things with these limits across these services, and here's the cryptographic delegation chain proving it") is plausible. OAuth extensions could even be a bridge — a service that accepts OAuth `act.sub` tokens today could add ACT verification later without breaking existing integrations.

x401 should position itself as complementary to OAuth agent work, not dismissive of it. The IETF process is slow but carries legitimacy. x401's own IETF submission (Phase 3 in the roadmap) should reference these drafts and explain how they relate.

---

## Chain Agnosticism and Multi-Chain Support

### The design is chain-agnostic at the protocol level

The capability URI scheme uses CAIP-2 chain identifiers, so any blockchain is addressable:

```
eip155:1/erc20:0xA0b8.../transfer          # Ethereum mainnet
eip155:8453/erc20:0x833589.../transfer      # Base
eip155:42161/erc20:0xaf88.../transfer       # Arbitrum
solana:mainnet/spl:EPjFW.../transfer        # Solana mainnet
solana:devnet/sol/transfer                   # Solana devnet
cosmos:cosmoshub-4/bank/send                 # Cosmos Hub
```

The token format (JWT), delegation model, capability structure, and consent flow are all completely chain-independent. A single ACT can contain capabilities across multiple chains.

### Signature algorithm follows the chain

The one thing that varies per chain is the signature algorithm, because on-chain verification needs to use whatever the chain verifies cheaply:

| Chain | Signature Algorithm | JWT `alg` | On-chain Verification Cost |
|-------|-------------------|-----------|---------------------------|
| Ethereum / EVM | secp256k1 (ECDSA) | `ES256K` | ~3,000 gas via `ecrecover` |
| Solana | Ed25519 | `EdDSA` | ~2,280 compute units per sig (native Ed25519 program) |
| Cosmos | secp256k1 or Ed25519 | varies | native in both cases |
| Aptos / Sui | Ed25519 | `EdDSA` | native |

Off-chain verification supports all algorithms. The `alg` field in the JWT header tells the verifier which to use.

### Why Solana is actually ideal for this

Solana has several properties that make it arguably better than EVM for agent authorization:

**1. Ed25519 is native and cheap.** Ed25519 signature verification uses Solana's native Ed25519 program at ~2,280 CU per signature. A 3-level delegation chain verification (3 sig checks) costs ~6,840 CU — well under 1% of Solana's 1.4M CU transaction limit. On EVM, Ed25519 verification costs 600K-1.2M gas because there's no precompile (secp256k1 via `ecrecover` is cheaper at ~3,000 gas but still more expensive per-dollar than Solana). Deep delegation chains are practical on Solana in ways they aren't on EVM.

**2. Fast finality.** Solana confirms transactions in ~400ms. For agent workflows where speed matters (trading, real-time API access), the authorization-to-execution loop is nearly instant. On Ethereum you're waiting 12 seconds per block.

**3. Low cost.** A full ACT verification + token transfer on Solana costs fractions of a cent. On Ethereum L1 it could cost $5-50 depending on gas prices. Even on L2s (Base, Arbitrum) you're paying 5-50 cents. This matters for micropayment agent use cases where the verification cost can't exceed the transaction value.

**4. Account model flexibility.** Solana's program-derived addresses (PDAs) and account model make it natural to create per-agent accounts with programmatic authority. The x401 verifier program can own PDAs that represent agent spending limits, revocation state, etc., without the storage cost concerns of EVM mappings.

**5. Composability with x402 on Solana.** x402 already supports Solana (USDC on Solana via SPL tokens). An agent paying for an API via x402 on Solana gets ~400ms settlement. Combined with ACT verification, the full "prove authorization + pay + get response" loop could be under 1 second.

### Solana-specific ACT example

```json
{
  "typ": "act+jwt",
  "alg": "EdDSA",
  "kid": "did:key:z6MkAgent..."
}
{
  "iss": "did:key:z6MkAgent...",
  "sub": "did:key:z6MkHuman...",
  "aud": "*",
  "exp": 1740672154,
  "jti": "0xdeadbeef...",

  "cap": [
    {
      "uri": "solana:mainnet/spl:EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v/transfer",
      "lim": { "amt": "100000000", "per": 86400 }
    },
    {
      "uri": "solana:mainnet/program:JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4/call:route",
      "lim": { "amt": "500000000", "per": 86400, "tx": "50000000" }
    }
  ],

  "dlg": {
    "iss": "did:key:z6MkHuman...",
    "sig": "base64-ed25519-sig...",
    "cap": [
      {
        "uri": "solana:mainnet/spl:EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v/transfer",
        "lim": { "amt": "1000000000", "per": 86400 }
      },
      {
        "uri": "solana:mainnet/program:JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4/*",
        "lim": { "amt": "1000000000", "per": 86400 }
      }
    ],
    "exp": 1740758554,
    "prf": []
  },

  "rsn": "Jupiter DCA rebalancing"
}
```

This ACT says: "Human authorized this agent to transfer up to 100 USDC/day on Solana and route up to 500 USDC/day through Jupiter, max 50 USDC per swap. The human's original grant was 1000 USDC/day for both (the agent narrowed it)."

### Solana verifier program (Anchor)

```rust
use anchor_lang::prelude::*;

#[account]
pub struct ACTState {
    pub human: Pubkey,           // Human who authorized
    pub agent: Pubkey,           // Agent authorized
    pub jti: [u8; 32],           // Unique token ID
    pub cap_hash: [u8; 32],      // Hash of capabilities
    pub exp: i64,                // Expiry timestamp
    pub revoked: bool,           // Revocation flag
    pub spent: u64,              // Amount spent in current period
    pub period_start: i64,       // When current period started
    pub max_amount: u64,         // Max per period
    pub period: i64,             // Period length in seconds
}

#[program]
pub mod x401_verifier {
    use super::*;

    pub fn verify(
        ctx: Context<Verify>,
        act_data: ACTData,
        human_sig: [u8; 64],
        agent_sig: [u8; 64],
    ) -> Result<()> {
        let clock = Clock::get()?;

        // 1. Check not revoked
        require!(!ctx.accounts.act_state.revoked, X401Error::Revoked);

        // 2. Check expiry
        require!(clock.unix_timestamp <= act_data.exp, X401Error::Expired);

        // 3. Verify human's Ed25519 delegation signature
        let delegation_msg = build_delegation_message(&act_data);
        let human_key = ctx.accounts.human.key();
        verify_ed25519(&human_key.to_bytes(), &delegation_msg, &human_sig)?;

        // 4. Verify agent's Ed25519 signature
        let payload_msg = build_payload_message(&act_data, &ctx.accounts.target.key());
        let agent_key = ctx.accounts.agent.key();
        verify_ed25519(&agent_key.to_bytes(), &payload_msg, &agent_sig)?;

        // 5. Check spending limits
        let state = &mut ctx.accounts.act_state;
        if state.period > 0 && clock.unix_timestamp >= state.period_start + state.period {
            state.spent = 0;
            state.period_start = clock.unix_timestamp;
        }
        state.spent = state.spent.checked_add(act_data.amount)
            .ok_or(X401Error::Overflow)?;
        require!(state.spent <= state.max_amount, X401Error::ExceedsLimit);

        emit!(Verified {
            jti: act_data.jti,
            agent: ctx.accounts.agent.key(),
            human: ctx.accounts.human.key(),
        });

        Ok(())
    }

    pub fn revoke(ctx: Context<Revoke>) -> Result<()> {
        // Only the human can revoke
        require!(
            ctx.accounts.signer.key() == ctx.accounts.act_state.human,
            X401Error::Unauthorized
        );
        ctx.accounts.act_state.revoked = true;
        emit!(Revoked {
            jti: ctx.accounts.act_state.jti,
            revoker: ctx.accounts.signer.key(),
        });
        Ok(())
    }
}
```

Verification cost estimate on Solana:
- Ed25519 sig verify: ~2,280 CU × 2 sigs = ~4,560 CU
- Account reads: ~100 CU
- Spending limit check (account write): ~200 CU
- Total: ~5,000-6,000 CU (~0.4% of Solana's 1.4M CU transaction limit)

Compare to EVM: ~50-80K gas (~$0.10-1.00 on L1, ~$0.005-0.05 on L2)

### Cross-chain ACTs

A single ACT can contain capabilities across multiple chains:

```json
{
  "cap": [
    {
      "uri": "solana:mainnet/spl:EPjFW.../transfer",
      "lim": { "amt": "500000000", "per": 86400 }
    },
    {
      "uri": "eip155:8453/erc20:0x833589.../transfer",
      "lim": { "amt": "500000000", "per": 86400 }
    },
    {
      "uri": "https://api.example.com/data",
      "act": ["read"]
    }
  ]
}
```

The signing challenge: if the human has a Solana wallet (Ed25519), the delegation signature is Ed25519. An EVM verifier can't cheaply verify that. Three approaches:

**Approach A: Chain-scoped signing (recommended).** The delegation includes per-chain signatures. The human signs once per chain ecosystem during the consent flow. The wallet adapter handles this (Phantom for Solana, MetaMask for EVM). Adds ~1 second to consent for each additional chain.

```json
{
  "dlg": {
    "iss": "did:key:z6MkHuman...",
    "sigs": {
      "solana": "base64-ed25519-sig...",
      "eip155": "0x-secp256k1-sig..."
    },
    "cap": [...],
    "exp": 1740758554,
    "prf": []
  }
}
```

**Approach B: Primary chain + attestation.** The human signs with their primary wallet (e.g., Solana Ed25519). For EVM verification, an attestation relayer verifies the Ed25519 sig off-chain and issues a secp256k1-signed attestation that EVM contracts can verify cheaply. Adds a trust assumption (the relayer) but is simpler UX.

**Approach C: Separate ACTs per chain.** Simplest. One ACT for Solana capabilities (Ed25519), one for EVM capabilities (secp256k1). Off-chain verification accepts either. Slight fragmentation but zero cross-chain complexity.

Recommendation: start with Approach C for simplicity, ship Approach A when multi-chain demand materializes. The protocol supports all three via the `dlg.sigs` field (Approach A) or single `dlg.sig` field (Approach B/C).

### Wallet support matrix

| Wallet | Chain | Sig Algorithm | Consent Flow |
|--------|-------|--------------|--------------|
| Phantom | Solana | Ed25519 | signMessage() |
| Backpack | Solana + EVM | Ed25519 + secp256k1 | signMessage() per chain |
| MetaMask | EVM | secp256k1 | EIP-712 signTypedData() |
| Coinbase Wallet | EVM + Solana | Both | Both methods |
| WalletConnect | Multi-chain | Both | Both methods |
| Ledger | Multi-chain | Both | Hardware signing |

The consent UI auto-detects the connected wallet and uses the appropriate signing method.

---

## 1. Credential Format: Agent Capability Token (ACT)

### JWT Header

```json
{
  "typ": "act+jwt",
  "alg": "ES256K",
  "kid": "did:key:zQ3shP2mWsZYWgDTL..."
}
```

- `typ`: MUST be `act+jwt` (registered media type for ACTs)
- `alg`: `ES256K` (secp256k1) for EVM targets, `EdDSA` (Ed25519) for Solana/non-EVM targets. Off-chain verifiers MUST support both.
- `kid`: The agent's DID. `did:key` for self-sovereign identity. `did:web` for organizational agents.

### JWT Payload

This example shows a multi-domain ACT — the agent is authorized for on-chain trading, API access, and email sending, all in one credential.

```json
{
  "iss": "did:key:zQ3shAgent...",
  "sub": "did:key:zQ3shHuman...",
  "aud": "*",
  "exp": 1740672154,
  "nbf": 1740672089,
  "jti": "0xdeadbeef1234567890abcdef",

  "cap": [
    {
      "uri": "solana:mainnet/spl:EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v/transfer",
      "lim": { "amt": "100000000", "per": 86400 }
    },
    {
      "uri": "https://api.example.com/data",
      "act": ["read"],
      "lim": { "rate": [1000, 3600] }
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
      {
        "uri": "solana:mainnet/spl:EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v/transfer",
        "lim": { "amt": "500000000", "per": 86400 }
      },
      {
        "uri": "https://api.example.com/data",
        "act": ["read", "write"],
        "lim": { "rate": [5000, 3600] }
      },
      {
        "uri": "gmail:alice@example.com/send",
        "lim": { "cnt": 200, "per": 86400 }
      },
      {
        "uri": "github:acme/*/push",
        "lim": { "cnt": 100, "per": 86400 }
      }
    ],
    "exp": 1740758554,
    "prf": []
  },

  "rsn": "Daily portfolio rebalancing and status reporting"
}
```

### Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `iss` | DID string | Yes | Agent's identity (who is presenting this token) |
| `sub` | DID string | Yes | Human's identity (the resource owner / authority source) |
| `aud` | string | Yes | Intended verifier. `"*"` for any verifier, or specific service DID/URL |
| `exp` | unix timestamp | Yes | Expiry. Protocol recommends 1h default, 24h max without explicit opt-in |
| `nbf` | unix timestamp | No | Not-before time |
| `jti` | hex string | Yes | Unique token ID. Used for revocation and replay prevention |
| `cap` | Capability[] | Yes | What this agent can do (effective capabilities, must be subset of dlg.cap) |
| `lim` | Limit | Per-cap | Quantitative constraints on each capability |
| `dlg` | Delegation | Yes | Proof of human authorization |
| `rsn` | string | Recommended | Human-readable reason. Echoed verbatim in consent UI |

### Capability URI Scheme

The URI scheme is designed to be extensible to any domain. On-chain actions use CAIP-2 chain identifiers. Off-chain actions use service-specific URI schemes. Custom domains can define their own URI patterns following the same `{service}:{scope}/{resource}/{action}` structure.

```
# ── On-chain actions ──

# EVM (CAIP-2 chain ID + asset/action)
eip155:{chainId}/erc20:{contractAddr}/transfer     # ERC-20 transfer
eip155:{chainId}/erc20:{contractAddr}/approve       # ERC-20 approval
eip155:{chainId}/erc721:{contractAddr}/transfer     # NFT transfer
eip155:{chainId}/eth/send                           # Native ETH send
eip155:{chainId}/contract:{addr}/call:{selector}    # Specific function call
eip155:{chainId}/contract:{addr}/*                  # Any call to contract

# Solana
solana:{cluster}/spl:{mintAddr}/transfer            # SPL token transfer
solana:{cluster}/sol/transfer                       # Native SOL transfer
solana:{cluster}/program:{programId}/call:{method}  # Specific program instruction
solana:{cluster}/program:{programId}/*              # Any instruction to program

# Cosmos
cosmos:{chainId}/bank/send
cosmos:{chainId}/staking/delegate

# ── Off-chain actions (APIs and services) ──

# Generic HTTPS resources
https://api.example.com/data                        # Full resource access
https://api.example.com/data:read                   # Read-only
https://api.example.com/data:write                  # Write-only
https://api.example.com/*                           # Wildcard

# Email
gmail:{account}/send                                # Send email
gmail:{account}/send:domain:company.com             # Send only to @company.com
gmail:{account}/read                                # Read emails
gmail:{account}/read:label:inbox                    # Read inbox only
gmail:{account}/draft                               # Create drafts (not send)
email:*/send                                        # Any email provider

# Code repositories
github:{owner}/{repo}/push                          # Push commits
github:{owner}/{repo}/push:branch:staging           # Push to staging only
github:{owner}/{repo}/pull-request                  # Create PRs
github:{owner}/{repo}/read                          # Read-only access
github:{owner}/*/read                               # Read all repos for owner
github:{owner}/{repo}/delete:branch                 # Delete branches

# Calendar
gcal:{account}/create                               # Create events
gcal:{account}/read                                 # Read calendar
gcal:{account}/modify                               # Modify existing events
gcal:{account}/delete                               # Delete events

# Messaging
slack:{workspace}/post:{channel}                    # Post to specific channel
slack:{workspace}/post:*                            # Post to any channel
slack:{workspace}/dm:{user}                         # DM a specific user
slack:{workspace}/read                              # Read messages

# Travel and commerce
booking:flights/search                              # Search flights
booking:flights/purchase                            # Purchase flights
booking:hotels/search
booking:hotels/reserve

# Healthcare
fhir:{provider}/Patient/{id}/read                   # Read patient records
fhir:{provider}/Patient/{id}/write                  # Write patient records
fhir:*/Patient/*/read                               # Read from any provider

# File storage
gdrive:{account}/read:{folder}                      # Read files in folder
gdrive:{account}/write:{folder}                     # Write files in folder
gdrive:{account}/share                              # Share files

# Generic service pattern
{service}:{scope}/{resource}/{action}               # Extensible to any domain
```

#### Formal grammar (ABNF)

```abnf
; ── Top-level URI ──

capability-uri   = onchain-uri / service-uri / https-uri

; ── On-chain: CAIP-2 chain ID + resource path ──

onchain-uri      = chain-ns ":" chain-ref "/" resource-path
chain-ns         = ALPHA *( ALPHA / DIGIT )          ; "eip155", "solana", "cosmos" (starts with letter, may contain digits)
chain-ref        = 1*(ALPHA / DIGIT / "-")           ; "1", "8453", "mainnet", "devnet", "cosmoshub-4"

; ── Off-chain services: scheme + scope + resource path ──

service-uri      = scheme ":" scope "/" resource-path
scheme           = ALPHA *( ALPHA / DIGIT )          ; "gmail", "github", "slack", "gcal", "fhir" (starts with letter)
scope            = scope-segment *("/" scope-segment)
scope-segment    = wildcard / value

; ── HTTPS: standard URL with optional action suffix ──

https-uri        = "https://" host "/" path-segments
host             = 1*(ALPHA / DIGIT / "." / "-")
path-segments    = path-segment *("/" path-segment)
path-segment     = wildcard / value [":" action *constraint]

; ── Resource path (shared by onchain and service URIs) ──

resource-path    = *( segment "/" ) terminal-segment
segment          = typed-segment / wildcard / value
typed-segment    = type-prefix ":" value             ; "erc20:0xA0b8...", "spl:EPjFW...", "program:JUP6..."
type-prefix      = ALPHA *( ALPHA / DIGIT )          ; "erc20", "erc721", "spl", "program", "contract" (starts with letter)

terminal-segment = wildcard / action *constraint
action           = 1*(ALPHA / DIGIT / "-")           ; "transfer", "send", "push", "read", "call", "pull-request"
constraint       = ":" constraint-key ":" constraint-value
constraint-key   = ALPHA *( ALPHA / DIGIT )          ; "domain", "branch", "label", "channel"
constraint-value = 1*(ALPHA / DIGIT / "." / "-" / "_" / "@" / "*")

; ── Primitives ──

wildcard         = "*"
value            = 1*(ALPHA / DIGIT / "." / "-" / "_" / "@" / ":" / "+" / "%")
```

Note: prefix wildcards (e.g., `JUP6*`) are NOT supported by the grammar. The wildcard `*` is a standalone token that matches an entire segment. To match "any program on Jupiter," use `solana:mainnet/program:JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4/*` (specific program address, wildcard action) rather than a prefix glob.

#### Wildcard semantics

`*` can appear in any segment position. It matches any single value in that position.

```
github:acme/*/push              matches github:acme/backend/push
                                matches github:acme/frontend/push
                                does NOT match github:acme/backend/v2/push (no recursive wildcard)

email:*/send                    matches gmail:alice@co.com/send
                                matches outlook:bob@co.com/send

fhir:*/Patient/*/read           matches fhir:kaiser/Patient/12345/read

solana:mainnet/program:*/call:route   matches solana:mainnet/program:JUP6.../call:route
                                     matches solana:mainnet/program:ORCA.../call:route
                                     does NOT match solana:mainnet/program:JUP6.../call:swap (action mismatch)
```

Rules:
- `*` matches exactly one path segment (between `/` delimiters). No recursive/globstar (`**`) matching.
- `*` in a constraint value position matches any constraint value: `push:branch:*` matches `push:branch:staging` and `push:branch:main`.
- A URI without constraints is broader than the same URI with constraints: `gmail:alice/send` covers `gmail:alice/send:domain:co.com`.
- `*` as the entire terminal segment matches any action: `program:JUP6.../*` matches any instruction to that program.

#### Subset matching (delegation chain verification)

During verification, the protocol checks that each child capability is a **subset** of its parent's capability. This is the core attenuation rule — capabilities can only narrow, never widen.

A child URI is a subset of a parent URI if and only if all of the following hold:

```
1. SCHEME MATCH
   Parent and child have the same scheme (or parent is wildcard).
   Parent: github:acme/*/push    Child: github:acme/backend/push       ✓
   Parent: gmail:alice/send      Child: github:acme/push               ✗ (different scheme)

2. SCOPE MATCH
   Each scope segment in the child matches the corresponding parent segment.
   A parent segment of * matches any child segment value.
   Parent: github:acme/*         Child: github:acme/backend             ✓
   Parent: github:acme/backend   Child: github:acme/*                   ✗ (child is broader)

3. ACTION MATCH
   Parent action of * matches any child action.
   A specific parent action must equal the child action.
   Parent: github:acme/*/push    Child: github:acme/backend/push        ✓
   Parent: github:acme/*         Child: github:acme/backend/push        ✓ (* matches push)
   Parent: github:acme/*/read    Child: github:acme/backend/push        ✗ (read ≠ push)

4. CONSTRAINT MATCH
   If the parent has no constraints, the child may have any constraints (or none).
   If the parent has constraints, the child must have the same or narrower constraints.
   A child may ADD constraints not present in the parent (adding constraints narrows access).
   A child may NOT REMOVE constraints present in the parent.

   Parent: gmail:alice/send                    Child: gmail:alice/send:domain:co.com    ✓ (child adds constraint)
   Parent: gmail:alice/send:domain:co.com      Child: gmail:alice/send                  ✗ (child removes constraint)
   Parent: github:acme/*/push:branch:*         Child: github:acme/backend/push:branch:staging  ✓ (child narrows wildcard)
   Parent: github:acme/*/push:branch:staging   Child: github:acme/backend/push:branch:main     ✗ (different constraint value)

5. LIMIT MATCH (checked separately, not part of URI matching)
   Child limits must be ≤ parent limits. See Capability Limits section.
```

The matching algorithm is implemented in `@x401/verify` and the `x401 verify` CLI. A reference test suite covers all edge cases.

#### Capability URI registration

The protocol does not require a central registry of capability URIs. Any service can define its own URI patterns following the grammar above. However, the protocol maintains a **well-known capability catalog** (similar to IANA media types) documenting common patterns for popular services. This helps interoperability — if two different agent tools both use `gmail:{account}/send:domain:{domain}` instead of inventing their own schemes, gateways and verifiers can handle them consistently.

The catalog is informational, not normative. Services are free to use any URI pattern that follows the grammar.

### Capability Limits

All limits use the same structure regardless of domain. This is what makes the protocol general-purpose — the same limit primitives apply to spending, sending emails, pushing code, and booking flights.

```json
// ── Spending limits (on-chain) ──
{ "amt": "100000000", "per": 86400 }     // Max 100 USDC per 24h (amounts in token's smallest unit)
{ "amt": "500000000" }                    // Max 500 USDC total lifetime of token
{ "amt": "100000000", "per": 86400, "tx": "50000000" }  // Per-period AND per-transaction limit

// ── Count limits (any domain) ──
{ "cnt": 50, "per": 86400 }              // Max 50 actions per day (emails, API calls, commits, etc.)
{ "cnt": 1 }                             // One-shot: can only do this action once
{ "cnt": 10, "per": 3600 }              // Max 10 per hour

// ── Rate limits (APIs and services) ──
{ "rate": [1000, 3600] }                  // Max 1000 requests per 3600 seconds
{ "rate": [10, 60] }                      // Max 10 requests per minute

// ── Monetary limits (off-chain purchases) ──
{ "cost": "50000", "cur": "USD", "per": 86400 }          // Max $500/day (cents)
{ "cost": "50000", "cur": "USD", "tx": "10000" }         // Max $100 per purchase

// ── Gas/compute limits (on-chain) ──
{ "gas": "5000000" }                      // Max gas per transaction (EVM)
{ "cu": "1000000" }                       // Max compute units per transaction (Solana)
{ "gas": "50000000", "per": 86400 }       // Max gas per day

// ── Combined examples ──

// Email: 50 emails/day, only to @company.com (domain restriction is in the URI)
{ "cnt": 50, "per": 86400 }

// Flight booking: max $500 per booking, $2000/month
{ "cost": "50000", "cur": "USD", "tx": "50000", "per": 2592000, "cnt": 5 }

// DeFi: 100 USDC/day, max 10 USDC per swap, 100 API calls/hour
{
  "amt": "100000000",
  "per": 86400,
  "tx": "10000000",
  "rate": [100, 3600]
}

// Code: max 20 pushes per day
{ "cnt": 20, "per": 86400 }
```

### Delegation Proof

The `dlg` field contains the cryptographic proof that a human authorized this agent.

```json
{
  "dlg": {
    "iss": "did:key:zQ3shHuman...",
    "sig": "0xabc123...",
    "cap": [...],
    "exp": 1740758554,
    "nonce": "0xdeadbeef...",
    "prf": []
  }
}
```

The `nonce` field is required in every delegation. It's included in the signed payload so verifiers can reconstruct exactly what was signed from the token contents alone. This prevents replay of delegation signatures and enables emergency revocation via nonce rotation (see Section 4).

**Signature payload (what the human signs)**:

The delegation signature MUST cover all fields that affect the agent's authorization: capabilities, limits, expiry, reason, and a nonce for replay prevention. The `rsn` (reason) field is included in the signed payload so it cannot be manipulated after signing — what the human saw in the consent UI is cryptographically bound to the delegation.

**Canonical serialization for `capabilities_hash`**: The capabilities array is serialized to JSON with keys sorted lexicographically (RFC 8785 — JSON Canonicalization Scheme) before hashing. This ensures two implementations produce the same hash for the same capabilities regardless of key ordering. The hash is SHA-256 of the canonical JSON bytes.

For EVM (EIP-712 typed data):
```
keccak256(abi.encode(
  "x401 Delegation",
  delegator_did,
  delegate_did,
  capabilities_hash,     // SHA-256 of JCS-canonicalized capabilities JSON
  reason_hash,           // SHA-256 of rsn string (human-readable reason)
  expiry,
  nonce                  // unique per delegation, stored in dlg.nonce
))
```

For Solana (signMessage):
```
SHA-256(concat(
  "x401 Delegation\n",
  delegator_did, "\n",
  delegate_did, "\n",
  capabilities_hash, "\n",
  reason_hash, "\n",
  expiry, "\n",
  nonce, "\n"
))
```

The `nonce` is stored in the `dlg` structure as `dlg.nonce` so verifiers can reconstruct the signed payload from the token alone.

### Sub-delegation (Agent → Agent)

Agent A delegates a subset of capabilities to Agent B. The token grows by one entry in `dlg.prf`:

```json
{
  "iss": "did:key:zQ3shAgentB...",
  "sub": "did:key:zQ3shHuman...",
  "cap": [
    { "uri": "eip155:8453/erc20:0xA0b8.../transfer", "lim": { "amt": "50000000", "per": 86400 } }
  ],
  "dlg": {
    "iss": "did:key:zQ3shAgentA...",
    "sig": "0xdef456...",
    "cap": [
      { "uri": "eip155:8453/erc20:0xA0b8.../transfer", "lim": { "amt": "100000000", "per": 86400 } }
    ],
    "exp": 1740672154,
    "prf": [
      {
        "iss": "did:key:zQ3shHuman...",
        "sig": "0xabc123...",
        "cap": [
          { "uri": "eip155:8453/erc20:0xA0b8.../transfer", "lim": { "amt": "500000000", "per": 86400 } }
        ],
        "exp": 1740758554,
        "prf": []
      }
    ]
  }
}
```

**Attenuation rules** (enforced at verification):
1. Each link's capabilities MUST be a subset of its parent's capabilities (see URI subset matching rules in the Capability URI Scheme section)
2. All limit fields can only decrease or stay the same, never increase. Specifically:
   - `amt` (amount): child ≤ parent
   - `cnt` (count): child ≤ parent
   - `rate` (requests per period): child rate ≤ parent rate (both numerator and denominator compared)
   - `cost` (monetary): child ≤ parent (same `cur` required; cross-currency comparison is not supported)
   - `tx` (per-transaction): child ≤ parent
   - `gas` / `cu` (compute): child ≤ parent
   - `per` (period window): child ≤ parent (shorter or equal window)
   - If a parent has a limit field and the child omits it, the parent's value carries forward (implicit inheritance). A child CANNOT remove a limit the parent set.
   - If a parent omits a limit field, the child MAY add it (adding limits narrows access).
3. Expiry can only be equal or earlier than parent's expiry
4. New capability URIs CANNOT be added (only narrowed or removed)
5. Enforcement tier can only stay the same or escalate (`none` → `verifier` → `onchain`). A child cannot downgrade enforcement.
6. Recommended max chain depth: 3 (human → agent → sub-agent → worker)

**Verification**: Walk the chain from leaf to root. At each link, verify: (a) signature is valid, (b) capabilities are a subset of parent, (c) expiry <= parent expiry. If any check fails, the entire token is invalid.

---

## 2. Consent Flow

### Issuance model: permissionless, not centralized

The protocol defines a **delegation message format** — what fields it contains, what gets signed, what the signature covers. Any app that can present that message to a human and collect a wallet signature is a valid issuer. There's no privileged issuer, no certificate authority, no registration step.

This is the same model as EIP-712 typed data signing: the protocol defines the data structure, any wallet/app renders the signing request. Or like ACME/Let's Encrypt: the protocol is open, Let's Encrypt is the dominant CA, but anyone can run their own.

The issuance landscape:

| Issuer | How it works | Who it's for |
|---|---|---|
| **Agent tools and frameworks** | Claude Code, Cursor, OpenClaw, CrewAI, LangChain — the tool surfaces a consent prompt inline when the agent needs authorization. Human approves in the same UI they're already using. | Most users. This is where most adoption would happen because this is where agents actually run. |
| **Wallet-native** | Phantom, MetaMask, Backpack build consent flows directly into the wallet. "Agent X requests these capabilities" → review → sign. No external server. | Crypto-native users. Best long-term UX for on-chain use cases. |
| **auth.x401.dev** (hosted consent server) | Our hosted app. Consent UI, wallet connect, capability review. The reference implementation and easiest default. | Headless agents, device grant flows, developers getting started. |
| **Self-hosted consent server** | Open source reference implementation, run your own. | Enterprise, privacy-sensitive deployments. |
| **CLI** (Mode C) | `x401 grant --to did:key:... --cap ...` — human signs directly. | Power users, CI/CD, scripts. No server at all. |

**Agent tools are the primary adoption channel.** The authorization moment happens when an agent needs to do something it can't yet. If the tool the human is already using can surface the consent flow inline, that's the fastest path to a signed ACT. No redirect to an external site, no wallet connect dance on a separate page. The agent framework includes `@x401/sdk`, detects the 401, prompts the human in-context, collects the signature, done.

The hosted consent server (auth.x401.dev) is the fallback and the default for cases where there's no inline UI — headless agents, background services, the device grant flow. It's important infrastructure but it's not the protocol. It's our app. Same as how Let's Encrypt is the most popular CA but isn't TLS.

**What this means for centralization:** verification is fully decentralized (local JWT check, no callbacks). Issuance is permissionless (any app can be an issuer). The hosted consent server is a convenience product, not a protocol dependency. The protocol works without it.

### Consent modes

Four modes for obtaining human authorization.

### Mode A: Interactive (browser-based)

For when the human has a browser and can interact directly.

```
GET https://auth.x401.dev/authorize?
  agent_did=did:key:zQ3shAgent...&
  cap=solana:mainnet/spl:EPjFW.../transfer&
  lim=amt:100000000,per:86400&
  cap=gmail:alice@example.com/send:domain:example.com&
  lim=cnt:50,per:86400&
  cap=github:acme/backend/push:branch:staging&
  lim=cnt:20,per:86400&
  exp=86400&
  rsn=Daily+rebalancing+and+reporting&
  redirect_uri=https://agent.example.com/callback&
  state=xyz123
```

1. Human is shown a consent screen with: agent identity, requested capabilities (human-readable, grouped by domain), limits, reason, expiry
2. Human authenticates — wallet signing for on-chain capabilities (Phantom, MetaMask, etc.), or passkey/WebAuthn for off-chain-only capabilities
3. Human signs the delegation (EIP-712 for EVM wallets, signMessage for Solana wallets, or WebAuthn assertion for off-chain-only)
4. Redirect back with signed delegation:

```
GET https://agent.example.com/callback?
  act=eyJhbGciOiJFUzI1NksiLC...&
  state=xyz123
```

### Mode B: Device Grant (headless agents)

For AI agents that can't open a browser (CLI tools, background services, MCP servers).

**Step 1: Agent requests authorization**
```
POST https://auth.x401.dev/device/authorize
Content-Type: application/json

{
  "agent_did": "did:key:zQ3shAgent...",
  "cap": [
    { "uri": "solana:mainnet/spl:EPjFW.../transfer", "lim": { "amt": "100000000", "per": 86400 } },
    { "uri": "gmail:alice@example.com/send:domain:example.com", "lim": { "cnt": 50, "per": 86400 } },
    { "uri": "slack:acme/post:engineering", "lim": { "cnt": 20, "per": 86400 } }
  ],
  "rsn": "Daily portfolio rebalancing with email and Slack reporting",
  "exp": 86400
}
```

**Step 2: Server responds with code**
```json
{
  "code": "WXYZ-1234",
  "verify_uri": "https://auth.x401.dev/verify",
  "verify_uri_complete": "https://auth.x401.dev/verify?code=WXYZ-1234",
  "expires_in": 600,
  "interval": 5,
  "poll_endpoint": "https://auth.x401.dev/poll/abc123",
  "sse_endpoint": "https://auth.x401.dev/sse/abc123"
}
```

Agent displays to user: "Authorize this agent at https://auth.x401.dev/verify — code: WXYZ-1234"

**Step 3: Agent polls (HTTP or SSE)**
```
GET https://auth.x401.dev/poll/abc123
→ { "status": "pending" }
→ { "status": "pending" }
→ { "status": "authorized", "act": "eyJhbGciOiJFUzI1NksiLC..." }
```

**Step 4: Human goes to verify_uri**
- Enters code (or uses the complete URI)
- Reviews agent identity, capabilities, limits, reason
- Connects wallet, signs delegation
- Agent receives ACT via poll/SSE

### Mode C: Agent-tool-native (inline consent)

For agent frameworks and tools where the human is actively present. This is where most issuance would happen in practice — tools like Claude Code, Cursor, OpenClaw, CrewAI, LangChain, etc.

The agent runtime detects that a capability is needed (either the agent requests it upfront or hits a 401 mid-task). The tool surfaces the consent prompt directly in its own UI. The human reviews and signs without leaving the tool.

```
Agent runtime (Claude Code, Cursor, OpenClaw, etc.)
  → Agent needs github:acme/backend/push:branch:staging
  → Runtime renders consent prompt inline:
      "Agent requests: push to acme/backend (staging branch only), 20/day, 24h"
      [Approve] [Deny] [Modify limits]
  → Human approves
  → Runtime collects signature:
      - If wallet connected: wallet signs delegation message
      - If passkey: WebAuthn assertion
      - If platform auth: platform-specific signing (e.g., platform-held key on behalf of user)
  → Runtime assembles ACT, hands it to the agent
  → Agent proceeds
```

For tools that support progressive authorization (Section 6), the same inline flow handles mid-task capability requests. The agent discovers it needs something new, the tool prompts the human in-context with the reason and requested capabilities, the human signs, the agent continues. No context switch, no external redirect.

#### Integration paths: API, CLI, SDK

Agent tools should NOT need to import an SDK or tightly couple to x401 to issue ACTs. The protocol provides three integration paths at increasing levels of depth. The API and CLI are first-class, not afterthoughts.

**Path 1: HTTP API (zero dependencies)**

Pure REST. Works from any language, any framework. Three HTTP calls, no imports.

```
# 1. Request authorization
POST https://api.x401.dev/authorize
Content-Type: application/json

{
  "agent_did": "did:key:z6MkAgent...",
  "cap": [
    { "uri": "github:acme/backend/push:branch:staging", "lim": { "cnt": 20, "per": 86400 } }
  ],
  "reason": "Deploy hotfix for checkout crash",
  "exp": 86400
}

→ 200 OK
{
  "request_id": "abc123",
  "consent_url": "https://auth.x401.dev/consent/abc123",
  "poll_endpoint": "https://api.x401.dev/poll/abc123",
  "expires_in": 600
}

# 2. Show consent_url to the human (open in browser, render inline, display QR code, etc.)
#    The tool decides how. The protocol doesn't care.

# 3. Poll until approved
GET https://api.x401.dev/poll/abc123
→ { "status": "pending" }
→ { "status": "pending" }
→ { "status": "authorized", "act": "eyJhbGciOiJFZERTQSIs..." }

# 4. Tool captures the ACT, attaches to agent requests
```

This is the most universal path. Any tool that can make HTTP calls can integrate. No binary dependency, no package import, no version conflicts. The tool owns its own UX for presenting the consent URL to the human.

**Path 2: CLI binary (shell out)**

The `x401` CLI wraps the API. The agent tool shells out to it and captures the ACT from stdout. Same pattern as `gh auth login`, `gcloud auth`, `aws configure`.

```bash
# Interactive: opens browser, polls, prints ACT to stdout
x401 authorize \
  --cap "github:acme/backend/push:branch:staging" \
  --lim "cnt:20,per:86400" \
  --exp 24h \
  --reason "Deploy hotfix"

# → Opens consent page in browser
# → Waits for human approval
# → Prints ACT JWT to stdout

# Headless: prints device code instead of opening browser
x401 authorize --headless \
  --cap "github:acme/backend/push:branch:staging" \
  --lim "cnt:20,per:86400" \
  --exp 24h \
  --reason "Deploy hotfix"

# → Prints: "Authorize at https://auth.x401.dev/consent/abc123 — code: WXYZ-1234"
# → Polls, prints ACT to stdout when approved
```

The tool calls `x401 authorize`, captures stdout, done. Zero knowledge of the protocol internals. Works from Python, Go, Rust, Node, shell scripts, anything that can exec a process.

The CLI also handles proof generation for subsequent requests:

```bash
# Generate a proof-of-possession for a specific request
x401 proof \
  --act ./my-act.jwt \
  --method POST \
  --url "https://gateway.x401.dev/gmail/send"

# → Prints proof JWT to stdout
# Tool attaches as X-X401-Proof header
```

**Path 3: SDK (deep integration)**

For tools that want tight integration — automatic proof generation on every request, ACT caching, token refresh, multi-ACT management. This is optional and additive. Nobody needs it for basic flows.

```typescript
import { X401Client } from '@x401/sdk';

const client = new X401Client({ act: myACT, privateKey: agentKey });

// Auto-generates proof, attaches ACT, handles refresh
const response = await client.fetch('https://gateway.x401.dev/gmail/send', {
  method: 'POST',
  body: JSON.stringify({ to: 'bob@co.com', subject: 'Update', body: '...' })
});
```

#### Integration spectrum summary

| Path | Dependency | Coupling | Effort | Best for |
|---|---|---|---|---|
| **HTTP API** | None | Zero — pure HTTP calls | 3 API calls | Any language, any framework, maximum flexibility. Tools that don't want any x401 dependency. |
| **CLI binary** | `x401` on PATH | Minimal — shell out, capture stdout | Install binary, exec process | Agent tools that already shell out to CLIs (most of them). Quick integration. |
| **SDK** | `@x401/sdk` package | Tight — import and call methods | Add dependency, use client API | Deep integration with auto-proofs, caching, refresh. Tools that want to own the full lifecycle. |

The API and CLI should be the default recommendation for agent tool developers. The SDK is for power users who want convenience features. This keeps x401 adoption lightweight — a tool can integrate in an afternoon with a few HTTP calls, no dependency review, no package conflicts.

### Mode D: Pre-signed (programmatic)

For CI/CD, scripts, and power users who want to create delegations without a consent server.

```bash
# On-chain + off-chain capabilities in one grant
x401 grant \
  --to did:key:zQ3shAgent... \
  --cap "solana:mainnet/spl:EPjFW.../transfer" \
  --limit "amt:100000000,per:86400" \
  --cap "gmail:alice@example.com/send:domain:example.com" \
  --limit "cnt:50,per:86400" \
  --cap "github:acme/backend/push:branch:staging" \
  --limit "cnt:20,per:86400" \
  --exp 24h \
  --reason "Daily rebalancing with status reports" \
  --sign-with ~/.x401/key.json \
  --output act.jwt
```

### Token Refresh

When an ACT expires, the agent must re-obtain authorization. Two patterns:

**1. Refresh token (like OAuth)**:
The consent server issues a `refresh_token` alongside the ACT. The agent uses it to get a new ACT without re-prompting the human (up to a max refresh window).

**2. Standing delegation**:
The human signs a long-lived delegation (e.g., 30 days) but the agent mints short-lived ACTs (1h) from it locally. More decentralized, no consent server needed for refresh.

---

## 3. Verification

### Off-chain Verification (API middleware)

```typescript
import { verifyACT } from '@x401/verify';

app.get('/api/data', verifyACT({ require: 'https://api.example.com/data:read' }), handler);
```

Verification algorithm: decode JWT → verify agent sig → **verify proof of possession** (check `X-X401-Proof` signature matches ACT's `iss` key, validate freshness + replay) → check time bounds → verify delegation chain (walk to root, check each sig + attenuation) → capability match → rate/amount limit check → optional revocation check.

### On-chain Verification

**EVM (Solidity):** Uses `ecrecover` for secp256k1 sigs. ~50-80K gas. See full contract in implementation appendix.

**Solana (Anchor/Rust):** Uses native Ed25519 program. ~5,000-6,000 compute units for a 2-sig chain (~2,280 CU per Ed25519 sig verify + account reads/writes). See Anchor program above in chain section.

### Token Binding: Proof of Possession (Off-chain)

ACTs are bearer tokens. The agent signs the JWT, proving it created the token. But once the signed JWT is on the wire (in an HTTP header), anyone who intercepts it can present it from a different machine. The JWT signature proves the agent *created* the ACT, but not that the *presenter* is the agent.

**On-chain this is already solved.** The transaction itself is signed by the agent's wallet key. The chain verifies the signature matches the agent's address. You can't submit a transaction from someone else's key. No additional mechanism needed.

**Off-chain is the gap.** The protocol uses DPoP-style proof of possession (inspired by RFC 9449) to close it. Alongside the ACT, the agent sends a fresh proof JWT signed by its private key, bound to the specific request.

#### HTTP presentation format

```
POST /gmail/send HTTP/1.1
Host: gateway.x401.dev
Authorization: ACT eyJhbGciOiJFZERTQSIs...
X-X401-Proof: eyJ0eXAiOiJhY3QtcG9wK2p3dCIs...
```

#### Proof JWT structure

```json
// Header
{
  "typ": "act-pop+jwt",
  "alg": "EdDSA"
}
// Payload
{
  "ath": "sha256-of-the-ACT",
  "htm": "POST",
  "htu": "https://gateway.x401.dev/gmail/send",
  "htb": "sha256-of-request-body",
  "iat": 1708300000,
  "jti": "unique-nonce-abc123"
}
// Signed by agent's private key (same key as ACT's iss DID)
```

| Field | Type | Description |
|---|---|---|
| `ath` | string | SHA-256 hash of the ACT JWT. Binds this proof to a specific token. |
| `htm` | string | HTTP method of the request. |
| `htu` | string | Target URL of the request. Prevents proof reuse against different endpoints. |
| `htb` | string | SHA-256 hash of the request body. Prevents body swapping by a MITM. Required for POST/PUT/PATCH. Omit for GET/DELETE. |
| `iat` | unix timestamp | When the proof was created. Verifier rejects if older than 60 seconds. |
| `jti` | string | Unique nonce. Verifier maintains a short-lived replay cache to reject duplicates. |

#### Verification steps

1. Verify ACT (normal JWT + delegation chain verification)
2. Decode proof JWT
3. Verify proof signature matches the public key in the ACT's `iss` DID
4. Verify `ath` matches SHA-256 of the presented ACT (binds proof to this specific token)
5. Verify `htm` and `htu` match the current HTTP request (binds to this specific call)
5a. For POST/PUT/PATCH: verify `htb` matches SHA-256 of the request body (prevents body swapping)
6. Verify `iat` is within the freshness window (recommended: 60 seconds)
7. Verify `jti` hasn't been seen before (replay cache, entries expire after the freshness window)

Cost: one additional signature verification. Negligible.

#### What this prevents

- **Stolen ACT replay**: Intercepting the ACT is useless without the agent's private key to generate valid proofs.
- **Proof replay**: Each proof is bound to a specific HTTP method + URL + timestamp. Intercepting a proof doesn't let you replay it against a different endpoint or after the freshness window.
- **Cross-agent token sharing**: Agent A can't hand its ACT to Agent B for use. Agent B can't generate proofs because it doesn't have Agent A's private key. (Sub-delegation via the `dlg` chain is the correct way to share capabilities.)

#### When token binding is required

| Context | Token binding | Why |
|---|---|---|
| Off-chain API / gateway | **Required** | This is where interception risk lives. HTTPS protects in transit but not at rest (logs, proxies, debugging tools). |
| On-chain verification | **Not needed** | Transaction signature already proves possession of the agent's key. |
| Internal / trusted network | **Opt-out** | Services behind a VPN or service mesh can skip the proof if they accept the tradeoff. The `verifyACT()` middleware accepts a `requireProof: false` option. |

#### SDK support

The agent SDK handles proof generation automatically. The developer never constructs proofs manually.

```typescript
import { X401Client } from '@x401/sdk';

const client = new X401Client({ act: myACT, privateKey: agentKey });

// Proof generated and attached automatically
const response = await client.fetch('https://gateway.x401.dev/gmail/send', {
  method: 'POST',
  body: JSON.stringify({ to: 'bob@co.com', subject: 'Update', body: '...' })
});
```

The `verifyACT()` middleware on the service side checks the proof by default:

```typescript
import { verifyACT } from '@x401/verify';

// Proof required by default
app.post('/gmail/send', verifyACT({ require: 'gmail:alice@co.com/send' }), handler);

// Opt out for internal services
app.get('/internal/status', verifyACT({ require: 'internal:status', requireProof: false }), handler);
```

### As an ERC-7710 Caveat Enforcer

Bridge x401 into MetaMask's delegation framework:

```solidity
contract X401CaveatEnforcer is CaveatEnforcer {
    IX401Verifier public immutable verifier;

    function beforeHook(
        bytes calldata _terms,
        bytes calldata _args,
        ModeCode _mode,
        bytes calldata _executionCalldata,
        bytes32 _delegationHash,
        address _delegator,
        address _redeemer
    ) public override {
        ACTProof memory proof = abi.decode(_args, (ACTProof));
        (address target, uint256 value, bytes memory callData) = _decodeExecution(_executionCalldata);
        require(verifier.verify(proof, target, value, bytes4(callData)), "X401Enforcer: unauthorized");
    }
}
```

---

## 4. Revocation

Three mechanisms, fastest to slowest:

**Instant (on-chain):** `verifier.revoke(jti)` — ~25K gas on EVM, ~200 CU on Solana. Immediate effect for all on-chain actions.

**Fast (hosted endpoint):** POST to revocation endpoint. Off-chain verifiers poll or subscribe via WebSocket. Propagation: seconds to minutes.

**Passive (expiry):** Protocol recommends 1h default token expiry. Tokens naturally expire. Agents refresh via consent flow.

**Emergency (nonce rotation):** Invalidate ALL outstanding ACTs from a human across all agents. Nuclear option.

---

## 5. On-Chain Limit Enforcement for Off-Chain Services

### The problem

ACTs are self-contained bearer tokens. On-chain, the verifier program tracks usage in global state (spending counters, rate windows). Off-chain, each service verifier tracks limits independently. An ACT with `cnt: 50` presented to 10 independent servers could theoretically get 500 total uses, because no single server sees the full picture.

For single-service capabilities (e.g., `gmail:alice@co.com/send`), this isn't a real problem — Gmail is the only verifier, so its counter is the global counter. But for capabilities verified by multiple services, or for high-stakes limits where the human needs hard enforcement, per-verifier counting is insufficient.

### The solution: on-chain as the global counter

Use an on-chain limit account as the single source of truth, even for off-chain actions. The chain tracks usage. Off-chain services read the chain before serving requests.

**How it works:**

1. Human signs an ACT with limits. A **limit account** is created on-chain (one-time transaction) storing the caps, counters, and period windows.
2. Agent wants to perform action #37 of 50.
3. Agent submits a **usage increment** transaction to the x401 verifier contract on-chain.
4. The on-chain program checks: 36 + 1 = 37 ≤ 50. If within limits, updates the counter and emits a receipt event.
5. Agent calls the off-chain API with the ACT + the on-chain transaction signature as proof of increment.
6. Off-chain service verifies: (a) ACT is valid (local JWT check), (b) the increment receipt is a valid recent transaction for this `jti` and capability.
7. Service serves the request.

Global enforcement, on-chain source of truth, off-chain service only needs to read (not write) the chain.

### Dual-chain support: Solana + Base

The protocol supports both chains for limit enforcement. Different use cases favor different chains.

**Solana** — best for full ACT verification on-chain (cheap Ed25519 via native Ed25519 program). The verifier program can verify the complete delegation chain + enforce limits in one transaction. Ideal when the agent's primary operations are on Solana (DeFi, SPL transfers).

**Base (Ethereum L2)** — best for gasless limit enforcement via paymasters. Base supports ERC-4337 account abstraction. A paymaster (run by the consent server or the protocol) sponsors gas for counter increments, making them literally free to the agent. The agent never needs to hold ETH.

| | Solana | Base |
|---|---|---|
| Counter increment cost | ~5000 lamports (~$0.001) | ~30-50K gas (~$0.0001 at typical Base prices) |
| With paymaster | N/A (no native AA) | Free to agent (paymaster sponsors) |
| Full ACT chain verification | ~5,000-6,000 CU for 2-sig chain (~2,280 CU per Ed25519 sig) | Expensive for Ed25519, cheap for secp256k1 via ecrecover (~3,000 gas) |
| Finality | ~400ms | ~2 seconds (L2 confirmation) |
| Best for | On-chain agent operations (DeFi, SPL) | Off-chain limit enforcement (APIs, email, code) |

The agent chooses the chain based on context:
- Agent doing Jupiter swaps → Solana verifier for both ACT verification and limit tracking
- Agent calling off-chain APIs → Base limit account with paymaster-sponsored increments
- Agent doing both → Limit accounts on both chains, one per domain

### Base limit enforcement flow (detailed)

```
Agent wants to send email #37 of 50

1. Agent calls x401LimitEnforcer.increment(jti, capHash, 1)
   → Paymaster sponsors gas (agent pays nothing)
   → Contract checks: 36 + 1 = 37 ≤ 50 ✓
   → Contract updates counter, emits IncrementEvent(jti, capHash, 37, txHash)
   → Agent gets transaction receipt

2. Agent calls Gmail gateway with:
   Authorization: ACT eyJhbGci...
   X-X401-Receipt: base:0xabc123...  (Base transaction hash)

3. Gmail gateway verifies:
   a. ACT signature and delegation chain (local JWT check, fast)
   b. Receipt exists on Base and is recent (RPC read, free, ~100ms)
   c. Receipt matches this jti and capability
   d. Receipt has NOT been consumed before (gateway maintains a receipt-consumed set, keyed by tx hash)
   e. Gateway marks receipt as consumed
   f. Proceed → send email via Gmail API
```

### Solidity: Base limit enforcer

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract X401LimitEnforcer {
    struct LimitAccount {
        address human;          // Who authorized (only they can create/revoke)
        address agent;          // Authorized agent (only they can increment)
        bytes32 jti;            // ACT unique ID
        bool revoked;
    }

    struct CapabilityCounter {
        uint256 maxCount;       // Max actions per period
        uint256 currentCount;   // Actions in current period
        uint256 periodLength;   // Period in seconds
        uint256 periodStart;    // When current period started
    }

    // jti => LimitAccount (one per ACT)
    mapping(bytes32 => LimitAccount) public limits;
    // keccak256(jti, capHash) => CapabilityCounter (one per capability per ACT)
    mapping(bytes32 => CapabilityCounter) public counters;

    event LimitCreated(bytes32 indexed jti, address indexed human, address indexed agent);
    event CapabilityRegistered(bytes32 indexed jti, bytes32 capHash, uint256 maxCount, uint256 periodLength);
    event Incremented(bytes32 indexed jti, bytes32 indexed capHash, uint256 newCount, uint256 remaining);
    event Revoked(bytes32 indexed jti, address revoker);

    /// @notice Create a limit account for an ACT. Only callable by the human (ACT signer).
    function createLimit(
        bytes32 jti,
        address agent,
        bytes32[] calldata capHashes,
        uint256[] calldata maxCounts,
        uint256[] calldata periodLengths
    ) external {
        require(limits[jti].human == address(0), "already exists");
        require(capHashes.length == maxCounts.length && maxCounts.length == periodLengths.length, "length mismatch");

        limits[jti] = LimitAccount({
            human: msg.sender,
            agent: agent,
            jti: jti,
            revoked: false
        });

        for (uint256 i = 0; i < capHashes.length; i++) {
            bytes32 key = keccak256(abi.encodePacked(jti, capHashes[i]));
            counters[key] = CapabilityCounter({
                maxCount: maxCounts[i],
                currentCount: 0,
                periodLength: periodLengths[i],
                periodStart: block.timestamp
            });
            emit CapabilityRegistered(jti, capHashes[i], maxCounts[i], periodLengths[i]);
        }

        emit LimitCreated(jti, msg.sender, agent);
    }

    /// @notice Increment usage for a specific capability. Only callable by the authorized agent.
    function increment(bytes32 jti, bytes32 capHash, uint256 count) external returns (uint256 remaining) {
        LimitAccount storage acc = limits[jti];
        require(!acc.revoked, "revoked");
        require(acc.human != address(0), "not found");
        require(msg.sender == acc.agent, "unauthorized: only the authorized agent can increment");

        bytes32 key = keccak256(abi.encodePacked(jti, capHash));
        CapabilityCounter storage ctr = counters[key];
        require(ctr.maxCount > 0, "capability not registered");

        // Reset period if expired
        if (block.timestamp >= ctr.periodStart + ctr.periodLength) {
            ctr.currentCount = 0;
            ctr.periodStart = block.timestamp;
        }

        ctr.currentCount += count;
        require(ctr.currentCount <= ctr.maxCount, "limit exceeded");

        remaining = ctr.maxCount - ctr.currentCount;
        emit Incremented(jti, capHash, ctr.currentCount, remaining);
    }

    /// @notice Revoke an ACT's limit account. Only callable by the human.
    function revoke(bytes32 jti) external {
        require(msg.sender == limits[jti].human, "unauthorized");
        limits[jti].revoked = true;
        emit Revoked(jti, msg.sender);
    }

    /// @notice Read remaining count for a capability. Free via RPC.
    function remaining(bytes32 jti, bytes32 capHash) external view returns (uint256) {
        LimitAccount storage acc = limits[jti];
        if (acc.revoked) return 0;

        bytes32 key = keccak256(abi.encodePacked(jti, capHash));
        CapabilityCounter storage ctr = counters[key];
        if (block.timestamp >= ctr.periodStart + ctr.periodLength) return ctr.maxCount;
        if (ctr.currentCount >= ctr.maxCount) return 0;
        return ctr.maxCount - ctr.currentCount;
    }
}
```

### Enforcement tiers

The human chooses the enforcement level when signing the ACT:

| Tier | Enforcement | Use case |
|---|---|---|
| `"enforce": "onchain"` | Hard. On-chain counter, receipt required. | Spending, email sending, code pushes, anything high-stakes |
| `"enforce": "verifier"` | Soft. Per-verifier counters. | API rate limits, read operations, low-stakes actions |
| `"enforce": "none"` | Token carries the limit but enforcement is advisory. | Informational caps, best-effort limits |

The enforcement tier is specified per-capability in the ACT:

```json
{
  "cap": [
    {
      "uri": "gmail:alice@co.com/send:domain:co.com",
      "lim": { "cnt": 50, "per": 86400 },
      "enforce": "onchain",
      "chain": "eip155:8453"
    },
    {
      "uri": "https://api.example.com/data:read",
      "lim": { "rate": [1000, 3600] },
      "enforce": "verifier"
    }
  ]
}
```

### Why this works

- **Global enforcement** — one counter, one source of truth, no double-spending across verifiers
- **Free to the agent on Base** — paymasters sponsor gas for counter increments
- **Off-chain services stay simple** — they verify the ACT locally (JWT check) and verify the receipt via RPC read (free). No blockchain writes, no wallet needed.
- **Opt-in complexity** — low-stakes capabilities use per-verifier enforcement (no chain dependency). High-stakes capabilities use on-chain enforcement. The human decides.
- **Composable with both chains** — Solana for on-chain operations, Base for off-chain limit enforcement, or either for both

### Open questions

- **Liveness dependency**: If Base goes down, agents can't increment counters and off-chain services with `enforce: "onchain"` will reject requests. Mitigation: fall back to per-verifier enforcement with a flag indicating the chain was unreachable. The service decides whether to accept degraded enforcement.
- **Paymaster economics**: Who funds the paymaster? The consent server (as part of the hosted service fee)? The protocol foundation? The human? Likely the consent server, as part of the Pro/Enterprise tier.
- **Multi-capability increments**: If an ACT has 5 capabilities with on-chain enforcement, does the agent submit 5 transactions per action or one batched transaction? Batched is better — one transaction increments all relevant counters atomically.
- **Receipt freshness**: How recent must a receipt be? Recommended: within the last 60 seconds. Prevents agents from stockpiling receipts.
- **Receipt single-use**: Each receipt (identified by on-chain tx hash) MUST be consumed at most once by a given gateway. Gateways maintain a receipt-consumed set (tx hashes, expiring after the freshness window). For multi-instance gateway deployments, this set must be shared (e.g., Redis, database) to prevent the same receipt being accepted by different instances concurrently.

---

## 6. Progressive Authorization (Agent-Initiated Permission Requests)

Agents don't always know upfront what they'll need. An agent exploring a task might discover mid-operation that it needs access to a service or capability it wasn't pre-authorized for. The protocol needs a standard way for agents to request additional permissions from the human.

### The flow

1. Agent sends a request to a service
2. Service responds with HTTP 401 + the required capability URI
3. Agent checks its ACTs — doesn't have the required capability
4. Agent sends a **permission request** to the human
5. Human reviews and signs a new ACT granting the additional capability
6. Agent retries with the new ACT

The agent ends up carrying multiple ACTs (one per authorization event). It presents the relevant one per service based on which capability is needed. This is simpler than amending a signed credential, which would break the cryptographic chain.

### Permission request format

The agent sends a structured request to the consent server, which routes it to the human:

```json
{
  "type": "permission_request",
  "agent_did": "did:key:z6MkAgent...",
  "requested_cap": [
    {
      "uri": "github:acme/frontend/push:branch:main",
      "lim": { "cnt": 5, "per": 86400 }
    }
  ],
  "reason": "Staging tests passed for hotfix #427. Need to push to main because the bug is blocking production checkout.",
  "trigger": "401 from github:acme/frontend/push:branch:main",
  "context": {
    "current_task": "Deploy hotfix for checkout crash",
    "existing_caps": ["github:acme/frontend/push:branch:staging"]
  },
  "proposed_exp": 3600,
  "urgency": "high"
}
```

Key fields:
- `reason`: Why the agent needs this now. Displayed verbatim in the consent UI.
- `trigger`: What caused the request (typically the 401 response).
- `context`: What the agent is currently doing and what it already has access to. Helps the human make an informed decision.
- `urgency`: Hint for notification priority. `high` = push notification, `normal` = queued for next check-in.

### Delivery channels

How the request reaches the human depends on the context:

**On-chain (wallet message).** For crypto-native users, the permission request is sent as a message to the human's wallet address. Wallet apps (Phantom, MetaMask) surface it as a signing request. The human reviews the requested capabilities and signs a new delegation directly in the wallet. This is the most natural flow for on-chain use cases — the agent needs permission, the wallet asks for it.

**Push notification (consent server).** The consent server sends a push notification to the human's device (via Guardian-style app, or native mobile push). Human taps, reviews the request in the consent UI, signs. Similar to CIBA but scoped to new capability grants, not per-action approval.

**Device grant (poll/SSE).** For cases where the agent has a terminal or UI, it displays a code. The human goes to the consent server, enters the code, reviews and signs. Same flow as initial authorization, just triggered mid-operation.

**In-app.** If the human is actively using an app that integrates with the agent (e.g., a chat interface, dashboard), the permission request surfaces inline. Best UX for interactive agent use cases.

**Email/SMS.** Fallback for low-urgency requests. Link to consent page. Human reviews and signs at their convenience.

### Batching

If an agent discovers it needs multiple new capabilities, it SHOULD batch them into a single permission request rather than sending separate notifications. The consent UI renders all requested capabilities on one screen, and the human signs one delegation covering all of them (or selectively approves a subset).

```json
{
  "type": "permission_request",
  "agent_did": "did:key:z6MkAgent...",
  "requested_cap": [
    { "uri": "github:acme/frontend/push:branch:main", "lim": { "cnt": 5, "per": 86400 } },
    { "uri": "slack:acme/post:deployments", "lim": { "cnt": 10, "per": 86400 } },
    { "uri": "gmail:ops@acme.com/send:domain:acme.com", "lim": { "cnt": 5, "per": 86400 } }
  ],
  "reason": "Deploying hotfix #427 to production. Need to push to main, notify #deployments, and email the ops team.",
  "trigger": "401 from github:acme/frontend/push:branch:main"
}
```

Human sees one consent screen with three capabilities. Can approve all, some, or none.

### Delegation chain escalation

When a sub-agent needs a capability its parent doesn't have:

1. Sub-agent asks its parent agent for the capability
2. Parent checks its own ACT — if it has the capability with enough headroom, it sub-delegates
3. If the parent doesn't have it, the parent escalates to ITS parent (or directly to the human)
4. The request bubbles up the chain until it reaches someone with authority to grant it
5. New delegation flows back down the chain, with attenuation at each hop

```
Sub-agent needs github:push:main
  → asks Parent Agent (only has github:push:staging)
    → Parent doesn't have it, escalates to Human
      → Human reviews, signs new ACT for Parent with github:push:main (cnt: 5)
        → Parent sub-delegates to Sub-agent with github:push:main (cnt: 3)
```

### Distinction from Auth0 CIBA

Auth0's CIBA flow sends a push notification for each sensitive ACTION. Agent wants to buy 3 iPhones → push notification → human approves → agent proceeds. This doesn't scale for autonomous agents making hundreds of API calls per day.

x401 progressive authorization is different in a critical way: **the human approves a new CAPABILITY with limits, not a single action.** "You can push to main, up to 5 times today" vs "Can I push this specific commit to main?" The agent gets scoped autonomy for the new capability, not one-shot approval.

| | Auth0 CIBA | x401 Progressive Auth |
|---|---|---|
| Granularity | Per-action approval | Per-capability grant with limits |
| Frequency | Every sensitive action | Once per new capability needed |
| Result | One-time access token | ACT with scoped autonomy |
| Agent autonomy | Blocked until human responds each time | Operates freely within granted limits |
| Scales to 1000 actions/day | No | Yes (approve capability once, agent uses it within limits) |

### Standing grants and pre-approval

For predictable workflows, humans can set up standing grants: "If this agent ever needs calendar access, auto-approve up to read-only with these limits." The consent server stores standing grant rules and auto-issues ACTs when the pattern matches, without prompting the human.

```json
{
  "type": "standing_grant",
  "agent_did": "did:key:z6MkAgent...",
  "auto_approve": [
    {
      "uri_pattern": "gcal:alice@acme.com/*",
      "max_lim": { "rate": [100, 3600] },
      "max_exp": 86400
    },
    {
      "uri_pattern": "slack:acme/read:*",
      "max_lim": { "rate": [500, 3600] },
      "max_exp": 86400
    }
  ],
  "require_approval": [
    "*/push:branch:main",
    "*/delete:*",
    "*/transfer"
  ]
}
```

This gives the human a declarative policy: auto-approve safe capabilities, always ask for dangerous ones. The agent gets fast access for routine needs without waiting for human response.

### Open questions for this flow

- **Timeout**: How long should an agent wait for human approval before giving up or trying an alternative approach? Recommended: configurable, default 5 minutes for high urgency, 1 hour for normal.
- **Partial approval**: Human approves some requested capabilities but not others. Agent needs to handle partial grants gracefully.
- **Audit**: Every permission request and response (approved, denied, partial, timed out) is logged. This becomes part of the authorization audit trail.
- **Rate limiting requests**: An agent shouldn't spam the human with permission requests. The consent server should rate-limit requests per agent (e.g., max 10 per hour) and encourage batching.

---

## 7. Composition with x402

When an API requires both authorization and payment:

```
GET /api/premium-data HTTP/1.1
Host: api.example.com

→ HTTP/1.1 402 Payment Required
  WWW-Authenticate: ACT realm="api.example.com", cap="https://api.example.com/data:read"
  PAYMENT-REQUIRED: <base64 PaymentRequired JSON>
```

Agent resolves both:
```
GET /api/premium-data HTTP/1.1
Authorization: ACT eyJhbGciOiJFUzI1NksiLC...
PAYMENT-SIGNATURE: <base64 PaymentPayload JSON>
```

Wallet linking: the protocol specifies that the payment wallet SHOULD be verifiably linked to the ACT (same human wallet, delegated agent wallet, or facilitator-verified).

---

## 8. Developer Surface

Three layers, increasing depth. Most integrations only need the first.

### HTTP API (`api.x401.dev`)

The foundational integration layer. Zero dependencies. Any language, any framework.

- `POST /authorize` — request authorization, get consent URL + poll endpoint
- `GET /poll/{id}` — poll for human approval, receive ACT
- `POST /revoke` — revoke an ACT by `jti`
- `GET /verify` — verify an ACT (optional; services can verify locally, but this endpoint exists for tools that don't want to implement JWT verification)
- `POST /proof` — generate a proof-of-possession JWT (optional; for tools that don't want to implement signing locally)

### CLI (`x401`)

Wraps the API. Standalone binary, installable via `brew install x401`, `npm install -g @x401/cli`, or direct download.

- `x401 authorize` — interactive consent flow (opens browser or prints device code), prints ACT to stdout
- `x401 grant` — pre-sign a delegation locally (Mode D, no server)
- `x401 proof` — generate a proof-of-possession for a request, prints to stdout
- `x401 verify` — verify an ACT locally (offline, no API call)
- `x401 revoke` — revoke an ACT by `jti`
- `x401 inspect` — decode and pretty-print an ACT (capabilities, limits, delegation chain, expiry)

### SDK packages

For deep integration. Optional — the API and CLI cover all basic flows.

- `@x401/sdk` — agent-side client. Auto-proof generation, ACT caching, token refresh, multi-ACT management.
- `@x401/verify` — server/service middleware. `verifyACT()` Express/Fastify/Hono middleware with proof-of-possession checking.
- `@x401/react` — consent UI components. Reference React components for inline consent flows.
- `@x401/contracts` — EVM Solidity verifier + limit enforcer contracts.
- `@x401/anchor` — Solana Anchor verifier program.
- `@x401/adapters` — service-specific capability translators (Gmail, GitHub, Slack, etc.) for gateway use.

---

## 9. Product: Hosted Consent Server

`auth.x401.dev` — "Auth0 for the Agent Era"

The consent server handles the human-facing side: rendering the authorization screen, managing wallet/passkey signing, issuing ACTs, and handling revocation. Any service can verify ACTs independently without the consent server (that's the point of self-contained JWTs), but the consent server makes it easy to get started and handles the UX.

**Free tier:** 1K consent flows/month, basic revocation. **Pro ($99/mo):** unlimited, webhooks, audit dashboard, custom consent UI. **Enterprise:** self-hosted, fleet management, compliance reporting, SSO integration.

Revenue model: protocol is free and open source. Hosted service is the business. Same as Auth0 (OAuth), Vercel (Next.js), Pimlico (ERC-4337).

### Go-to-market

**Phase 1 (months 1-3):** Ship SDKs + reference server. Target MCP server authors and agent framework developers. The pitch: "add one middleware and your MCP server can verify which human authorized the agent calling it." This is the trojan horse — every MCP server that adopts ACT verification becomes a node in the protocol.

**Phase 2 (months 3-6):** x402 integration. Solana on-chain verifier. Target API providers and DeFi protocols. The pitch: "agents can prove authorization AND pay you in one request." Submit SIP (Solana Improvement Proposal) for the verifier program.

**Phase 3 (months 6-12):** IETF draft for the off-chain protocol. ERC for the EVM verifier. Foundation. Wallet provider integrations (Phantom, MetaMask). The pitch to wallets: "your users' agents are already presenting ACTs — add native support for signing them."

**Phase 4 (months 12+):** Service-specific capability registries. Native x401 adoption by major services. The protocol becomes the universal agent authorization layer.

### Capability Gateways: How x401 Works Without Service Adoption

The biggest adoption question for x401: why would Gmail, GitHub, or Slack add x401 middleware to their APIs? The honest answer is they won't, at least not initially. These services have working auth systems. They don't need a new protocol.

x401 doesn't require them to. The protocol works through **capability gateways** — proxy services that verify x401 tokens on the front end and call existing APIs with native credentials on the back end. Existing services don't change at all.

#### How it works

```
              Capability Gateway: Works Without Service Adoption

  ┌──────────┐        ┌─────────────────────────┐        ┌───────────────┐
  │          │        │   Capability Gateway     │        │   Existing    │
  │  Agent   │        │                         │        │   Service     │
  │          │        │  • Verify ACT (local)   │        │               │
  │ carries  │        │  • Enforce x401 limits  │        │  Gmail        │
  │ ACT      │        │  • Translate to native  │        │  GitHub       │
  │          │        │    API calls            │        │  Slack        │
  └────┬─────┘        └────────────┬────────────┘        └───────┬───────┘
       │                           │                             │
       │  Authorization: ACT eyJ.. │                             │
       │──────────────────────────▶│                             │
       │                           │                             │
       │                 ┌─────────┴─────────┐                   │
       │                 │ verify ACT       ✓│                   │
       │                 │ check limits     ✓│                   │
       │                 │ domain: @co.com? ✓│                   │
       │                 │ count: 37/50?   ✓│                   │
       │                 └─────────┬─────────┘                   │
       │                           │                             │
       │                           │  OAuth token / API key      │
       │                           │────────────────────────────▶│
       │                           │                             │
       │                           │  API response               │
       │                           │◀────────────────────────────│
       │                           │                             │
       │  result                   │                             │
       │◀──────────────────────────│                             │

       The agent never touches the real credentials.
       The service has no idea x401 exists.
```

The gateway is an **x401-to-OAuth bridge**. It translates x401 capabilities into native API actions. The agent sees one credential (its ACT). The gateway sees two credentials (the ACT from the agent, the OAuth token for the service). The service (Gmail) sees a normal OAuth request and has no idea x401 exists.

#### How this compares to Auth0's Token Vault

Auth0's Token Vault has a similar architecture: it stores OAuth tokens and gives agents access to them. The core pattern is the same — something sits between the agent and the service, holding credentials. The differences are in how the agent authenticates to the gateway and what controls are available.

```
  Auth0 Token Vault:

  Agent ──── Auth0 JWT ────▶ Auth0 ──── fetch token ────▶ Gmail API
                              │  (round-trip to Auth0)
                              │  sensitive action?
                              │  → CIBA push notification
                              │  → wait for human approval
                              │  → then proceed

  ─────────────────────────────────────────────────────────────────

  x401 Gateway:

  Agent ──── ACT ────▶ Gateway ──── OAuth token ────▶ Gmail API
                         │  (verify locally, no round-trip)
                         │  check limits: 37/50 emails ✓
                         │  check domain: @co.com ✓
                         │  → proceed immediately
```

The practical differences: x401's ACT carries the full authorization scope and limits in the token itself, so the gateway can verify and enforce without calling any external service. Auth0's Token Vault enforces policies server-side in Auth0's infrastructure. The agent-facing credentials are also different — one ACT across all services vs. separate OAuth tokens fetched per service.

#### What the gateway stores

For each human who has set up the gateway:

| Service | Stored Credential | How Obtained |
|---|---|---|
| Gmail | OAuth refresh token | Human connected Gmail during gateway setup (standard OAuth consent) |
| GitHub | Fine-grained PAT or OAuth token | Human authorized during setup |
| Slack | Bot token or user token | Human installed Slack app during setup |
| Calendar | OAuth refresh token | Same as Gmail (Google OAuth) |

The human does one-time setup per service: connect their accounts to the gateway (standard OAuth flow). After that, agents present ACTs to the gateway, and the gateway handles the translation.

#### Gateway-enforced capability constraints

The gateway doesn't just proxy API calls. It actively enforces x401 capability restrictions that the underlying service may not support:

| x401 Capability | Gateway Enforcement | Native Service Support |
|---|---|---|
| `gmail:send:domain:co.com` | Gateway checks recipient domain before calling Gmail API | Gmail has no domain restriction on sending |
| `github:push:branch:staging` | Gateway checks branch name before calling GitHub API | GitHub PATs can't restrict to specific branches |
| `booking:flights/purchase` with `cost: $500` | Gateway checks fare amount before completing booking | Most travel APIs have no per-transaction spending limits |
| `slack:post:engineering` | Gateway checks channel name before posting | Slack tokens can restrict to channels, but not all do |

This is the key insight: **x401 capability gateways can enforce finer-grained restrictions than the underlying services support natively.** The restrictions exist in the ACT (defined by the human), and the gateway enforces them at the translation layer. The underlying service doesn't need to know about x401.

#### Three adoption tiers

The protocol doesn't need universal native adoption to be useful. Three tiers of service integration, all of which work today:

**Tier 1: Native x401 (no gateway needed)**
- New APIs and services built with x401 from day one
- MCP servers that add `verifyACT()` middleware
- On-chain programs (Solana, Base) with x401 verifier
- Any service where the builder controls the auth stack

**Tier 2: Capability gateway (existing services, no changes)**
- Gmail, GitHub, Slack, Calendar, Stripe, etc.
- Gateway verifies ACTs, enforces x401 constraints, proxies to native API
- Human sets up OAuth connections once, agents use ACTs forever
- Hosted gateway at gateway.x401.dev, or self-hostable

**Tier 3: Native adoption by major services (long-term)**
- Services add x401 verification alongside existing auth
- Accept ACTs directly, no gateway needed
- Happens when enough agents present ACTs that it's worth supporting natively
- The gateway creates demand; native adoption follows demand

```
          Three Paths: x401 Works at Every Adoption Level

  ───────────────────────────────────────────────────────────────────

  ON-CHAIN        Agent ──── ACT ────▶ Smart Contract     Zero adoption
  (Tier 1)                             verifies natively   needed. The chain
                                       in VM               IS the verifier.

  ───────────────────────────────────────────────────────────────────

  GATEWAY         Agent ──── ACT ────▶ Gateway ──────────▶ Gmail
  (Tier 2)                             verifies ACT,       GitHub
                                       bridges to          Slack
                                       native API          (no changes)

  ───────────────────────────────────────────────────────────────────

  NATIVE          Agent ──── ACT ────▶ New API Service     One line of
  (Tier 3)                             verifyACT()         middleware.
                                       middleware          Full protocol.

  ───────────────────────────────────────────────────────────────────
```

#### Gateway as a product

The capability gateway is a natural extension of the consent server:

- **Consent server** (auth.x401.dev): handles human authorization → ACT issuance
- **Capability gateway** (gateway.x401.dev): handles ACT verification → service API calls
- **Limit enforcer** (on Base/Solana): handles global limit tracking

Together, these three components form the hosted x401 platform. The protocol is open and free. The hosted platform is the business.

**Pricing**: Free tier (3 services, 1K API calls/month). Pro ($49/mo, unlimited services, 50K calls). Enterprise (self-hosted, custom).

#### Updated go-to-market with gateways

**Phase 1 (months 1-3):** SDKs + consent server + reference gateway. Target MCP servers (native x401) and agent framework developers. Ship gateway adapters for Gmail, GitHub, Slack, Calendar. The pitch: "your agents carry one credential that works across all these services."

**Phase 2 (months 3-6):** On-chain verifiers (Solana + Base). x402 integration. Limit enforcement contracts. The pitch: "agents can prove authorization AND pay you in one request, with hard-enforced limits."

**Phase 3 (months 6-12):** IETF draft. Wallet integrations. More gateway adapters (Stripe, AWS, Twilio, etc.). The pitch: "every service your agent touches, one credential."

**Phase 4 (months 12+):** Native adoption by services. As gateway traffic grows, services add native x401 support to skip the middleman. The protocol becomes the standard.

#### The infrastructure spectrum (honest framing)

Not all domains have the same infrastructure requirements. This matters for how we talk about the protocol.

| Domain | Infrastructure needed | Why |
|---|---|---|
| **On-chain (Solana, Base, EVM)** | **None.** Truly zero dependency. | The chain IS the verifier. Smart contracts verify ACTs natively. No gateway, no consent server, no middleman. The ACT is self-contained and the chain is already running. This is where x401 is purest. |
| **New APIs / MCP servers** | **One middleware line.** Minimal. | Service owner adds `verifyACT()`. Self-verifying JWT, no callbacks, no external dependency. Same trust model as checking a standard JWT. |
| **Existing off-chain services (Gmail, GitHub, Slack)** | **Gateway required.** Honest centralization tradeoff. | These services don't speak x401 and won't anytime soon. Something has to sit between the agent and the service to translate. That something stores OAuth tokens and proxies requests. |

The third category is where the story gets complicated. We say "no vault dependency" and "self-verifying" — and that's true at the agent-facing layer (the ACT is verified locally, no Auth0-style round-trip). But the gateway still stores OAuth tokens and sits in the critical path for legacy services. It's a better vault than Auth0's (pre-authorized limits instead of per-action approval), but it's still a vault.

For crypto and on-chain use cases, x401 is genuinely infrastructure-free. The protocol's purest expression is on-chain: human signs a delegation, agent carries it, smart contract verifies it, done. No servers, no accounts, no intermediaries.

For off-chain legacy services, the gateway is a pragmatic bridge. It works today, it's better than the alternatives, and it creates demand for native adoption. But it's not the end state.

#### Open exploration: reducing gateway dependency

Ideas worth exploring for getting closer to zero-infrastructure off-chain verification. None of these are ready but they're worth keeping in the design space.

**1. Local agent gateway.** The gateway runs on the user's machine (or the agent's runtime) instead of a hosted service. OAuth tokens stay local — never leave the user's device. The agent connects to `localhost`. Eliminates the centralized service but requires the user to run software. Trade: no hosted dependency, but more setup friction.

**2. Browser extension as gateway.** For agents that operate through browser-based environments, a browser extension could carry OAuth tokens and proxy API calls. The ACT is verified in the extension, the extension makes the API call with native credentials. Tokens never leave the browser context. Trade: limited to browser-based agent workflows.

**3. Service-initiated x401 adoption.** As agent traffic grows, services have incentive to accept ACTs directly. A service that sees 10% of its API calls coming through x401 gateways might add native verification to reduce latency and dependency on a third-party gateway. The gateway is the bootstrapping mechanism; native support is the long-term outcome. This is the most realistic path but it's slow.

**4. OAuth token binding in the ACT itself.** What if the ACT could carry an encrypted reference to the OAuth token, decryptable only by the target service? The agent presents the ACT directly to Gmail, Gmail decrypts the embedded OAuth reference, verifies the x401 constraints, and serves the request. No gateway needed. But this requires services to add x401 support (chicken-and-egg) and raises questions about encrypted token lifecycle.

**5. Wallet-native off-chain signing.** For services that support passkeys/WebAuthn, the human's wallet (or passkey) could serve as the signing root for off-chain services too, without OAuth tokens. The service verifies the ACT's delegation chain against the human's passkey. This would work for services that adopt passkey authentication but doesn't help with services that only support OAuth.

The honest answer for now: **on-chain is zero infrastructure, off-chain legacy services need a gateway, and we should keep exploring ways to shrink or eliminate that dependency over time.** The gateway is the pragmatic answer today, not the forever answer.

---

## 10. Auth0 for AI Agents: Why It's Not Enough

Auth0 launched "Auth0 for AI Agents" (GA October 2025). They're the incumbent and they're claiming this space. Worth understanding exactly what they built and where it falls short.

### What Auth0 ships

**Token Vault**: Stores OAuth tokens for third-party services (Google, Slack, GitHub, etc.). Built on RFC 8693 (OAuth Token Exchange). Agent calls Auth0 to fetch a stored token, uses that token to call the external API. Auth0 handles refresh token rotation.

**Async Authorization (CIBA)**: Human-in-the-loop for sensitive actions. Agent wants to do something risky, Auth0 sends a push notification via Guardian app, human approves or denies on their phone, agent gets an access token. Per-action approval flow.

**FGA for RAG**: Fine-grained authorization for document retrieval. Ensures agents only see documents the user is authorized to see. Useful for enterprise RAG pipelines.

**User Authentication**: Standard Auth0 login to establish user identity before the agent operates.

### Architecture: what's centralized and what's not

To be fair to Auth0: they issue standard JWTs that verify locally using JWKS public keys. A service with Auth0's public key can verify an Auth0-issued access token without calling Auth0's servers. This is the same local verification mechanism x401 uses. Auth0 is not "call home on every request."

What IS centralized is the **Token Vault** — the credential management layer for third-party services:

```
Agent needs to call Gmail
  → Agent calls Auth0 Token Vault API (round-trip to Auth0)
  → Auth0 returns stored Gmail OAuth token
  → Agent calls Gmail with that token
  → Token expires? Auth0 refreshes it
```

The agent doesn't carry a portable credential for Gmail. It carries an Auth0 access token that proves identity to Auth0, then asks Auth0's vault for the Gmail token. For multi-service agents (Gmail + GitHub + Slack), every service requires a separate vault fetch and results in a separate, unrelated OAuth token. There's no single credential that represents "what this agent is authorized to do across all services."

### What Auth0 doesn't have

| Gap | Detail |
|-----|--------|
| **No portable cross-service credential** | The agent carries separate OAuth tokens per service, fetched from Auth0's vault. No single credential expressing "this human authorized this agent for these capabilities across these services." An agent talking to Gmail, GitHub, and Slack has 3 unrelated tokens with no common authorization root. |
| **No delegation chains** | Agent can't sub-delegate to another agent with narrower scope. No verifiable chain from human → orchestrator → worker. |
| **No quantitative limits in the token** | Can't express "50 emails/day" or "$100/day" in the credential itself. Limits live in Auth0's policy layer, enforced server-side, not carried by the token. |
| **No on-chain verification** | Entirely web2. Can't verify agent authorization in a smart contract. |
| **No x402 composition** | No concept of combining authorization with payment in a single request. |
| **CIBA per-action approval doesn't scale** | CIBA sends a push notification for each sensitive action. Works for "buy 3 iPhones" but not for an autonomous agent making 1000 API calls/day. x401's approach: pre-authorize capabilities with limits, agent operates freely within them. |
| **Token Vault is a central dependency for multi-service access** | If Auth0 goes down, agents can't fetch tokens for third-party services. Auth0's own JWTs verify locally, but the vault operations don't. |

### The fundamental difference

**Auth0**: "We verify the agent's identity (locally, via JWT). We store the service credentials (centrally, in the vault). We enforce policies (server-side, in our infrastructure)."

**x401**: "The agent carries a self-contained credential with its capabilities, limits, and delegation chain. Any service verifies it independently. No vault, no policy server, no per-service tokens."

Both verify JWTs locally. The difference is what the JWT contains and what infrastructure sits behind it. Auth0's JWT proves identity to Auth0's platform. x401's ACT carries the full authorization story — capabilities, limits, delegation chain — in the token itself, verifiable by anyone.

Auth0 extended OAuth to handle agents. x401 is a new credential format designed for agents from scratch. Auth0's real value is the Token Vault and the enterprise platform around it. x401's value is the portable, self-contained credential that works across services and chains without centralized infrastructure.

### Why Auth0's move is good for x401

Auth0 is educating their entire customer base that agent authorization is a real problem. They're telling thousands of companies "you need to think about what your agents are allowed to do." That market education is expensive and they're doing it for free. When those companies hit the limitations (no delegation chains, no on-chain, no portable credentials, centralized dependency), x401 is the next step.

---

## 11. Protocol Comparison

| | **x401** | **Auth0 for AI** | **OAuth 2.0** | **UCAN** | **ERC-7710** | **Lit/Vincent** |
|---|---|---|---|---|---|---|
| Architecture | Decentralized (self-verifying tokens) | Centralized (token vault) | Centralized (auth server) | Decentralized | On-chain (EVM) | MPC network |
| Format | JWT | OAuth tokens (stored) | JWT | DAG-CBOR | Solidity structs | PKPs |
| Scope | Any domain (on-chain + off-chain) | Off-chain APIs only | Off-chain APIs | Any domain | EVM only | Lit network |
| Agent-native | Yes (designed for autonomous agents) | Partial (OAuth + CIBA bolt-on) | No (human-interactive) | Partial | Yes (on-chain only) | Yes (wallet-centric) |
| Delegation chains | Yes (inline, verifiable) | No | No | Yes (CID refs) | Yes (hash refs) | No |
| Quantitative limits | First-class (spending, count, rate) | In policy layer, not token | Coarse scopes only | Extensible | Via caveats | Via policies |
| Self-verifying | Yes (no callback needed) | JWTs verify locally, but Token Vault requires API call | JWTs verify locally via JWKS (but scopes are per-service, not portable) | Yes | Yes | No |
| On-chain verify | Yes (native per chain) | No | No | Expensive on EVM | Yes (EVM only) | Yes (Lit only) |
| x402 composition | Defined | No | No | No | No | No |
| Cross-service credential | One ACT for all services | Separate token per service | Separate token per service | One token | One delegation | One PKP |
| Non-financial caps | Native (email, code, calendar) | Via OAuth scopes (coarse) | Via scopes (coarse) | Extensible | No | No |
| Headless agent flow | Yes (device grant) | Yes (CIBA) | Partial | No standard flow | N/A | No |
| Human-in-the-loop | Optional (pre-authorized limits) | Required (CIBA per action) | Required (consent screen) | Optional | Optional | Optional |

---

## 12. Open Questions

1. **DID method**: `did:key` (self-sovereign, no resolution) vs `did:pkh` (linked to blockchain address, simpler for on-chain)?
2. **Multi-chain signing UX**: How many wallet signatures per consent flow is acceptable? Each chain ecosystem needs its own sig.
3. **Privacy**: ZK proofs of delegation? "I can prove a human authorized me without revealing which human." Important for healthcare and personal data.
4. **Liability**: If an agent exceeds authorization, who's liable? Protocol defines expectations but can't resolve legal questions.
5. **Standard body**: IETF (off-chain protocol) + SIP (Solana verifier) + ERC (EVM verifier)? Probably all three since the protocol spans domains.
6. **Naming**: Working title is x401 (mirrors x402 naming, HTTP 401 = authorization). Alternatives: Agent Delegation Protocol (ADP), Agent Capability Authorization Protocol (ACAP).
7. **Solana-first for on-chain**: Confirmed — reference implementation targets Solana first given speed/cost advantages. EVM verifier follows.
8. **Off-chain capability enforcement**: On-chain, the verifier program can enforce limits directly. Off-chain, services need adapters that translate ACT capabilities into native API permissions (e.g., ACT `gmail:send` → Gmail API scope). How standardized should these adapters be? Should the protocol define them or leave it to the ecosystem?
9. **Authentication for off-chain-only use cases**: If a human has no wallet (pure SaaS agent use case), passkeys/WebAuthn can sign the delegation instead. How does this interact with on-chain capabilities? Can a single ACT mix WebAuthn and wallet signatures?
10. **Capability registry**: Should there be a canonical registry of well-known capability URIs (like IANA media types) or should it be freeform? A registry helps interoperability. Freeform helps adoption speed.

---

## Key References

### Protocol foundations
- [UCAN Specification v1.0](https://ucan.xyz/specification/)
- [ERC-7710 (Smart Contract Delegation)](https://eips.ethereum.org/EIPS/eip-7710)
- [ERC-7715 (Grant Permissions from Wallets)](https://eips.ethereum.org/EIPS/eip-7715)
- [OAuth 2.0 (RFC 6749)](https://datatracker.ietf.org/doc/html/rfc6749)
- [OAuth Device Authorization Grant (RFC 8628)](https://datatracker.ietf.org/doc/html/rfc8628)
- [x402 Specification v2](https://github.com/coinbase/x402)

### Agent authorization proposals
- [AAuth IETF Draft](https://datatracker.ietf.org/doc/html/draft-rosenberg-oauth-aauth-01)
- [OAuth On-Behalf-Of for AI Agents](https://datatracker.ietf.org/doc/html/draft-oauth-ai-agents-on-behalf-of-user-01)
- [AAP (Agent Authorization Profile)](https://www.aap-protocol.org/)
- [ERC-8004 (Trustless Agents)](https://eips.ethereum.org/EIPS/eip-8004)
- [ERC-5573 (SIWE ReCap)](https://eips.ethereum.org/EIPS/eip-5573)

### Identity standards
- [did:key Specification](https://w3c-ccg.github.io/did-key-spec/)
- [W3C Verifiable Credentials 2.0](https://www.w3.org/press-releases/2025/verifiable-credentials-2-0/)
- [EIP-712 (Typed Data Signing)](https://eips.ethereum.org/EIPS/eip-712)
- [CAIP-2 (Chain Agnostic Namespace)](https://github.com/ChainAgnostic/CAIPs/blob/main/CAIPs/caip-2.md)

### Incumbent products
- [Auth0 for AI Agents](https://auth0.com/ai) — GA Oct 2025. Token Vault + CIBA async auth + FGA for RAG. OAuth-based, centralized.
- [Auth0 Token Vault docs](https://auth0.com/ai/docs/intro/token-vault) — RFC 8693 token exchange, stores per-service OAuth tokens.
- [Auth0 Async Authorization (CIBA)](https://auth0.com/ai/docs/get-started/asynchronous-authorization) — Push notification approval via Guardian app.

### Implementation references
- [MetaMask Delegation Toolkit](https://docs.metamask.io/smart-accounts-kit/concepts/delegation/)
- [Lit Protocol Vincent](https://github.com/LIT-Protocol/Vincent)
- [Storacha/ucanto](https://github.com/storacha/ucanto)
- [Anchor Framework (Solana)](https://www.anchor-lang.com/)
