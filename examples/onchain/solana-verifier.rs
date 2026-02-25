/// x401 Solana/Anchor On-Chain Verifier
///
/// A smart contract that verifies ACTs natively on Solana.
/// Checks delegation signatures, enforces spending limits with
/// per-capability counters, and supports revocation.
///
/// Cost: ~5,000-6,000 compute units for a 2-signature delegation chain
/// (Ed25519 verification via native program at ~2,280 CU per signature)

use anchor_lang::prelude::*;

declare_id!("x401...");

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

#[error_code]
pub enum X401Error {
    #[msg("ACT has been revoked")]
    Revoked,
    #[msg("ACT has expired")]
    Expired,
    #[msg("Signature verification failed")]
    InvalidSignature,
    #[msg("Spending limit exceeded")]
    ExceedsLimit,
    #[msg("Arithmetic overflow")]
    Overflow,
    #[msg("Unauthorized")]
    Unauthorized,
}

#[event]
pub struct Revoked {
    pub jti: [u8; 32],
    pub revoker: Pubkey,
}
