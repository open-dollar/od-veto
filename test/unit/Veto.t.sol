// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import '@script/Registry.s.sol';
import {Test, console} from 'forge-std/Test.sol';
import {Veto, IVeto} from '@contracts/Veto.sol';
import {Governor, IGovernor} from '@openzeppelin/governance/Governor.sol';
import {TimelockController} from '@openzeppelin/governance/TimelockController.sol';
import {ODGovernor} from '@test/mock-contracts/ODGovernor.sol';
import {ProtocolToken} from '@test/mock-contracts/ProtocolToken.sol';
import {ECDSA} from '@openzeppelin/utils/cryptography/ECDSA.sol';
import {ENS} from '@ens/registry/ENS.sol';

/**
 * @notice ProposalState:
 * Pending = 0
 * Active = 1
 * Canceled = 2
 * Defeated = 3
 * Succeeded = 4
 * Queued = 5
 * Expired = 6
 * Executed = 7
 */
contract Base is Test {
  using ECDSA for bytes;

  ENS internal constant _ENS = ENS(address(0x0));
  address public constant alice = address(0xa11ce);
  address public constant bob = address(0xb0b);
  address public constant caleb = address(0xca13b);
  address public constant concentratedVetoPower = address(0x333);
  uint256 public constant concentratedVetoWeight = TOKEN_DROP * 2;
  string public constant proposal_description = 'Proposal #1: Mock Proposal';

  string public constant pledge = 'I pledge to defend the DAO that this Veto contract is attached to from attackers';
  bytes32 public pledgeHash = abi.encodePacked(pledge).toEthSignedMessageHash();

  address public derek;
  uint256 public derekPk;
  address public nonDelegate;
  uint256 public nonDelegatePk;

  ODGovernor public governor;
  Veto public veto;
  ProtocolToken public voteToken;
  TimelockController public timelockController;

  address public deployer = address(this);
  address[3] public delegates = [alice, bob, caleb];

  function setUp() public virtual {
    address[] memory members = new address[](0);

    (derek, derekPk) = makeAddrAndKey('alice');
    (nonDelegate, nonDelegatePk) = makeAddrAndKey('rando');

    voteToken = new ProtocolToken('voteToken', 'VT');
    timelockController = new TimelockController(TEST_INIT_VOTING_DELAY, members, members, deployer);
    governor = new ODGovernor(
      TEST_INIT_VOTING_DELAY,
      TEST_INIT_VOTING_PERIOD,
      TEST_INIT_PROP_THRESHOLD,
      TEST_INIT_VOTE_QUORUM,
      address(voteToken),
      timelockController
    );
    timelockController.grantRole(timelockController.EXECUTOR_ROLE(), address(governor));
    timelockController.grantRole(timelockController.PROPOSER_ROLE(), address(governor));

    veto = new Veto(address(governor), pledge);

    _mintVoteTokens();
    vm.roll(1);
    _delegateVoteTokens();
  }

  function _mintVoteTokens() internal {
    for (uint256 i = 0; i < delegates.length; i++) {
      voteToken.mint(delegates[i], TOKEN_DROP);
    }
    voteToken.mint(derek, TOKEN_DROP);
    voteToken.mint(concentratedVetoPower, concentratedVetoWeight);
    uint256 _ts = voteToken.totalSupply();
    voteToken.mint(deployer, TOKEN_SUPPLY - _ts);
  }

  function _delegateVoteTokens() internal {
    for (uint256 i = 0; i < delegates.length; i++) {
      vm.prank(delegates[i]);
      voteToken.delegate(delegates[i]);
    }
  }

  function _createProposal() internal returns (uint256 propId) {
    (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _createProposalArgs();
    vm.prank(alice);
    propId = governor.propose(targets, values, calldatas, proposal_description);
  }

  function _createProposalAndWarp() internal returns (uint256 propId) {
    vm.roll(2);
    propId = _createProposal();
    vm.roll(6);
  }

  function _createProposalArgs()
    internal
    view
    returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
  {
    calldatas = new bytes[](1);
    calldatas[0] = abi.encodeWithSignature('mint(address,uint256)', deployer, 100 ether);
    targets = new address[](1);
    targets[0] = address(voteToken);
    values = new uint256[](1);
    values[0] = 0;
  }
}

contract Test_SetUp is Base {
  function testGovernorSetUp() public {
    assertEq(governor.votingDelay(), TEST_INIT_VOTING_DELAY);
    assertEq(governor.votingPeriod(), TEST_INIT_VOTING_PERIOD);
    assertEq(governor.proposalThreshold(), TEST_INIT_PROP_THRESHOLD);
    assertEq(address(governor.token()), address(voteToken));
    assertEq(address(governor.timelock()), address(timelockController));
  }

  function testTotalSupply() public {
    assertEq(voteToken.totalSupply(), TOKEN_SUPPLY);
  }

  function testDelegateSupply() public {
    for (uint256 i = 0; i < delegates.length; i++) {
      assertEq(voteToken.balanceOf(delegates[i]), TOKEN_DROP);
    }
    assertEq(voteToken.balanceOf(nonDelegate), 0);
  }

  function testDelegateTokens() public {
    vm.roll(2);
    for (uint256 i = 0; i < delegates.length; i++) {
      assertEq(governor.getVotes(delegates[i], 0), 0);
    }
    assertEq(governor.getVotes(nonDelegate, 0), 0);

    for (uint256 i = 0; i < delegates.length; i++) {
      assertEq(governor.getVotes(delegates[i], 1), TOKEN_DROP);
    }
    assertEq(governor.getVotes(nonDelegate, 1), 0);
  }

  function testPropose() public {
    vm.expectRevert('Governor: proposer votes below proposal threshold');
    _createProposal();
    vm.roll(2);
    _createProposal();
  }

  function testActivateProposal() public {
    vm.roll(2);
    uint256 propId = _createProposal();
    assertEq(uint256(governor.state(propId)), uint256(IGovernor.ProposalState.Pending));
    vm.roll(6);
    assertEq(uint256(governor.state(propId)), uint256(IGovernor.ProposalState.Active));
  }

  function testVoteOnProposalDefeat() public {
    uint256 propId = _createProposalAndWarp();
    vm.prank(alice);
    governor.castVote(propId, 0); // against
    vm.prank(bob);
    governor.castVote(propId, 1); // for
    vm.prank(caleb);
    governor.castVote(propId, 2); // abstain

    vm.roll(governor.proposalDeadline(propId) + 1);
    assertEq(uint256(governor.state(propId)), uint256(IGovernor.ProposalState.Defeated));
  }

  function testVoteOnProposalSucceed() public {
    uint256 propId = _createProposalAndWarp();
    vm.prank(alice);
    governor.castVote(propId, 1);
    vm.prank(bob);
    governor.castVote(propId, 1);
    vm.prank(caleb);
    governor.castVote(propId, 0);

    vm.roll(governor.proposalDeadline(propId) + 1);
    assertEq(uint256(governor.state(propId)), uint256(IGovernor.ProposalState.Succeeded));
  }
}

contract UnitTest_Veto is Base {
  function setUp() public override {
    super.setUp();

    veto.grantRole(veto.VETO_CANDIDATE_ROLE(), derek);
    veto.grantRole(veto.VETO_CANDIDATE_ROLE(), nonDelegate);

    vm.prank(concentratedVetoPower);
    voteToken.delegate(address(veto));
  }

  function testDelegateVetoContract() public {
    vm.roll(2);
    assertEq(governor.getVotes(address(veto), 1), concentratedVetoWeight);
  }

  function testAcceptRole() public {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(derekPk, pledgeHash);
    bytes memory sig = abi.encodePacked(r, s, v);
    vm.prank(derek);
    veto.enableVeto(sig);
    assertFalse(veto.hasRole(veto.VETO_CANDIDATE_ROLE(), derek));
    assertTrue(veto.hasRole(veto.VETO_ROLE(), derek));
  }

  function testAcceptRoleInvalidSignatureRevert() public {
    string memory differentPledge = 'No, I do not agree to pledge';
    bytes32 differentPledgeHash = ECDSA.toEthSignedMessageHash(abi.encodePacked(differentPledge));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(derekPk, differentPledgeHash);
    bytes memory sig = abi.encodePacked(r, s, v);
    vm.startPrank(derek);
    vm.expectRevert();
    veto.enableVeto(sig);
    vm.stopPrank();
    assertTrue(veto.hasRole(veto.VETO_CANDIDATE_ROLE(), derek));
    assertFalse(veto.hasRole(veto.VETO_ROLE(), derek));
  }

  function testNoAcceptRoleAndVetoRevert() public {
    assertTrue(veto.hasRole(veto.VETO_CANDIDATE_ROLE(), derek));
    assertFalse(veto.hasRole(veto.VETO_ROLE(), derek));
    uint256 propId = _propAndAllYesVote();
    vm.startPrank(derek);
    vm.expectRevert();
    veto.castVote(propId);
    vm.stopPrank();
  }

  // with <50%
  function testAcceptRoleAndVetoWithDelegate() public {
    _generateSig(derekPk);
    uint256 propId = _propAndAllYesVote();
    vm.prank(derek);
    veto.castVote(propId);
    vm.roll(governor.proposalDeadline(propId) + 1);
    assertEq(uint256(governor.state(propId)), uint256(IGovernor.ProposalState.Succeeded));
  }

  function testAcceptRoleAndVetoWithNonDelegate() public {
    _generateSig(nonDelegatePk);
    uint256 propId = _propAndAllYesVote();
    vm.prank(nonDelegate);
    veto.castVote(propId);
    vm.roll(governor.proposalDeadline(propId) + 1);
    assertEq(uint256(governor.state(propId)), uint256(IGovernor.ProposalState.Succeeded));
  }

  // with 50%
  function testAcceptRoleAndVetoWithDelegate50Percent() public {
    _generateSig(derekPk);
    uint256 propId = _propAndMajorityYesVote();
    vm.prank(derek);
    veto.castVote(propId);
    vm.roll(governor.proposalDeadline(propId) + 1);
    assertEq(uint256(governor.state(propId)), uint256(IGovernor.ProposalState.Defeated));
  }

  function testAcceptRoleAndVetoWithNonDelegate50Percent() public {
    _generateSig(nonDelegatePk);
    uint256 propId = _propAndMajorityYesVote();
    vm.prank(nonDelegate);
    veto.castVote(propId);
    vm.roll(governor.proposalDeadline(propId) + 1);
    assertEq(uint256(governor.state(propId)), uint256(IGovernor.ProposalState.Defeated));
  }

  // with <50%
  function testCastVetoWithDelegate() public {
    _forceVetoRole(derek);
    uint256 propId = _propAndAllYesVote();
    vm.prank(derek);
    veto.castVote(propId);
    vm.roll(governor.proposalDeadline(propId) + 1);
    assertEq(uint256(governor.state(propId)), uint256(IGovernor.ProposalState.Succeeded));
  }

  function testCastVetoWithNonDelegate() public {
    _forceVetoRole(nonDelegate);
    uint256 propId = _propAndAllYesVote();
    vm.prank(nonDelegate);
    veto.castVote(propId);
    vm.roll(governor.proposalDeadline(propId) + 1);
    assertEq(uint256(governor.state(propId)), uint256(IGovernor.ProposalState.Succeeded));
  }

  // with 50%
  function testCastVetoWithDelegate50Percent() public {
    _forceVetoRole(derek);
    uint256 propId = _propAndMajorityYesVote();
    vm.prank(derek);
    veto.castVote(propId);
    vm.roll(governor.proposalDeadline(propId) + 1);
    assertEq(uint256(governor.state(propId)), uint256(IGovernor.ProposalState.Defeated));
  }

  function testCastVetoWithNonDelegate50Percent() public {
    _forceVetoRole(nonDelegate);
    uint256 propId = _propAndMajorityYesVote();
    vm.prank(nonDelegate);
    veto.castVote(propId);
    vm.roll(governor.proposalDeadline(propId) + 1);
    assertEq(uint256(governor.state(propId)), uint256(IGovernor.ProposalState.Defeated));
  }

  // delegate votes Yes with tokens and vetos No with veto contract
  function testVoteAndVeto() public {
    _forceVetoRole(alice);
    assertTrue(veto.hasRole(veto.VETO_ROLE(), alice));
    uint256 propId = _propAndAllYesVote();
    vm.prank(alice);
    veto.castVote(propId);
    vm.roll(governor.proposalDeadline(propId) + 1);
    assertEq(uint256(governor.state(propId)), uint256(IGovernor.ProposalState.Succeeded));
  }

  function testVoteAndVeto50Percent() public {
    _forceVetoRole(alice);
    assertTrue(veto.hasRole(veto.VETO_ROLE(), alice));
    uint256 propId = _propAndMajorityYesVote();
    vm.prank(alice);
    veto.castVote(propId);
    vm.roll(governor.proposalDeadline(propId) + 1);
    assertEq(uint256(governor.state(propId)), uint256(IGovernor.ProposalState.Defeated));
  }

  function _propAndAllYesVote() internal returns (uint256) {
    uint256 propId = _createProposalAndWarp();
    vm.prank(alice);
    governor.castVote(propId, 1);
    vm.prank(bob);
    governor.castVote(propId, 1);
    vm.prank(caleb);
    governor.castVote(propId, 1);
    return propId;
  }

  function _propAndMajorityYesVote() internal returns (uint256) {
    uint256 propId = _createProposalAndWarp();
    vm.prank(alice);
    governor.castVote(propId, 1);
    vm.prank(bob);
    governor.castVote(propId, 1);
    vm.prank(caleb);
    governor.castVote(propId, 2);
    return propId;
  }

  function _forceVetoRole(address vetoer) internal {
    veto.grantRole(veto.VETO_ROLE(), vetoer);
  }

  function _generateSig(uint256 privateKey) internal returns (bytes memory sig) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, pledgeHash);
    sig = abi.encodePacked(r, s, v);
    vm.prank(vm.addr(privateKey));
    veto.enableVeto(sig);
  }
}
