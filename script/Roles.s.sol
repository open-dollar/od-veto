// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import '@script/Registry.s.sol';
import {Script} from 'forge-std/Script.sol';
import {Veto} from '@contracts/Veto.sol';

abstract contract MainnetDeployment {
  Veto public veto;

  constructor() {
    veto = Veto(MAINNET_VETO);
  }
}

// BROADCAST
// source .env && forge script AddVetoManager --skip-simulation --with-gas-price 2000000000 -vvvvv --rpc-url $ARB_MAINNET_RPC --broadcast --verify --etherscan-api-key $ARB_ETHERSCAN_API_KEY

// SIMULATE
// source .env && forge script AddVetoManager --with-gas-price 2000000000 -vvvvv --rpc-url $ARB_MAINNET_RPC

contract AddVetoManager is MainnetDeployment, Script {
  function run() public {
    vm.startBroadcast(vm.addr(vm.envUint('ARB_MAINNET_DEPLOYER_PK')));

    address _delegate = vm.addr(vm.envUint('ARB_NEW_VETO_MANAGER'));

    veto.grantRole(veto.VETO_ROLE(), _delegate);

    vm.stopBroadcast();
  }
}

// BROADCAST
// source .env && forge script AddCandidate --skip-simulation --with-gas-price 2000000000 -vvvvv --rpc-url $ARB_MAINNET_RPC --broadcast --verify --etherscan-api-key $ARB_ETHERSCAN_API_KEY

// SIMULATE
// source .env && forge script AddCandidate --with-gas-price 2000000000 -vvvvv --rpc-url $ARB_MAINNET_RPC

contract AddCandidate is MainnetDeployment, Script {
  function run() public {
    vm.startBroadcast(vm.addr(vm.envUint('ARB_MAINNET_DEPLOYER_PK')));

    address _delegate = vm.addr(vm.envUint('ARB_NEW_CANDIDATE'));

    veto.grantRole(veto.VETO_CANDIDATE_ROLE(), _delegate);

    vm.stopBroadcast();
  }
}

// BROADCAST
// source .env && forge script AddAdmin --skip-simulation --with-gas-price 2000000000 -vvvvv --rpc-url $ARB_MAINNET_RPC --broadcast --verify --etherscan-api-key $ARB_ETHERSCAN_API_KEY

// SIMULATE
// source .env && forge script AddAdmin --with-gas-price 2000000000 -vvvvv --rpc-url $ARB_MAINNET_RPC

contract AddAdmin is MainnetDeployment, Script {
  function run() public {
    vm.startBroadcast(vm.addr(vm.envUint('ARB_MAINNET_DEPLOYER_PK')));

    address _admin = vm.addr(vm.envUint('ARB_NEW_ADMIN'));

    veto.grantRole(veto.DEFAULT_ADMIN_ROLE(), _admin);

    vm.stopBroadcast();
  }
}
