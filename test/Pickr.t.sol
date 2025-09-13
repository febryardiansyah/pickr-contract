// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Pickr} from "../src/Pickr.sol";

contract PickrTest is Test {
    Pickr internal pickr;

    address internal creator;
    address internal alice;
    address internal bob;
    address internal carol;
    address internal dave;

    string internal constant CODE1 = "RAFFLE1";
    string internal constant CODE2 = "RAFFLE2";

    function setUp() public {
        pickr = new Pickr();
        creator = makeAddr("creator");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        dave = makeAddr("dave");

        // seed balances
        vm.deal(creator, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
        vm.deal(dave, 100 ether);
    }

    // helpers
    function _createRaffle(address _creator, string memory code, uint256 maxP, uint256 minP, uint256 value) internal {
        vm.prank(_creator);
        pickr.createRaffle{value: value}(maxP, minP, code);
    }

    function _join(address user, string memory code) internal {
        vm.prank(user);
        pickr.joinRaffle(code);
    }

    // createRaffle
    function test_CreateRaffle_Success() public {
        _createRaffle(creator, CODE1, 5, 2, 1 ether);

        (
            address c,
            uint256 balance,
            Pickr.RaffleStatus status,
            uint256 maxP,
            uint256 minP,
            uint256 totalP,
            uint64 createdAt
        ) = pickr.raffles(CODE1);

        assertEq(c, creator, "creator mismatch");
        assertEq(balance, 1 ether, "balance mismatch");
        assertEq(uint8(status), uint8(Pickr.RaffleStatus.ACTIVE), "status");
        assertEq(maxP, 5, "maxP");
        assertEq(minP, 2, "minP");
        assertEq(totalP, 0, "totalP");
        assertGt(uint256(createdAt), 0, "createdAt");

        string[] memory codes = pickr.getUserRaffleCodes(creator);
        assertEq(codes.length, 1);
        assertEq(keccak256(bytes(codes[0])), keccak256(bytes(CODE1)));

        (Pickr.Raffle[] memory raffs, string[] memory codes2) = pickr.getUserRaffles(creator);
        assertEq(raffs.length, 1);
        assertEq(codes2.length, 1);
        assertEq(raffs[0].creator, creator);
        assertEq(raffs[0].balance, 1 ether);
    }

    function test_CreateRaffle_Revert_NoDeposit() public {
        vm.prank(creator);
        vm.expectRevert(bytes("Initial deposit is required"));
        pickr.createRaffle(5, 2, CODE1);
    }

    function test_CreateRaffle_Revert_MaxLEMin() public {
        vm.prank(creator);
        vm.expectRevert(bytes("Max participant must be greater than min participant"));
        pickr.createRaffle{value: 1 ether}(2, 2, CODE1);
    }

    function test_CreateRaffle_Revert_MinZero() public {
        vm.prank(creator);
        vm.expectRevert(bytes("Min participant must be greater than 0"));
        pickr.createRaffle{value: 1 ether}(2, 0, CODE1);
    }

    function test_CreateRaffle_Revert_EmptyCode() public {
        vm.prank(creator);
        vm.expectRevert(bytes("Code is required"));
        pickr.createRaffle{value: 1 ether}(5, 2, "");
    }

    function test_CreateRaffle_Revert_DuplicateCode() public {
        _createRaffle(creator, CODE1, 5, 2, 1 ether);
        vm.prank(creator);
        vm.expectRevert(bytes("Code already used"));
        pickr.createRaffle{value: 1 ether}(6, 2, CODE1);
    }

    // deposit
    function test_Deposit_Success_IncreasesBalance() public {
        _createRaffle(creator, CODE1, 5, 2, 1 ether);

        vm.prank(alice);
        pickr.deposit{value: 0.5 ether}(CODE1);

        (, uint256 balance,,,,,) = pickr.raffles(CODE1);
        assertEq(balance, 1.5 ether, "deposit didn't add");
    }

    function test_Deposit_Revert_NonexistentCode() public {
        vm.prank(alice);
        vm.expectRevert(bytes("Raffle does not exist"));
        pickr.deposit{value: 1 ether}(CODE1);
    }

    function test_Deposit_Revert_ZeroValue() public {
        _createRaffle(creator, CODE1, 5, 2, 1 ether);
        vm.prank(alice);
        vm.expectRevert(bytes("Deposit must be greater than 0"));
        pickr.deposit(CODE1);
    }

    function test_Deposit_Revert_WhenStarted() public {
        _createRaffle(creator, CODE1, 5, 2, 1 ether);
        _join(alice, CODE1);
        _join(bob, CODE1);
        vm.prank(creator);
        pickr.startRaffle(CODE1);

        vm.prank(alice);
        vm.expectRevert(bytes("Raffle is already inactive or started"));
        pickr.deposit{value: 1 ether}(CODE1);
    }

    // join / leave
    function test_JoinRaffle_Success() public {
        _createRaffle(creator, CODE1, 3, 1, 1 ether);
        _join(alice, CODE1);
        _join(bob, CODE1);

        (,,,,, uint256 totalP,) = pickr.raffles(CODE1);
        assertEq(totalP, 2);

        address[] memory parts = pickr.raffleParticipants(CODE1);
        assertEq(parts.length, 2);
        // order is not guaranteed after leaves, but here it's sequential joins
        assertEq(parts[0], alice);
        assertEq(parts[1], bob);
    }

    function test_JoinRaffle_Revert_OwnerCannotJoinOwnRaffle() public {
        _createRaffle(creator, CODE1, 3, 1, 1 ether);
        vm.prank(creator);
        vm.expectRevert(bytes("You can't join to your own raffle"));
        pickr.joinRaffle(CODE1);
    }

    function test_JoinRaffle_Revert_DuplicateJoin() public {
        _createRaffle(creator, CODE1, 3, 1, 1 ether);
        _join(alice, CODE1);
        vm.prank(alice);
        vm.expectRevert(bytes("You have already joined"));
        pickr.joinRaffle(CODE1);
    }

    function test_JoinRaffle_Revert_Full() public {
        _createRaffle(creator, CODE1, 2, 1, 1 ether);
        _join(alice, CODE1);
        _join(bob, CODE1);
        vm.prank(carol);
        vm.expectRevert(bytes("Raffle is full"));
        pickr.joinRaffle(CODE1);
    }

    function test_LeaveRaffle_Success_RemovesParticipant() public {
        _createRaffle(creator, CODE1, 3, 1, 1 ether);
        _join(alice, CODE1);
        _join(bob, CODE1);
        _join(carol, CODE1);

        vm.prank(bob);
        pickr.leaveRaffle(CODE1);

        (,,,,, uint256 totalP,) = pickr.raffles(CODE1);
        assertEq(totalP, 2);

        address[] memory parts = pickr.raffleParticipants(CODE1);
        assertEq(parts.length, 2);
        // bob should not be present; remaining should be alice and carol in any order
        bool hasAlice;
        bool hasCarol;
        for (uint256 i = 0; i < parts.length; i++) {
            if (parts[i] == alice) hasAlice = true;
            if (parts[i] == carol) hasCarol = true;
            assertTrue(parts[i] != bob, "bob still listed");
        }
        assertTrue(hasAlice && hasCarol, "remaining participants mismatch");
    }

    function test_LeaveRaffle_Revert_NotJoined() public {
        _createRaffle(creator, CODE1, 3, 1, 1 ether);
        vm.prank(alice);
        vm.expectRevert(bytes("You have not joined the raffle yet"));
        pickr.leaveRaffle(CODE1);
    }

    // startRaffle
    function test_StartRaffle_Success() public {
        _createRaffle(creator, CODE1, 5, 2, 1 ether);
        _join(alice, CODE1);
        _join(bob, CODE1);
        vm.prank(creator);
        pickr.startRaffle(CODE1);

        (,, Pickr.RaffleStatus status,,,,) = pickr.raffles(CODE1);
        assertEq(uint8(status), uint8(Pickr.RaffleStatus.STARTED));
    }

    function test_StartRaffle_Revert_NotEnoughParticipants() public {
        _createRaffle(creator, CODE1, 5, 2, 1 ether);
        _join(alice, CODE1);
        vm.prank(creator);
        vm.expectRevert(bytes("Not enough participants"));
        pickr.startRaffle(CODE1);
    }

    function test_StartRaffle_Revert_OnlyCreator() public {
        _createRaffle(creator, CODE1, 5, 1, 1 ether);
        _join(alice, CODE1);
        vm.prank(alice);
        vm.expectRevert(bytes("Not authorized"));
        pickr.startRaffle(CODE1);
    }

    // winnerSelected
    function test_WinnerSelected_Success_TransfersPrizeAndCloses() public {
        _createRaffle(creator, CODE1, 5, 2, 2 ether);
        // extra deposit to have a clear prize
        vm.prank(dave);
        pickr.deposit{value: 1 ether}(CODE1);

        _join(alice, CODE1);
        _join(bob, CODE1);

        vm.prank(creator);
        pickr.startRaffle(CODE1);

        uint256 prizeBefore;
        (, prizeBefore,,,,,) = pickr.raffles(CODE1);
        assertEq(prizeBefore, 3 ether);

        uint256 bobBalBefore = bob.balance;

        vm.prank(creator);
        pickr.winnerSelected(CODE1, bob);

        // state changes
        (,, Pickr.RaffleStatus statusAfter,,,,) = pickr.raffles(CODE1);
        assertEq(uint8(statusAfter), uint8(Pickr.RaffleStatus.INACTIVE));
        (, uint256 balanceAfter,,,,,) = pickr.raffles(CODE1);
        assertEq(balanceAfter, 0);
        assertEq(pickr.winners(CODE1), bob);

        // payout
        assertEq(bob.balance, bobBalBefore + prizeBefore);
    }

    function test_WinnerSelected_Revert_NotStarted() public {
        _createRaffle(creator, CODE1, 5, 1, 1 ether);
        _join(alice, CODE1);
        vm.prank(creator);
        vm.expectRevert(bytes("Raffle is not started"));
        pickr.winnerSelected(CODE1, alice);
    }

    function test_WinnerSelected_Revert_InvalidWinner() public {
        _createRaffle(creator, CODE1, 5, 1, 1 ether);
        _join(alice, CODE1);
        vm.prank(creator);
        pickr.startRaffle(CODE1);

        vm.prank(creator);
        vm.expectRevert(bytes("Invalid winner"));
        pickr.winnerSelected(CODE1, address(0));
    }

    function test_WinnerSelected_Revert_NotParticipant() public {
        _createRaffle(creator, CODE1, 5, 1, 1 ether);
        _join(alice, CODE1);
        vm.prank(creator);
        pickr.startRaffle(CODE1);

        vm.prank(creator);
        vm.expectRevert(bytes("Winner not a participant"));
        pickr.winnerSelected(CODE1, bob);
    }

    // closeRaffle
    function test_CloseRaffle_Success_RefundsCreator() public {
        _createRaffle(creator, CODE1, 5, 1, 2 ether);
        // add extra deposit from others
        vm.prank(alice);
        pickr.deposit{value: 1.5 ether}(CODE1);

        (, uint256 balanceBefore,,,,,) = pickr.raffles(CODE1);
        assertEq(balanceBefore, 3.5 ether);

        uint256 creatorBefore = creator.balance;
        vm.prank(creator);
        pickr.closeRaffle(CODE1);

        // status & balance
        (,, Pickr.RaffleStatus statusAfter,,,,) = pickr.raffles(CODE1);
        assertEq(uint8(statusAfter), uint8(Pickr.RaffleStatus.INACTIVE));
        (, uint256 balanceAfter,,,,,) = pickr.raffles(CODE1);
        assertEq(balanceAfter, 0);

        // refund
        assertEq(creator.balance, creatorBefore + balanceBefore);
    }

    function test_CloseRaffle_Revert_IfStarted() public {
        _createRaffle(creator, CODE1, 5, 1, 1 ether);
        _join(alice, CODE1);
        vm.prank(creator);
        pickr.startRaffle(CODE1);

        vm.prank(creator);
        vm.expectRevert(bytes("Raffle can only be closed before start"));
        pickr.closeRaffle(CODE1);
    }

    // receive()
    function test_Receive_Reverts() public {
        vm.expectRevert(bytes("use createRaffle/deposit with code"));
        (bool ok,) = address(pickr).call{value: 1 ether}("");
        ok; // silence unused var warning when not using expectRevert messages
    }
}
