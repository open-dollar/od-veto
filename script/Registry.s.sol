// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

// Token
uint256 constant TOKEN_SUPPLY = 10_000_000 ether; // 10m
uint256 constant TOKEN_DROP = 10_000 ether; // 10K (0.001 %)

// Governance Settings
uint256 constant TEST_INIT_VOTING_DELAY = 3;
uint256 constant TEST_INIT_VOTING_PERIOD = 15;
uint256 constant TEST_INIT_PROP_THRESHOLD = 5000 * 1e18; // 5k (0.0005 %)
uint256 constant TEST_INIT_VOTE_QUORUM = 1; // 10k
