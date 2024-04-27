// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {ERC20Votes, ERC20Permit, ERC20} from '@openzeppelin/token/ERC20/extensions/ERC20Votes.sol';

/**
 * @title  ProtocolToken
 * @notice This contract represents the protocol ERC20Votes token to be used for governance purposes
 */
contract ProtocolToken is ERC20Votes {
  /**
   * @param  _name String with the name of the token
   * @param  _symbol String with the symbol of the token
   */
  constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) ERC20Permit(_name) {}

  // --- Methods ---

  function mint(address _dst, uint256 _wad) external {
    _mint(_dst, _wad);
  }

  function burn(uint256 _wad) external {
    _burn(msg.sender, _wad);
  }
}
