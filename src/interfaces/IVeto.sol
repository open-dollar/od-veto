// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {AccessControl} from '@openzeppelin/access/AccessControl.sol';

contract IVeto is AccessControl {
  error InvalidSignature();
  error AccessDenied();

  event NewGovernor(address governor);
}
