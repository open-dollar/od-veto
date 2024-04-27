// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {IVeto} from '@interfaces/IVeto.sol';
import {IGovernor} from '@openzeppelin/governance/IGovernor.sol';
import {SignatureChecker} from '@openzeppelin/utils/cryptography/SignatureChecker.sol';
import {Strings} from '@openzeppelin/utils/Strings.sol';

contract Veto is IVeto {
  IGovernor public governor;
  string public pledge;
  bytes32 public constant VETO_CANDIDATE_ROLE = keccak256('VETO_CANDIDATE_ROLE');
  bytes32 public constant VETO_ROLE = keccak256('VETO_ROLE');

  enum VoteType {
    Against,
    For,
    Abstain
  }

  /**
   * @dev Constructor
   * @param _governor The OZ governor contract to target.
   * @param _pledge The pledge that veto candidates must sign to gain access.
   */
  constructor(address _governor, string memory _pledge) {
    governor = IGovernor(_governor);
    emit NewGovernor(_governor);
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    pledge = _pledge;
  }

  /**
   * @dev Updates the governor address.
   * @param _governor The address of the new governor contract.
   */
  function setGovernor(address _governor) external onlyRole(DEFAULT_ADMIN_ROLE) {
    governor = IGovernor(_governor);
    emit NewGovernor(_governor);
  }

  /**
   * @dev Enables a candidate to accept veto power by signing the pledge.
   * @param signature A signature over the message in `pledge`.
   */
  function enableVeto(bytes memory signature) external onlyRole(VETO_CANDIDATE_ROLE) {
    if (!SignatureChecker.isValidSignatureNow(msg.sender, _toEthSignedMessageHash(bytes(pledge)), signature)) {
      revert InvalidSignature();
    }
    _grantRole(VETO_ROLE, msg.sender);
    _revokeRole(VETO_CANDIDATE_ROLE, msg.sender);
  }

  /**
   * @dev Enables a vetoer to veto the specified proposal.
   * @param proposalId The proposal ID of the proposal to veto.
   */
  function castVote(uint256 proposalId) public virtual onlyRole(VETO_ROLE) returns (uint256 balance) {
    return governor.castVote(proposalId, uint8(VoteType.Against));
  }

  /**
   * @dev Enables a vetoer to veto the specified proposal.
   * @param proposalId The proposal ID of the proposal to veto.
   * @param reason An explanation of why the vote is being vetoed.
   */
  function castVoteWithReason(
    uint256 proposalId,
    string calldata reason
  ) public virtual onlyRole(VETO_ROLE) returns (uint256 balance) {
    return governor.castVoteWithReason(proposalId, uint8(VoteType.Against), reason);
  }

  /**
   * @dev Returns the keccak256 digest of an ERC-191 signed data with version
   * `0x45` (`personal_sign` messages).
   *
   * The digest is calculated by prefixing an arbitrary `message` with
   * `"\x19Ethereum Signed Message:\n" + len(message)` and hashing the result. It corresponds with the
   * hash signed when using the https://eth.wiki/json-rpc/API#eth_sign[`eth_sign`] JSON-RPC method.
   *
   * See {ECDSA-recover}.
   */
  function _toEthSignedMessageHash(bytes memory message) internal pure returns (bytes32) {
    return keccak256(bytes.concat('\x19Ethereum Signed Message:\n', bytes(Strings.toString(message.length)), message));
  }
}
