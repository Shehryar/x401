#!/bin/bash
# x401 Agent Integration — CLI (Shell Out)
#
# Any agent framework can shell out to the x401 CLI.
# Authorization flows and proof generation from the terminal.

# ── Interactive: opens browser, polls, prints ACT to stdout ──

x401 authorize \
  --cap "github:acme/backend/push:branch:staging" \
  --lim "cnt:20,per:86400" \
  --cap "gmail:alice@example.com/send:domain:example.com" \
  --lim "cnt:50,per:86400" \
  --exp 24h \
  --reason "Deploy hotfix and notify team"

# Opens consent page in browser
# Waits for human approval
# Prints ACT JWT to stdout


# ── Headless: prints device code instead of opening browser ──

x401 authorize --headless \
  --cap "github:acme/backend/push:branch:staging" \
  --lim "cnt:20,per:86400" \
  --exp 24h \
  --reason "Deploy hotfix"

# Prints: "Authorize at https://auth.x401.dev/consent/abc123 — code: WXYZ-1234"
# Polls, prints ACT to stdout when approved


# ── Pre-signed grant: create ACT offline ──

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


# ── Generate proof-of-possession for a specific request ──

x401 proof \
  --act ./act.jwt \
  --method POST \
  --url "https://gateway.x401.dev/gmail/send"

# Prints proof JWT to stdout


# ── Revoke an ACT ──

x401 revoke --jti 0xdeadbeef1234567890abcdef
