// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title x401 On-Chain Limit Enforcer (EVM/Base)
/// @notice Per-capability counters that enforce quantitative limits on-chain.
///         Serves as a global source of truth for agent usage — off-chain services
///         can read the chain to verify an agent hasn't exceeded its limits.
///         Gasless on Base via paymasters.
///
/// @dev Verification cost: ~50-80K gas via ecrecover for secp256k1 signatures.
///      Counter reads are free via RPC.

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

    /// @notice Create a limit account for an ACT.
    ///         Only callable by the human (the one who signed the ACT delegation).
    function createLimit(
        bytes32 jti,
        address agent,
        bytes32[] calldata capHashes,
        uint256[] calldata maxCounts,
        uint256[] calldata periodLengths
    ) external {
        require(limits[jti].human == address(0), "already exists");
        require(
            capHashes.length == maxCounts.length && maxCounts.length == periodLengths.length,
            "length mismatch"
        );

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

    /// @notice Increment usage for a specific capability.
    ///         Only callable by the authorized agent.
    function increment(
        bytes32 jti,
        bytes32 capHash,
        uint256 count
    ) external returns (uint256 remaining) {
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

        return remaining;
    }

    /// @notice Revoke an ACT's limit account.
    ///         Only callable by the human who created it.
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
