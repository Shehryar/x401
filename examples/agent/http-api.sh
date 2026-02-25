#!/bin/bash
# x401 Agent Integration — HTTP API (Zero Dependencies)
#
# Any agent can request authorization, collect human consent, and
# present ACTs using plain HTTP calls. No SDK required.

# ── Step 1: Request authorization ──
# The agent tells the authorization server what capabilities it needs.

curl -X POST https://api.x401.dev/authorize \
  -H "Content-Type: application/json" \
  -d '{
    "agent_did": "did:key:z6MkAgent...",
    "cap": [
      {
        "uri": "github:acme/backend/push:branch:staging",
        "lim": { "cnt": 20, "per": 86400 }
      },
      {
        "uri": "gmail:alice@example.com/send:domain:example.com",
        "lim": { "cnt": 50, "per": 86400 }
      }
    ],
    "reason": "Deploy hotfix and notify team",
    "exp": 86400
  }'

# Response:
# {
#   "request_id": "abc123",
#   "consent_url": "https://auth.x401.dev/consent/abc123",
#   "poll_endpoint": "https://api.x401.dev/poll/abc123"
# }


# ── Step 2: Show consent_url to the human ──
# Open in browser, render inline, display QR code — any method works.
# The human reviews the requested capabilities and signs with their wallet.


# ── Step 3: Poll until approved ──

curl https://api.x401.dev/poll/abc123
# → { "status": "pending" }
# → { "status": "authorized", "act": "eyJhbGciOiJFZERTQSIs..." }


# ── Step 4: Use the ACT ──
# Attach to any request via the Authorization header.

curl -X GET https://api.example.com/data \
  -H "Authorization: ACT eyJhbGciOiJFZERTQSIs..."


# ── With proof-of-possession ──
# For services that require proof, include the X-X401-Proof header.
# The proof is a short-lived JWT signed by the agent's private key,
# bound to the specific request (method, URL, body hash).

curl -X POST https://gateway.x401.dev/gmail/send \
  -H "Authorization: ACT eyJhbGciOiJFZERTQSIs..." \
  -H "X-X401-Proof: eyJ0eXAiOiJhY3QtcG9wK2p3dCIs..." \
  -H "Content-Type: application/json" \
  -d '{"to": "bob@company.com", "subject": "Hotfix deployed", "body": "..."}'
