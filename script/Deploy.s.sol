// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import '@script/Registry.s.sol';
import {Script} from 'forge-std/Script.sol';
import {Veto} from '@contracts/Veto.sol';

// BROADCAST
// source .env && forge script Deploy --skip-simulation --with-gas-price 2000000000 -vvvvv --rpc-url $ARB_MAINNET_RPC --broadcast --verify --etherscan-api-key $ARB_ETHERSCAN_API_KEY

// SIMULATE
// source .env && forge script Deploy --with-gas-price 2000000000 -vvvvv --rpc-url $ARB_MAINNET_RPC

/**
 * @dev deploys a Veto contract that has delegated voting weight and elected delegates to vote against governance-attack proposals
 *
 * @notice add IPFS hashed location of pledge in script/Registry.s.sol before broadcast
 */
contract Deploy is Script {
  function run() public {
    vm.startBroadcast(vm.addr(vm.envUint('ARB_MAINNET_DEPLOYER_PK')));

    new Veto(MAINNET_OD_GOVERNOR, MAINNET_OD_VETO_DELEGATE_PLEDGE);

    vm.stopBroadcast();
  }
}
