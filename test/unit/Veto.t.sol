// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import '@script/Registry.s.sol';
import {Test, console} from 'forge-std/Test.sol';
import {Veto, IVeto} from '@contracts/Veto.sol';
import {Governor, IGovernor} from '@openzeppelin/governance/Governor.sol';
import {TimelockController} from '@openzeppelin/governance/TimelockController.sol';
import {ODGovernor} from '@test/mock-contracts/ODGovernor.sol';
import {ProtocolToken} from '@test/mock-contracts/ProtocolToken.sol';

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
  address constant alice = address(0xa11ce);
  address constant bob = address(0xb0b);
  address constant caleb = address(0xca13b);
  address constant nonDelegate = address(0x101);
  address constant concentratedVetoPower = address(0x666);
  uint256 constant concentratedVetoWeight = TOKEN_DROP * 3;

  string constant pledge = 'I pledge to defend the DAO that this Veto contract is attached to from attackers';
  bytes32 constant pledgeHash = keccak256(abi.encodePacked(pledge));

  string constant proposal_description = 'Proposal #1: Mock Proposal';

  ODGovernor public governor;
  Veto public veto;
  ProtocolToken public voteToken;
  TimelockController public timelockController;

  address public deployer = address(this);
  address[3] public delegates = [alice, bob, caleb];

  function setUp() public virtual {
    address[] memory members = new address[](0);

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
    (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = __createProposalArgs();
    vm.prank(alice);
    propId = governor.propose(targets, values, calldatas, proposal_description);
  }

  function __createProposalArgs()
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
    vm.roll(2);
    uint256 propId = _createProposal();
    vm.roll(6);
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
    vm.roll(2);
    uint256 propId = _createProposal();
    vm.roll(6);
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

    veto.grantRole(veto.VETO_CANDIDATE_ROLE(), alice);
    veto.grantRole(veto.VETO_CANDIDATE_ROLE(), nonDelegate);

    vm.prank(concentratedVetoPower);
    voteToken.delegate(address(veto));
  }

  function testDelegateVetoContract() public {
    vm.roll(2);
    assertEq(governor.getVotes(address(veto), 1), concentratedVetoWeight);
  }

  function testAcceptRole() public {}

  function testAcceptRoleInvalidSignatureRevert() public {}

  function testAcceptRoleAndVetoWithDelegate() public {}

  function testAcceptRoleAndVetoWithNonDelegate() public {}

  function testNoAcceptRoleAndVetoRevert() public {}

  function testCastVetoWithDelegate() public {
    _forceVetoRole(alice);
    vm.roll(2);
    uint256 propId = _createProposal();
    vm.roll(6);
    vm.prank(alice);
    governor.castVote(propId, 1);
    vm.prank(bob);
    governor.castVote(propId, 1);
  }

  function testCastVetoWithNonDelegate() public {
    _forceVetoRole(nonDelegate);
  }

  function _forceVetoRole(address vetoer) internal {
    veto.grantRole(veto.VETO_ROLE, vetoer);
  }
}
