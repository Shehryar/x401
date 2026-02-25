---
layout: doc
title: "x401: An Open Standard for Internet-Native Agent Authorization"
description: An HTTP-based protocol for AI agents, API access, and verifiable delegation
permalink: /whitepaper
---

# x401: An Open Standard for Internet-Native Agent Authorization

An HTTP-based protocol for AI agents, API access, and verifiable delegation

---

## Abstract

x401 is an open authorization standard that enables AI agents to carry verifiable, scoped proof of human authorization. By leveraging the HTTP 401 "Unauthorized" status code, x401 lets any service verify what an agent is allowed to do, who authorized it, and when that authorization expires. On-chain, smart contracts verify agent authorization natively in the VM with no external infrastructure. Off-chain, any API can verify an ACT with a single middleware line. No centralized token vault, no per-service API keys, no human in the loop per request.

x401 builds on the capability-based authorization model pioneered by UCAN, adapted for the specific needs of AI agents: quantitative limits as first-class primitives, dual-mode verification (off-chain JWT check and on-chain native signature verification), DPoP-style proof of possession for token binding, and composition with x402 for combined authorization and payment. With a few lines of middleware, developers can verify agent authorization for API access, on-chain transactions, email sending, code pushes, and any other agent action — making it the authorization layer for agent-first applications and autonomous commerce.

---

## 1. Motivation

The rapid growth of AI agents is reshaping how software interacts with the world. Agents book flights, send emails, push code, trade assets, and manage infrastructure. But one of the major roadblocks to fully autonomous operation is the lack of an authorization system that lets agents prove what they're allowed to do without human intervention.

Legacy authorization systems were designed for human interactions. OAuth requires a human to click "Allow" in a browser. API keys are static skeleton keys with no scoping, no delegation, no expiry. Token vaults like Auth0 store per-service credentials centrally. The IETF is working on OAuth agent extensions (AAuth, On-Behalf-Of) that add agent identity claims to existing token flows, but they extend the framework rather than address what the token should carry: capabilities, quantitative limits, delegation chains, cross-service scope.

These approaches create significant friction for AI-driven applications and autonomous agents. Agents need to operate autonomously across many services, for hours or days, with clear boundaries on what they can and can't do. They need to prove their authorization to services that have never seen them before. They should be able to delegate subsets of their permissions to other agents. None of this is possible with today's tools.

**Not your token, not your agent.** If an agent's proof of authorization lives in someone else's vault, the agent is only as autonomous as that vault lets it be. The same lesson crypto learned about self-custody applies to agent authorization.

x401 replaces fragmented per-service credentials with a single, self-contained, portable authorization token. The human defines the boundaries. The agent operates within them. Any service verifies independently.

---

### We need a new way to authorize agents on the internet...

*The old way of managing credentials was barely working for a human world, let alone an agentic future. x401 does in one token what existing systems can't do at all.*

**THE OLD WAY**

1. **Create API key per service** — Manual setup, different dashboard every time
2. **Learn each service's scoping syntax** — Stripe scopes, GitHub PAT permissions, AWS IAM policies
3. **Store credentials in a centralized vault** — Single point of failure, agent is locked out if vault goes down
4. **Agent fetches token per request** — Round-trip to vault every time, latency on every call
5. **Revoke per service when compromised** — Log into each dashboard individually, hope you remember them all

**WITH X401**

1. **Human signs one authorization with scoped capabilities** — One consent flow, all services covered
2. **Agent carries self-contained proof** — No vault, no round-trips, no dependencies
3. **Any service verifies locally** — Works on-chain and off-chain, no callbacks

---

## 2. Self-Contained Authorization: The Foundation of Autonomous Agents

### 2.1 Where Centralized Authorization Fails

Current agent authorization has a layering problem. OAuth JWTs verify locally via JWKS, but the tokens carry coarse per-service scopes with no quantitative limits, no delegation chains, and no cross-service portability. Auth0's JWTs also verify locally, but its Token Vault (where multi-service credential management lives) requires API calls to fetch each service's credentials. API keys require database lookups. None of these carry what an autonomous agent needs in the credential itself.

| Authorization Method | Verification | Scoping | Delegation | Revocation | On-chain |
|---|---|---|---|---|---|
| API Key | Database lookup | None | None | Per-service | No |
| Scoped API Key | Database lookup | Service-defined | None | Per-service | No |
| OAuth 2.0 | JWTs verify locally via JWKS | Coarse scopes (per-service) | None | Per-service | No |
| Auth0 for AI | JWTs verify locally; Token Vault fetches require API call | OAuth scopes | None | Per-service | No |
| **x401 (ACT)** | **Local JWT verify** | **Fine-grained + quantitative** | **Inline chains** | **One kill switch** | **Yes** |

### 2.2 Why Scoped API Keys Aren't Enough

Some services already offer scoped credentials. Stripe has restricted keys. GitHub has fine-grained personal access tokens. AWS has IAM policies. On the surface, this looks like it solves the authorization problem.

It doesn't. Every service invented its own scoping system with its own syntax, its own granularity, its own dashboard. The fundamental issue: the service defines the scope vocabulary, not the human. If Stripe doesn't offer a "max $100 per refund" scope, you can't express that constraint. If GitHub doesn't offer "staging branch only, max 20 pushes per day," you're out of luck.

This creates three problems for agents.

**No portable scope definitions.** An agent operating across 10 services needs 10 different credential types with 10 different scoping models. A developer building an agent has to learn Stripe's restricted key syntax, GitHub's PAT permissions, AWS IAM policy language, and whatever each new service invented. x401 uses one capability URI scheme across all services. `github:acme/backend/push:branch:staging` and `stripe:acme/refunds:create` follow the same grammar. Learn it once, use it everywhere.

**No composability across services.** A scoped GitHub PAT tells GitHub what the agent can do. A scoped Stripe key tells Stripe what the agent can do. But nothing connects them. There's no way to express "this agent can push to staging AND issue refunds up to $50 AND send emails to @company.com only" in a single credential. x401 bundles capabilities across any number of services into one token. One credential, one verification, one revocation.

**Quantitative limits are an afterthought.** Most API key scoping is boolean: can read or can't, can write or can't. Some services have rate limits, but those are enforced server-side and aren't part of the credential. x401 makes quantitative limits a first-class primitive in the token itself. Spending caps, count limits, rate limits, per-transaction maximums, time bounds. The human defines the budget. Every service enforces the same limits the same way.

| Capability | Scoped API Keys | x401 ACT |
|---|---|---|
| Scope vocabulary | Defined by each service | Defined by the human, universal grammar |
| Cross-service | Separate key per service | One token, many services |
| Quantitative limits | If the service implemented them | First-class, in every token |
| Delegation | Not possible | Inline chains with attenuation |
| Revocation | Per-service dashboard | One call, cascading |
| Audit trail | Per-service logs, unlinked | Unified across all services |

### 2.3 Self-Verifying Credentials Change Everything

A self-contained Agent Capability Token (ACT) carries everything a verifier needs: who authorized the agent, what it can do, quantitative limits, expiry, and the full delegation chain. Verification is a local cryptographic operation. No round-trip to any server.

This is also the only architecture that works on-chain. A smart contract can't call Auth0's API. It can't look up a Stripe restricted key. It needs the proof in the transaction itself. x401 tokens verify natively on Solana (~5,000-6,000 compute units for a 2-signature delegation chain, using the native Ed25519 program at ~2,280 CU per signature) and EVM (~50-80K gas via `ecrecover`).

---

## 3. How x401 Works

### 3.1 Example Integration

With a few lines of code, any service can verify agent authorization:

```bash
npm install @x401/verify
```

```typescript
import { verifyACT } from '@x401/verify';

app.get('/api/data', verifyACT({ require: 'https://api.example.com/data:read' }), handler);
```

That's it. The middleware decodes the ACT from the `Authorization` header, verifies the signature chain, checks capabilities and limits, and either passes the request through or returns HTTP 401.

### 3.2 Core Authorization Flow

The x401 protocol follows a simple four-step flow:

```
  ┌──────────┐                                        ┌──────────────┐
  │  Agent   │         1. Request access               │   Service    │
  │          │ ──────────────────────────────────────▶ │              │
  │          │                                        │              │
  │          │         2. HTTP 401 + required caps     │  "you need   │
  │          │ ◀────────────────────────────────────── │   ACT with   │
  │          │            { required: "...data:read" } │   data:read" │
  │          │                                        │              │
  │          │         3. Authorization: ACT eyJ...    │              │
  │          │ ──────────────────────────────────────▶ │  verify      │
  │          │                                        │  locally ✓   │
  │          │         4. Response                     │              │
  │          │ ◀────────────────────────────────────── │  execute ✓   │
  └──────────┘                                        └──────────────┘
```

**1. Agent Request.** An AI agent requests access to an API, on-chain resource, or any service endpoint.

**2. Authorization Required (401).** If no valid ACT is attached, the server responds with HTTP 401 Unauthorized, specifying the required capabilities:

```json
{
  "required": "https://api.example.com/data:read",
  "consent_uri": "https://auth.x401.dev/authorize?cap=...",
  "description": "Agent authorization required to access market data.",
  "accepts": "ACT"
}
```

**3. Agent Attaches ACT.** The agent includes its Agent Capability Token in the Authorization header:

```
GET /api/data HTTP/1.1
Authorization: ACT eyJhbGciOiJFZERTQSIsInR5cCI6ImFjdCtqd3QiLC...
```

**4. Service Verifies and Executes.** The service verifies the ACT locally (JWT signature check, delegation chain validation, capability match, limit check) and serves the request. No round-trip to any external service.

### 3.3 How Agents Get Authorized

Before an agent can present an ACT, a human must authorize it. x401 supports four consent modes:

**Interactive.** The human reviews requested capabilities in a browser and signs with their wallet (Phantom, MetaMask) or passkey. Best for first-time authorization of a new agent.

**Device grant.** A headless agent displays a short code. The human approves on their phone or laptop by entering the code, reviewing capabilities, and signing. Best for CLI tools, background services, and MCP servers.

**Agent-tool-native.** The agent's runtime (Claude Code, Cursor, OpenClaw, CrewAI, etc.) surfaces the consent prompt directly in its own UI. The human reviews and signs without leaving the tool. This is where most issuance happens in practice — the authorization moment occurs when the agent needs to do something, and the tool the human is already using surfaces the consent flow inline.

**Pre-signed (CLI).** The human signs a delegation offline using the `x401 grant` command. Best for CI/CD pipelines, scripts, and programmatic workflows where the capabilities are known in advance.

The protocol defines a delegation message format — any app that can present that message to a human and collect a wallet signature is a valid issuer. There is no privileged issuer, no certificate authority, no registration step. All four modes produce the same output: a signed ACT that the agent carries and presents to services.

### 3.4 Token Binding (Proof of Possession)

ACTs are bearer tokens. The agent signs the JWT, proving it created the token. But once the signed JWT is on the wire, anyone who intercepts it could present it from a different machine.

On-chain, this is already solved. The transaction itself is signed by the agent's wallet key. The chain verifies the signature matches the agent's address.

Off-chain, x401 uses DPoP-style proof of possession (inspired by RFC 9449). Alongside the ACT, the agent sends a fresh proof JWT signed by its private key, bound to the specific request:

```
POST /gmail/send HTTP/1.1
Host: gateway.x401.dev
Authorization: ACT eyJhbGciOiJFZERTQSIs...
X-X401-Proof: eyJ0eXAiOiJhY3QtcG9wK2p3dCIs...
```

The proof JWT (type `act-pop+jwt`) contains:

| Field | Description |
|---|---|
| `ath` | SHA-256 hash of the ACT. Binds this proof to a specific token. |
| `htm` | HTTP method of the request. |
| `htu` | Target URL. Prevents proof reuse against different endpoints. |
| `htb` | SHA-256 hash of the request body. Required for POST/PUT/PATCH. Prevents body swapping by a MITM. |
| `iat` | When the proof was created. Verifier rejects if older than 60 seconds. |
| `jti` | Unique nonce. Verifier maintains a short-lived replay cache to reject duplicates. |

Stealing the ACT is useless without the agent's private key to generate valid proofs. Each proof is short-lived, non-replayable, and bound to the specific request. Agent A can't hand its ACT to Agent B for use — Agent B can't generate proofs because it doesn't have Agent A's private key. Sub-delegation via the `dlg` chain is the correct way to share capabilities.

---

### HTTP-native. Authorization is built into the request.

```
  [Agent]  · · · · · · · · ·  [HTTP 401 / ACT]  · · · · · · · · ·  [Service]
```

x401 uses HTTP 401, the internet's standard "unauthorized" response. No additional infrastructure required. The agent sends a request, the service responds with what authorization is needed, and the agent attaches its proof. It works with any HTTP client, any HTTP server, any programming language. The protocol is the internet itself.

---

## 4. x401 Enables Verifiable Agent Autonomy

The difference between current agent authorization and x401 is best understood through concrete scenarios.

| Scenario | Traditional Process | With x401 |
|---|---|---|
| Coding agent that can merge to staging but not main | Share full GitHub token. Agent has access to every repo and branch. Hope it doesn't push to production. | ACT scoped to `github:acme/backend/push:branch:staging`. Agent literally cannot merge to main. The constraint is cryptographic, not a policy document. |
| Medical agent reading lab results from an EHR | Per-provider API key with broad patient access. No record of which human authorized which agent to see what. | ACT scoped to `fhir:provider/Patient/123/DiagnosticReport:read`. Can read labs, can't touch psychiatric notes. Hospital verifies the token locally without calling the patient's auth provider. |
| Travel agent booking flights | Agent has full access to corporate travel account. $5,000 first-class international booking? Nothing stops it. | ACT with `booking:flights/purchase` capped at $500 domestic. Airline verifies at checkout. Agent finds a $501 fare, it simply can't purchase it. |
| Revoking a compromised agent | Log into GitHub, Gmail, Stripe, Slack, each cloud provider individually. Some don't support programmatic revocation. | One revocation call. All services reject the agent. Sub-delegations cascade. |

x401 composes with x402 for combined authorization and payment. A single HTTP roundtrip can prove "this agent is authorized by Alice AND Alice's wallet is paying." Authorization and payment become one operation, not two separate systems.

---

## 5. x401 in Practice

The preceding sections describe what x401 enables in the abstract. This section walks through what it actually feels like to use, day to day.

### 5.1 First Authorization

You have a wallet — Phantom, MetaMask, a passkey. That's your identity. You also have an agent: Claude Code in your terminal, a portfolio manager bot, a customer support agent.

The first time the agent needs to do something real — push code, send an email, execute a swap — it hits a service that returns HTTP 401. The agent doesn't have an ACT yet. It surfaces a consent prompt inline, in whatever tool you're already using:

```
Agent requests authorization:
  github:acme/backend/push:branch:staging  (20/day, 24h)

Reason: "Deploy hotfix for checkout crash"

Sign with wallet to approve.
```

You review the capabilities, the limits, the expiry. You sign with your wallet. The agent now holds an ACT that's good for 24 hours. No account creation, no dashboard, no OAuth dance across multiple browser tabs. You signed a message with your key. The protocol handled the rest.

### 5.2 Normal Operation

The agent has an active ACT. You tell it "push the fix to staging." Behind the scenes:

```
  Agent                      Gateway                       GitHub
    │                           │                             │
    │  ACT + Proof-of-Possession│                             │
    │──────────────────────────▶│                             │
    │                           │                             │
    │                 ┌─────────┴─────────┐                   │
    │                 │ 1. verify ACT   ✓ │                   │
    │                 │ 2. verify proof ✓ │                   │
    │                 │ 3. read on-chain  │                   │
    │                 │    counter: 7/20 ✓│                   │
    │                 └─────────┬─────────┘                   │
    │                           │                             │
    │                           │  push via OAuth token       │
    │                           │────────────────────────────▶│
    │                           │                             │
    │                           │  success                    │
    │                           │◀────────────────────────────│
    │                           │                             │
    │  "pushed to staging"      │                             │
    │◀──────────────────────────│                             │
```

1. The agent generates a proof-of-possession JWT — signed with its private key, bound to this specific request, this URL, this body, expires in 60 seconds.
2. It sends the request with the ACT in the `Authorization` header and the proof in `X-X401-Proof`.
3. The gateway verifies both locally in milliseconds.
4. It checks the on-chain counter on Base (free RPC read) to confirm the agent has pushes remaining.
5. It pushes via GitHub's API using the OAuth token the gateway stores.

The agent never sees the GitHub token. You never see any of this. You said "push the fix" and it happened.

Later you say "send the deployment email to the team." Same flow — the ACT already covers `gmail:me/send:to:*@company.com` with a 50/day limit. Proof generated, gateway verified, email sent. Counter incremented.

### 5.3 Limits in Action

The agent tries push #21. The on-chain counter reads 20/20. The gateway returns:

```json
{
  "error": "limit_exceeded",
  "capability": "github:acme/backend/push:branch:staging",
  "limit": { "cnt": 20, "per": 86400 },
  "used": 20,
  "resets_at": "2026-02-25T00:00:00Z"
}
```

The agent surfaces this: "I've hit my 20-push limit for today. Resets at midnight. Want me to request a higher limit?" If yes, you sign a new delegation with `cnt: 50`. If no, you wait. The guardrail worked without any infrastructure you had to build.

### 5.4 Multi-Agent Workflows

A portfolio manager agent manages several worker bots. You authorized the manager for 500 USDC/day in swaps.

The manager delegates to a DCA bot: 100 USDC/day, SOL-USDC only. The manager signs this delegation with its own key. The DCA bot now holds an ACT with a two-link chain: human (500) → manager (100). The DCA bot delegates to a swap executor: 10 USDC per swap. Three-link chain.

The executor submits a swap to Jupiter on Solana. The smart contract walks the entire chain in one transaction — verifies every signature, checks every limit, confirms the URI matches. The swap executes. From your perspective: you authorized one thing ("500/day in swaps"), and a fleet of agents operated within that budget with cryptographic enforcement at every level.

### 5.5 Emergency Revocation

The manager agent is behaving unexpectedly. One call:

```bash
x401 revoke --jti <root-act-id>
```

Every sub-delegation dies. The DCA bot, the swap executor, everything downstream. On-chain, revocation is immediate — same block. Off-chain services see it within seconds via the revocation feed, or at worst when the ACT expires.

### 5.6 Steady State

For daily workflows with predictable needs, standing grants eliminate repeated consent:

```bash
x401 grant \
  --cap "github:acme/backend/push:branch:staging" \
  --lim "cnt:20,per:86400" \
  --exp 30d \
  --to did:key:z6MkClaudeCode...
```

The agent has a 30-day ACT. Limits reset daily on-chain. Every morning the agent just works. You don't interact with x401 again unless you want to change the boundaries.

The core pattern: you interact with x401 at authorization boundaries, not during normal operation. Sign when you set up or adjust permissions. The rest of the time the agent is invisible. The limits are live, the proofs are automatic, the revocation is instant. The protocol stays out of the way until you need it not to.

---

## 6. What x401 Enables

### 6.1 Trustless On-Chain Agent Execution

This is where the protocol is purest. A DeFi protocol's smart contract verifies, on-chain, that a transaction was authorized by a specific human with specific limits. Not "trust the wallet provider." Actual cryptographic verification at the point of execution. No oracles, no gateways, no external services. The chain IS the verifier.

```
  ┌──────────┐        ┌──────────┐        ┌─────────────────────────────┐
  │  Human   │        │  Agent   │        │  Smart Contract (On-Chain)  │
  └────┬─────┘        └────┬─────┘        └──────────────┬──────────────┘
       │                   │                             │
       │  sign delegation  │                             │
       │  (Phantom / MM)   │                             │
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

          ~5,000 CU on Solana  /  ~50K gas on EVM
          No oracles. No gateways. The chain IS the verifier.
```

Combined with x402, an agent can prove authorization AND pay in a single HTTP roundtrip. The ACT and x402 payment are cryptographically linked via the same wallet:

```
GET /api/premium-data HTTP/1.1
Authorization: ACT eyJhbGciOiJFZERTQSIsInR5cCI6...
PAYMENT-SIGNATURE: <base64 PaymentPayload>
```

This is uniquely possible because both protocols share the same wallet-native, HTTP-native design. Authorization and payment become one operation, not two separate systems. This enables agent-to-agent commerce, paid API access, and micropayments without any human in the loop per transaction.

### 6.2 One Credential, Any Domain

x401 is not limited to financial transactions. The same token format expresses authorization for any domain:

- `solana:mainnet/spl:EPjFW.../transfer` — transfer up to 100 USDC per day
- `gmail:alice@company.com/send:domain:company.com` — send max 50 emails per day to @company.com only
- `github:acme/backend/push:branch:staging` — push to staging, max 20 pushes per day
- `fhir:hospital/Patient/123/DiagnosticReport:read` — read lab results, not psychiatric notes
- `booking:flights/purchase` — book domestic flights under $500

All of these follow the same URI grammar, defined by a formal ABNF specification: `{service}:{scope}/{resource}/{action}`. An agent carries one ACT that works across on-chain transactions, APIs, email, code repos, and enterprise systems. For new services with x401 middleware, this works natively. For existing services (Gmail, GitHub, Slack), capability gateways enforce these constraints at the translation layer.

### 6.3 Quantitative Limits as First-Class Primitives

x401 goes beyond boolean "can read" or "can write" permissions. Every limit type is a first-class primitive in the token:

| Limit | Field | Example |
|---|---|---|
| Spending | `amt` | Max 100 USDC per day, max 10 USDC per transaction |
| Count | `cnt` | Max 50 emails per day, max 20 code pushes per day |
| Rate | `rate` | Max 1,000 API requests per hour |
| Monetary | `cost`, `cur` | Max $500 per flight booking, $2,000 per month |
| Per-transaction | `tx` | Max 10 USDC per swap |
| Gas/compute | `gas`, `cu` | Max 5M gas per EVM transaction, max 1M CU on Solana |
| Time window | `per` | Period length in seconds for rolling limits |

All limit fields follow the same attenuation rule in delegation chains: children can only decrease, never increase. If a parent sets a limit field and the child omits it, the parent's value carries forward. A sub-agent can never have more headroom than its parent.

A customer support agent can issue refunds up to $50 and access order history, but can't view payment methods. If a customer asks for a $200 refund, the agent has to escalate. It's not a policy choice. It's a cryptographic constraint.

### 6.4 The Infrastructure Spectrum

Not all domains have the same infrastructure requirements. This matters for how the protocol works in practice.

| Domain | Infrastructure needed |
|---|---|
| **On-chain (Solana, Base, EVM)** | **None.** The chain IS the verifier. Smart contracts verify ACTs natively. No gateway, no consent server, no middleman. This is where x401 is purest. |
| **New APIs / MCP servers** | **One middleware line.** Service owner adds `verifyACT()`. Self-verifying JWT, no callbacks, no external dependency. |
| **Existing off-chain services (Gmail, GitHub, Slack)** | **Gateway required.** These services don't speak x401 and won't anytime soon. A capability gateway verifies ACTs on the agent-facing side and calls native APIs on the service side. Pragmatic, not pure. |

```
          x401 Works at Every Adoption Level

  ───────────────────────────────────────────────────────────────────

  ON-CHAIN        Agent ──── ACT ────▶ Smart Contract     Zero adoption
                                       verifies natively   needed. The chain
                                       in VM               IS the verifier.

  ───────────────────────────────────────────────────────────────────

  GATEWAY         Agent ──── ACT ────▶ Gateway ──────────▶ Gmail
                                       verifies ACT,       GitHub
                                       bridges to          Slack
                                       native API          (no changes)

  ───────────────────────────────────────────────────────────────────

  NATIVE          Agent ──── ACT ────▶ New API Service     One line of
                                       verifyACT()         middleware.
                                       middleware          Full protocol.

  ───────────────────────────────────────────────────────────────────
```

For crypto and on-chain use cases, x401 is genuinely infrastructure-free. The protocol's purest expression is on-chain: human signs a delegation, agent carries it, smart contract verifies it, done. No servers, no accounts, no intermediaries.

For off-chain legacy services, the capability gateway is a pragmatic bridge. The agent presents its ACT. The gateway verifies it locally, enforces x401 constraints (domain restrictions, count limits, spending caps), and calls the native API with stored OAuth credentials. The service has no idea x401 exists.

```
  ┌──────────┐        ┌─────────────────────────┐        ┌───────────────┐
  │  Agent   │        │   Capability Gateway     │        │   Existing    │
  │          │        │                         │        │   Service     │
  │ carries  │        │  • Verify ACT (local)   │        │               │
  │ ACT      │        │  • Enforce x401 limits  │        │  Gmail        │
  └────┬─────┘        └────────────┬────────────┘        └───────┬───────┘
       │                           │                             │
       │  Authorization: ACT eyJ.. │                             │
       │──────────────────────────▶│                             │
       │                           │                             │
       │                 ┌─────────┴─────────┐                   │
       │                 │ verify ACT       ✓│                   │
       │                 │ check limits     ✓│                   │
       │                 │ domain: @co.com? ✓│                   │
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

This works today, it's better than the alternatives (pre-authorized limits instead of per-action approval), and it creates demand for native adoption. As agent traffic grows, services have incentive to accept ACTs directly and skip the middleman.

### 6.5 Progressive Authorization

Agents don't always know upfront what they'll need. A coding agent might discover mid-task that it needs to push to main, not just staging. A research agent might hit a premium API it wasn't pre-authorized for. x401 handles this natively.

When an agent encounters a service that requires a capability it doesn't have, the service responds with HTTP 401 and the required capability URI. The agent sends a **permission request** to the human, specifying what it needs and why:

```json
{
  "type": "permission_request",
  "requested_cap": [
    { "uri": "github:acme/frontend/push:branch:main", "lim": { "cnt": 5, "per": 86400 } }
  ],
  "reason": "Staging tests passed for hotfix #427. Need to push to main.",
  "trigger": "401 from github:acme/frontend/push:branch:main"
}
```

The request reaches the human through whatever channel is available. For crypto-native users, the agent sends a message to the human's wallet — Phantom or MetaMask surfaces it as a signing request. For off-chain use cases, the consent server delivers a push notification, and the human reviews and signs on their phone. The result is the same: the human signs a new ACT granting the additional capability, and the agent continues.

This is fundamentally different from Auth0's CIBA flow, which requires per-action approval ("can I push this commit?"). x401 progressive authorization grants a scoped capability with limits ("you can push to main, up to 5 times today"). The agent gets autonomy within the new boundary, not one-shot permission.

For predictable workflows, humans can set standing grants: "If this agent ever needs calendar read access, auto-approve with these limits." The consent server auto-issues ACTs when the pattern matches, without prompting the human. Dangerous capabilities like `*/delete:*` or `*/transfer` always require explicit approval.

When a sub-agent in a delegation chain needs a new capability, the request escalates up the chain. The sub-agent asks its parent. If the parent has the authority, it sub-delegates. If not, the parent escalates to its parent, eventually reaching the human. New authorization flows back down with attenuation at each hop.

---

## 7. Agent Governance

### 7.1 Delegation Chains with Attenuation

A human authorizes an orchestrator agent. The orchestrator delegates narrower permissions to worker agents. Each hop in the chain can only narrow capabilities, never escalate. Any verifier can walk the full chain back to the human.

A portfolio manager agent is authorized for 500 USDC per day in swaps. It delegates to a DCA bot capped at 100 USDC per day, SOL-USDC only. The DCA bot delegates to a swap executor with 10 USDC per trade maximum. The DEX smart contract verifies the full chain in one transaction.

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

Each link in the chain carries a cryptographic signature proving delegation and provable attenuation. Capabilities can only narrow. Limits can only decrease. Expiry can only shorten. A sub-agent can never grant itself more authority than its parent.

### 7.2 One Kill Switch

Revoking agent access today means visiting every service dashboard individually. x401 collapses this into one operation. One revocation call invalidates the agent across all services. Revoke the root delegation and all sub-delegations cascade.

On-chain revocation costs approximately 200 compute units on Solana (instant finality). Off-chain revocation propagates via webhook in seconds. For emergencies, nonce rotation invalidates all outstanding ACTs from a human across all agents.

### 7.3 Chain-Agnostic, Domain-Agnostic

The token format is universal. The signature algorithm follows the target chain: Ed25519 for Solana, secp256k1 for EVM. Off-chain verification supports both. A single ACT can contain capabilities across multiple chains and multiple off-chain services.

x401 is not a DeFi protocol. It is not an OAuth extension. It is a general-purpose authorization standard that happens to work natively on-chain, because self-verifying credentials are the only kind of credential a smart contract can check.

---

## 8. The x401 Specification

### 8.1 Middleware Configuration

Server-side verification requires one middleware call:

```typescript
verifyACT({
  require: 'https://api.example.com/data:read',
  audience: 'https://api.example.com',
  maxChainDepth: 3
})
```

| Parameter | Description |
|---|---|
| `require` | Capability URI the agent must possess |
| `audience` | Expected audience (optional, defaults to service URL) |
| `maxChainDepth` | Maximum delegation chain depth (optional, default 3) |
| `requireProof` | Require DPoP-style proof of possession via `X-X401-Proof` header (default: true) |

The middleware extracts the ACT from the `Authorization: ACT <token>` header, verifies the proof of possession from the `X-X401-Proof` header, runs the full verification algorithm, and either passes the request to the handler or returns HTTP 401.

### 8.2 Handling Requests Without Authorization

If a request is submitted without a valid ACT, the server responds with HTTP 401 Unauthorized. The response body provides structured feedback that agents can act on programmatically:

```json
{
  "required": "https://api.example.com/data:read",
  "consent_uri": "https://auth.x401.dev/authorize?cap=...",
  "description": "Agent authorization required to access market data.",
  "accepts": "ACT"
}
```

The `consent_uri` points the agent to a consent server where it can obtain authorization from its human. The `required` field tells the agent exactly which capability it needs. This mirrors the x402 pattern: a structured 4xx response that machines can resolve without human intervention.

---

## 9. Technical Specifications

### 9.1 Agent Capability Token Format

An ACT is a signed JWT with type `act+jwt`. The header specifies the signing algorithm and the agent's decentralized identifier:

```json
{
  "typ": "act+jwt",
  "alg": "EdDSA",
  "kid": "did:key:z6MkAgent..."
}
```

The payload carries the agent's identity, the human's identity, capabilities with limits, and the delegation proof:

| Field | Type | Required | Description |
|---|---|---|---|
| `iss` | DID string | Yes | Agent's identity (who is presenting this token) |
| `sub` | DID string | Yes | Human's identity (the authority source) |
| `aud` | string | Yes | Intended verifier (`"*"` for any, or specific service URL) |
| `exp` | unix timestamp | Yes | Expiry (recommended 1h default, 24h max) |
| `jti` | hex string | Yes | Unique token ID for revocation and replay prevention |
| `cap` | Capability[] | Yes | What this agent can do (must be subset of delegation) |
| `dlg` | Delegation | Yes | Cryptographic proof of human authorization |
| `rsn` | string | Recommended | Human-readable reason, echoed in consent UI |

### 9.2 Capability URI Scheme

Capabilities follow a universal URI grammar defined by a formal ABNF specification. On-chain actions use CAIP-2 chain identifiers. Off-chain actions use service-specific schemes. Key grammar rules: `chain-ns = ALPHA *(ALPHA / DIGIT)` (identifiers like `eip155`, `solana` start with a letter and may contain digits), the wildcard `*` matches exactly one path segment (no recursive/globstar matching), and prefix wildcards are not supported.

| Domain | URI Pattern | Example |
|---|---|---|
| Solana SPL transfer | `solana:{cluster}/spl:{mint}/transfer` | `solana:mainnet/spl:EPjFW.../transfer` |
| EVM ERC-20 transfer | `eip155:{chainId}/erc20:{addr}/transfer` | `eip155:8453/erc20:0x833.../transfer` |
| HTTPS API | `https://{host}/{path}:{action}` | `https://api.example.com/data:read` |
| Email | `gmail:{account}/{action}:{constraint}` | `gmail:alice@co.com/send:domain:co.com` |
| Code repository | `github:{owner}/{repo}/{action}:{constraint}` | `github:acme/backend/push:branch:staging` |
| Calendar | `gcal:{account}/{action}` | `gcal:alice@co.com/create` |
| Healthcare | `fhir:{provider}/{resource}/{action}` | `fhir:hospital/Patient/123/DiagnosticReport:read` |

Custom domains can define their own URI patterns following the same `{service}:{scope}/{resource}/{action}` structure. The protocol maintains a well-known capability catalog (similar to IANA media types) documenting common patterns for popular services, but it is informational, not normative.

During verification, the protocol checks that each child capability is a **subset** of its parent's. A child URI is a subset of a parent URI if: (1) schemes match, (2) each scope segment matches (parent `*` matches any child value), (3) actions match (parent `*` matches any child action), (4) child may add constraints but not remove parent constraints, and (5) child limits are ≤ parent limits.

### 9.3 Delegation Proof

The `dlg` field contains the cryptographic proof that a human authorized this agent. The delegation includes a `nonce` field (required) that enables verifiers to reconstruct the signed payload from the token alone and prevents delegation signature replay.

The human signs a structured payload covering all fields that affect authorization:

For EVM (EIP-712 typed data):
```
keccak256(abi.encode(
  "x401 Delegation",
  delegator_did,
  delegate_did,
  capabilities_hash,   // SHA-256 of JCS-canonicalized capabilities JSON
  reason_hash,         // SHA-256 of rsn string
  expiry,
  nonce
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

**Canonical serialization**: The capabilities array is serialized to JSON with keys sorted lexicographically (RFC 8785 — JSON Canonicalization Scheme) before hashing. This ensures two implementations produce the same hash for the same capabilities regardless of key ordering.

**Signed reason**: The `reason_hash` (SHA-256 of the `rsn` string) is included in the signed payload so the human-readable reason displayed in the consent UI cannot be manipulated after signing.

For off-chain-only use cases, passkeys and WebAuthn are supported as the signing mechanism.

**Attenuation rules** (enforced at verification):

1. Each link's capabilities MUST be a subset of its parent's capabilities (see URI subset matching)
2. All limit fields can only decrease or stay the same: `amt`, `cnt`, `rate`, `cost`, `tx`, `gas`, `cu`, `per`
3. If a parent sets a limit field and the child omits it, the parent's value carries forward (implicit inheritance)
4. A child may add limit fields the parent didn't set (adding limits narrows access)
5. Expiry can only be equal to or earlier than the parent's expiry
6. New capability URIs cannot be added, only narrowed or removed
7. Enforcement tier can only stay the same or escalate (`none` → `verifier` → `onchain`)

### 9.4 Verification Algorithm

Verification is a deterministic local operation:

```
  Incoming request
       │
       ▼
  ┌─────────────────┐
  │ 1. Decode JWT   │
  └────────┬────────┘
       │
       ▼
  ┌─────────────────┐     ┌─────────────────┐
  │ 2. Verify agent │     │ 3. Verify proof  │
  │    signature    │     │    of possession │
  └────────┬────────┘     └────────┬────────┘
       │                       │
       └───────────┬───────────┘
                   ▼
  ┌─────────────────────────┐
  │ 4. Check time bounds    │
  │    nbf <= now <= exp    │
  └────────────┬────────────┘
               ▼
  ┌─────────────────────────┐
  │ 5. Walk delegation chain│
  │    verify each sig,     │
  │    check attenuation    │
  └────────────┬────────────┘
               ▼
  ┌─────────────────────────┐
  │ 6. Verify root          │
  │    chain → human (sub)  │
  └────────────┬────────────┘
               ▼
  ┌─────────────────┐     ┌─────────────────┐
  │ 7. Capability   │     │ 8. Limit check  │
  │    match        │     │                 │
  └────────┬────────┘     └────────┬────────┘
       │                       │
       └───────────┬───────────┘
                   ▼
  ┌─────────────────────────┐
  │ 9. Revocation check     │
  └────────────┬────────────┘
               ▼
           ✓ PASS → execute request
```

1. **Decode JWT** — parse header, payload, signature
2. **Verify agent signature** — confirm the JWT was signed by the agent identified in `iss`
3. **Verify proof of possession** — check `X-X401-Proof` header: verify the proof JWT signature matches the ACT's `iss` key, confirm `ath` matches SHA-256 of the presented ACT, confirm `htm` and `htu` match the current HTTP request, for POST/PUT/PATCH confirm `htb` matches SHA-256 of the request body, reject if `iat` is older than 60 seconds, reject if `jti` has been seen before
4. **Check time bounds** — confirm `nbf <= now <= exp`
5. **Walk delegation chain** — starting from the agent's delegation, verify each signature, confirm `capabilities_hash` and `reason_hash` match the signed payload, and confirm each link's capabilities are a valid subset of its parent
6. **Verify root** — confirm the chain terminates at the human identified in `sub`
7. **Capability match** — confirm the requested capability is covered by the ACT's `cap` array
8. **Limit check** — confirm the request is within quantitative bounds
9. **Revocation check** (optional) — check `jti` against a revocation list

If any step fails, return HTTP 401. The entire verification is a local operation with no external dependencies.

---

## 10. Integration Examples

### 10.1 Server-Side Implementation

A complete Express.js server that verifies agent authorization:

```bash
npm install express @x401/verify
```

```typescript
import express from 'express';
import { verifyACT } from '@x401/verify';

const app = express();

// Public endpoint — no authorization needed
app.get('/api/status', (req, res) => {
  res.json({ status: 'ok' });
});

// Protected endpoint — requires ACT with proof of possession (default)
app.get('/api/data',
  verifyACT({ require: 'https://api.example.com/data:read' }),
  (req, res) => {
    // req.act contains the verified token
    // req.act.sub is the human who authorized the agent
    // req.act.iss is the agent's identity
    res.json({ data: getMarketData(), authorized_by: req.act.sub });
  }
);

// Protected endpoint — proof verifies body hash for POST
app.post('/api/data',
  verifyACT({ require: 'https://api.example.com/data:write' }),
  (req, res) => {
    updateData(req.body);
    res.json({ success: true });
  }
);

// Internal endpoint — opt out of proof for trusted networks
app.get('/internal/status',
  verifyACT({ require: 'internal:status', requireProof: false }),
  (req, res) => res.json({ status: 'ok' })
);

app.listen(3000);
```

### 10.2 Agent-Side: Three Integration Paths

Agent tools don't need an SDK to integrate. x401 provides three paths at increasing depth. The HTTP API and CLI are first-class, not afterthoughts.

**Path 1: HTTP API (zero dependencies).** Pure REST. Three HTTP calls, no imports. Works from any language, any framework.

```bash
# 1. Request authorization
curl -X POST https://api.x401.dev/authorize \
  -H "Content-Type: application/json" \
  -d '{
    "agent_did": "did:key:z6MkAgent...",
    "cap": [
      { "uri": "github:acme/backend/push:branch:staging", "lim": { "cnt": 20, "per": 86400 } }
    ],
    "reason": "Deploy hotfix for checkout crash",
    "exp": 86400
  }'
# → {"request_id":"abc123","consent_url":"https://auth.x401.dev/consent/abc123","poll_endpoint":"..."}

# 2. Show consent_url to the human (open in browser, render inline, display QR code)

# 3. Poll until approved
curl https://api.x401.dev/poll/abc123
# → {"status":"authorized","act":"eyJhbGciOiJFZERTQSIs..."}
```

**Path 2: CLI binary (shell out).** The `x401` CLI wraps the API. The agent tool shells out and captures the ACT from stdout. Same pattern as `gh auth login`.

```bash
# Interactive: opens browser, polls, prints ACT to stdout
x401 authorize \
  --cap "github:acme/backend/push:branch:staging" \
  --lim "cnt:20,per:86400" \
  --exp 24h \
  --reason "Deploy hotfix"

# Generate proof of possession for a request
x401 proof --act ./my-act.jwt --method POST --url "https://gateway.x401.dev/gmail/send"
```

**Path 3: SDK (deep integration).** For tools that want auto-proof generation, ACT caching, and token refresh. Optional and additive.

```bash
npm install @x401/sdk
```

```typescript
import { X401Client } from '@x401/sdk';

const client = new X401Client({ act: myACT, privateKey: agentKey });

// Proof generated and attached automatically on every request
const response = await client.fetch('https://gateway.x401.dev/gmail/send', {
  method: 'POST',
  body: JSON.stringify({ to: 'bob@co.com', subject: 'Update', body: '...' })
});
```

| Path | Dependency | Effort | Best for |
|---|---|---|---|
| **HTTP API** | None | 3 API calls | Any language, any framework, maximum flexibility |
| **CLI binary** | `x401` on PATH | Install binary, exec process | Agent tools that already shell out to CLIs |
| **SDK** | `@x401/sdk` package | Add dependency, use client API | Deep integration with auto-proofs and caching |

### 10.3 On-Chain Verification (Solana)

A Solana program verifies an ACT before executing a transaction:

```rust
use anchor_lang::prelude::*;

#[program]
pub mod x401_verifier {
    use super::*;

    pub fn verify_and_execute(
        ctx: Context<VerifyAndExecute>,
        act_data: ACTData,
        human_sig: [u8; 64],
        agent_sig: [u8; 64],
    ) -> Result<()> {
        let clock = Clock::get()?;

        // 1. Check not revoked
        require!(!ctx.accounts.act_state.revoked, X401Error::Revoked);

        // 2. Check expiry
        require!(clock.unix_timestamp <= act_data.exp, X401Error::Expired);

        // 3. Verify human's Ed25519 delegation signature (~2,280 CU)
        let delegation_msg = build_delegation_message(&act_data);
        verify_ed25519(&ctx.accounts.human.key(), &delegation_msg, &human_sig)?;

        // 4. Verify agent's Ed25519 signature (~2,280 CU)
        let payload_msg = build_payload_message(&act_data);
        verify_ed25519(&ctx.accounts.agent.key(), &payload_msg, &agent_sig)?;

        // 5. Check and update spending limits (per-capability counter)
        let state = &mut ctx.accounts.act_state;
        if state.period > 0 && clock.unix_timestamp >= state.period_start + state.period {
            state.spent = 0;
            state.period_start = clock.unix_timestamp;
        }
        state.spent = state.spent.checked_add(act_data.amount)
            .ok_or(X401Error::Overflow)?;
        require!(state.spent <= state.max_amount, X401Error::ExceedsLimit);

        // Execute the authorized action
        transfer_spl_tokens(ctx, act_data.amount)?;

        Ok(())
    }
}
```

Total verification cost on Solana: approximately 5,000-6,000 compute units for a 2-signature delegation chain (two Ed25519 signature verifications at ~2,280 CU each via the native Ed25519 program, plus account reads and spending limit updates). Solana's per-transaction limit is 1.4 million compute units — verification uses less than 0.5% of the budget.

The on-chain limit enforcer uses per-capability counters keyed by `keccak256(jti, capHash)`, not a single counter per ACT. This means an ACT with multiple capabilities tracks each one independently. Only the authorized agent address can increment counters (`msg.sender == agent`), preventing third parties from burning someone else's quota.

### 10.4 Sub-Delegation

An orchestrator agent delegates narrower permissions to a worker:

```typescript
import { Agent } from '@x401/sdk';

const orchestrator = new Agent({ keyfile: './orchestrator-key.json' });

// Orchestrator has a broad ACT from the human (500 USDC/day, any Jupiter pair)
const orchestratorACT = await orchestrator.loadACT('./act.jwt');

// Delegate narrower permissions to a worker agent
const workerACT = orchestrator.delegate(orchestratorACT, {
  to: 'did:key:z6MkWorker...',
  capabilities: [
    {
      uri: 'solana:mainnet/program:JUP6Lk.../call:route',
      lim: { amt: '100000000', per: 86400, tx: '50000000' }  // 100 USDC/day, 50 max per swap
    }
  ],
  reason: 'DCA execution — SOL-USDC only'
});

// Worker carries this ACT and any service can verify the full chain:
// Human (500 USDC/day) → Orchestrator (500 USDC/day) → Worker (100 USDC/day, 50/swap)
```

x402 composition and local development tooling (mock consent server, test ACTs, delegation chain builder) are documented in the reference implementation.

### 10.5 End-to-End Scenarios

Three walkthroughs showing x401 in real workflows:

**DeFi agent (on-chain, zero infrastructure).** A human opens Phantom and reviews the capabilities the agent is requesting: "Jupiter swaps, 100 USDC/day, max 10 per swap." The human signs the delegation. The agent carries the ACT and submits a swap to Jupiter's program on Solana. The smart contract verifies the delegation chain and spending limits on-chain in one transaction (~5,000-6,000 CU). The agent hits its daily limit? The next transaction reverts. The human wants to stop everything? One on-chain revocation call, instant.

**Coding agent (off-chain, gateway-mediated).** Claude Code detects it needs `github:acme/backend/push:branch:staging`. It surfaces the consent prompt inline: "Agent requests: push to acme/backend (staging branch only), 20/day, 24h." The human approves. Claude Code collects the wallet signature, assembles the ACT, and hands it to the agent. The agent generates a proof-of-possession, calls the GitHub capability gateway. The gateway verifies the ACT and proof locally (JWT check), checks the on-chain limit counter on Base (free RPC read), pushes via the GitHub API using stored OAuth tokens. The agent never touches the OAuth token directly.

**Multi-agent delegation chain.** A human authorizes a portfolio manager agent for 500 USDC/day in swaps. The manager delegates to a DCA bot: 100 USDC/day, SOL-USDC only. The DCA bot delegates to a swap executor: 10 USDC per swap. Each delegation is signed and attenuated. The DEX smart contract receives a request from the swap executor and verifies the entire chain in one transaction: human signed 500 → manager signed 100 → bot signed 10. Each hop narrowed the capabilities. The executor tries 15 USDC? Transaction reverts. The bot tries to trade SOL-ETH? Not in its capability URI. The human revokes the root? Every sub-delegation dies.

---

## 11. Use Cases

### DeFi and On-Chain Agent Operations

A trading agent proves authorization for Jupiter swaps (100 USDC per day, max 10 per swap). The DEX smart contract verifies the full delegation chain on-chain in one transaction (~5,000-6,000 CU on Solana). Combined with x402, an agent proves authorization and pays in a single request.

A DCA bot is sub-delegated from a portfolio manager agent with attenuated limits. The swap executor can't exceed 10 USDC per trade, even if the parent agent has a 500 USDC/day budget. On-chain math enforces this — no policy server, no trust assumption, no external dependency.

### Healthcare: Scoped Access to Patient Data

A triage agent reads lab results and vitals from an EHR but cannot access psychiatric notes or billing records. The capability URI scopes it to specific FHIR resource types. The hospital verifies the token locally without calling the patient's auth provider.

A pharmacy agent checks medication interactions, scoped to read-only on the formulary. No access to patient identity. The agent's ACT traces back to the prescribing physician who authorized the query.

### Software Development: Agents with Repository Boundaries

A coding agent can merge PRs to staging but not main, scoped to specific repos. It delegates read-only access to a review agent. The review agent literally cannot push, even if compromised.

A CI agent is authorized to deploy to staging environments only. Production deploys require a separate ACT signed by a human with elevated permissions. The deployment platform verifies the ACT before executing any pipeline.

### Autonomous Commerce: Authorization and Payment in One Request

A procurement agent books domestic flights under $500, with full audit trail back to the authorizing human. The airline verifies the ACT at checkout. Agent finds a $501 fare, it can't purchase it.

An agent paying for a premium API proves authorization (ACT) and submits payment (x402) in a single HTTP roundtrip. The service verifies both before serving the request. No separate auth flow, no separate payment flow.

### Multi-Agent Delegation Chains

A hiring manager agent delegates to a scheduling agent (calendar access only) and a sourcing agent (LinkedIn outreach, 20 messages per day). Neither can access compensation data in the HRIS. Each carries a verifiable chain back to the hiring manager's authorization.

An IoT fleet agent adjusts thermostats in Building A (68-74F range) and delegates to per-floor sub-agents that can only control their own floor. The building management system verifies each agent's scope independently.

### Enterprise Governance at Scale

A company authorizes 50 agent instances with hierarchical budgets. One revocation call shuts down any agent across all services instantly. Full audit trail from every action back to the authorizing human.

An agent carries one ACT that authorizes Solana transfers (100 USDC per day), Gmail sending (50 per day to @company.com), and GitHub pushes (staging only). One credential, three services, one kill switch.

---

## 12. Prior Art and Related Work

x401's delegation model is directly inspired by UCAN (User Controlled Authorization Networks), which pioneered capability-based authorization with inline delegation chains and self-verifying credentials. x401 diverges from UCAN in format (JWT vs DAG-CBOR, for adoption pragmatism), quantitative limits (first-class primitives vs extensible caveats), on-chain verification (native per chain vs expensive on EVM), and consent flows (defined protocol vs token format only). UCAN is the intellectual ancestor. The UCAN community's work on ucanto (Storacha's implementation) and the broader capability-based security literature (Mark Miller's object-capability model) inform the design.

The IETF is actively working on agent authorization within OAuth. AAuth extends OAuth 2.1 for scenarios where users interact via voice or SMS. The OAuth On-Behalf-Of draft adds `act.sub` claims identifying which agent is acting. These have a massive compatibility advantage — the OAuth ecosystem is enormous, and an extension that adds agent identity to existing JWTs is adoptable tomorrow.

Where OAuth extensions fall short is on the features that matter specifically for autonomous agents: quantitative limits in the token, multi-hop delegation chains, cross-service portable credentials, and on-chain verification. x401 and OAuth extensions are complementary. A world where OAuth handles simple agent identity ("this is Agent X acting on behalf of User Y") and x401 handles complex agent authorization ("Agent X can do these specific things with these limits, and here's the cryptographic delegation chain") is plausible.

---

## 13. Key Takeaways

**Self-contained, portable agent credentials.** No centralized vault, no per-service tokens, no round-trips to auth servers. Capabilities, limits, and delegation chains travel in the token itself.

**Not your token, not your agent.** Agents carry their own proof of authorization. Any service verifies independently. DPoP-style proof of possession prevents stolen token reuse.

**On-chain first.** Smart contracts verify ACTs natively — no oracles, no gateways. This is where the protocol is purest. Off-chain works via middleware (new services) or capability gateways (existing services).

**Agent-first, domain-agnostic, chain-agnostic.** One credential format for on-chain transactions, API calls, email, code, healthcare, IoT, and everything else agents do. Formal ABNF grammar for capability URIs. One model for limits.

**Composes with x402.** Authorization and payment in a single HTTP roundtrip. The same wallet proves who authorized the agent and who's paying.

---

## 14. Reference Implementation

The x401 protocol has a full reference implementation available as open source:

- **HTTP API** (`api.x401.dev`) — Zero-dependency integration: `/authorize`, `/poll`, `/revoke`, `/verify`, `/proof`
- **CLI** (`x401`) — Standalone binary: `authorize`, `grant`, `proof`, `verify`, `revoke`, `inspect`. Installable via `brew install x401`, `npm install -g @x401/cli`, or direct download.
- **@x401/verify** — Server-side middleware for Express, FastAPI, and Next.js with proof-of-possession checking
- **@x401/sdk** — Agent SDK with auto-proof generation, ACT caching, and token refresh
- **@x401/react** — Consent UI components for building authorization screens
- **@x401/anchor** — Solana Anchor verifier program with native Ed25519 verification and per-capability limit counters
- **@x401/contracts** — EVM Solidity verifier and limit enforcer with per-capability counters keyed by `keccak256(jti, capHash)`, agent-only increment, and Base paymaster support
- **@x401/adapters** — Service-specific capability translators (Gmail, GitHub, Slack, etc.) for gateway use
- **Consent server** — Hosted at auth.x401.dev or self-hostable

---

> For those building the next generation of AI-powered applications, x401 provides a foundation for verifiable, autonomous agent authorization.
>
> **Learn more at x401.dev**
