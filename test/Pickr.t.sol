// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Pickr.sol";

contract PickrTest is Test {
    Pickr internal pickr;

    address internal creator;
    address internal alice;
    address internal bob;
    address internal carol;
    address internal dave;

    bytes32 internal constant ROOM1 = keccak256("ROOM1");
    bytes32 internal constant ROOM2 = keccak256("ROOM2");

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
    function _createRoom(address _creator, bytes32 roomId, uint256 minP, uint256 maxP, uint256 value) internal {
        vm.prank(_creator);
        pickr.createRoom{value: value}(roomId, IPickr.RoomAccessMode.PUBLIC, minP, maxP);
    }

    function _join(address user, bytes32 roomId) internal {
        vm.prank(user);
        pickr.joinRoom(roomId);
    }

    // createRoom
    function test_CreateRoom_Success() public {
        _createRoom(creator, ROOM1, 2, 5, 1 ether);

        (
            address c,
            uint256 balance,
            IPickr.RoomStatus status,
            IPickr.RoomAccessMode accessMode,
            uint256 maxP,
            uint256 minP,
            uint256 totalP,
            uint64 createdAt
        ) = pickr.rooms(ROOM1);

        assertEq(c, creator, "creator mismatch");
        assertEq(balance, 1 ether, "balance mismatch");
        assertEq(uint8(status), uint8(IPickr.RoomStatus.ACTIVE), "status");
        assertEq(uint8(accessMode), uint8(IPickr.RoomAccessMode.PUBLIC), "access mode");
        assertEq(maxP, 5, "maxP");
        assertEq(minP, 2, "minP");
        assertEq(totalP, 0, "totalP");
        assertGt(uint256(createdAt), 0, "createdAt");

        bytes32[] memory codes = pickr.getUserRoomCodes(creator);
        assertEq(codes.length, 1);
        assertEq(codes[0], ROOM1);

        (IPickr.Room[] memory rooms, bytes32[] memory codes2) = pickr.getUserRooms(creator);
        assertEq(rooms.length, 1);
        assertEq(codes2.length, 1);
        assertEq(rooms[0].creator, creator);
        assertEq(rooms[0].balance, 1 ether);
    }

    function test_CreateRoom_Revert_NoDeposit() public {
        vm.prank(creator);
        vm.expectRevert(IPickr.ErrorDepositRequired.selector);
        pickr.createRoom(ROOM1, IPickr.RoomAccessMode.PUBLIC, 2, 5);
    }

    function test_CreateRoom_Revert_MaxLTMin() public {
        vm.prank(creator);
        vm.expectRevert(IPickr.ErrorMaxParticipantLessThanMin.selector);
        pickr.createRoom{value: 1 ether}(ROOM1, IPickr.RoomAccessMode.PUBLIC, 3, 2); // max < min
    }

    function test_CreateRoom_Revert_MinZero() public {
        vm.prank(creator);
        vm.expectRevert(IPickr.ErrorMinParticipantMustBeGreaterThanZero.selector);
        pickr.createRoom{value: 1 ether}(ROOM1, IPickr.RoomAccessMode.PUBLIC, 0, 2);
    }

    function test_CreateRoom_Revert_EmptyCode() public {
        vm.prank(creator);
        vm.expectRevert(IPickr.ErrorCodeIsRequired.selector);
        pickr.createRoom{value: 1 ether}(bytes32(0), IPickr.RoomAccessMode.PUBLIC, 2, 5);
    }

    function test_CreateRoom_Revert_DuplicateCode() public {
        _createRoom(creator, ROOM1, 2, 5, 1 ether);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IPickr.ErrorCodeAlreadyUsed.selector, ROOM1));
        pickr.createRoom{value: 1 ether}(ROOM1, IPickr.RoomAccessMode.PUBLIC, 2, 6);
    }

    // deposit
    function test_Deposit_Success_IncreasesBalance() public {
        _createRoom(creator, ROOM1, 2, 5, 1 ether);

        vm.prank(creator); // Only creator can deposit
        pickr.deposit{value: 0.5 ether}(ROOM1);

        (, uint256 balance,,,,,,) = pickr.rooms(ROOM1);
        assertEq(balance, 1.5 ether, "deposit didn't add");
    }

    function test_Deposit_Revert_NonexistentCode() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IPickr.ErrorRoomIsNotExist.selector, ROOM1));
        pickr.deposit{value: 1 ether}(ROOM1);
    }

    function test_Deposit_Revert_ZeroValue() public {
        _createRoom(creator, ROOM1, 2, 5, 1 ether);
        vm.prank(creator);
        vm.expectRevert(IPickr.ErrorDepositRequired.selector);
        pickr.deposit(ROOM1);
    }

    function test_Deposit_Revert_WhenStarted() public {
        _createRoom(creator, ROOM1, 2, 5, 1 ether);
        _join(alice, ROOM1);
        _join(bob, ROOM1);
        _join(carol, ROOM1); // Need more than minParticipant (2) to start
        vm.prank(creator);
        pickr.startRoom(ROOM1);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IPickr.ErrorRoomIsNotActive.selector, ROOM1));
        pickr.deposit{value: 1 ether}(ROOM1);
    }

    function test_Deposit_Revert_NotCreator() public {
        _createRoom(creator, ROOM1, 2, 5, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPickr.ErrorNotAuthorized.selector, alice));
        pickr.deposit{value: 1 ether}(ROOM1);
    }

    // join / leave
    function test_JoinRoom_Success() public {
        _createRoom(creator, ROOM1, 1, 3, 1 ether);
        _join(alice, ROOM1);
        _join(bob, ROOM1);

        (,,,,,, uint256 totalP,) = pickr.rooms(ROOM1);
        assertEq(totalP, 2);

        address[] memory parts = pickr.roomParticipants(ROOM1);
        assertEq(parts.length, 2);
        // order is not guaranteed after leaves, but here it's sequential joins
        assertEq(parts[0], alice);
        assertEq(parts[1], bob);
    }

    function test_JoinRoom_Revert_OwnerCannotJoinOwnRoom() public {
        _createRoom(creator, ROOM1, 1, 3, 1 ether);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IPickr.ErrorUserIsTheRoomOwner.selector, ROOM1));
        pickr.joinRoom(ROOM1);
    }

    function test_JoinRoom_Revert_DuplicateJoin() public {
        _createRoom(creator, ROOM1, 1, 3, 1 ether);
        _join(alice, ROOM1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPickr.ErrorUserAlreadyJoinRoom.selector, ROOM1));
        pickr.joinRoom(ROOM1);
    }

    function test_JoinRoom_Revert_Full() public {
        _createRoom(creator, ROOM1, 1, 2, 1 ether);
        _join(alice, ROOM1);
        _join(bob, ROOM1);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(IPickr.ErrorRoomIsFull.selector, ROOM1));
        pickr.joinRoom(ROOM1);
    }

    function test_LeaveRoom_Success_RemovesParticipant() public {
        _createRoom(creator, ROOM1, 1, 3, 1 ether);
        _join(alice, ROOM1);
        _join(bob, ROOM1);
        _join(carol, ROOM1);

        vm.prank(bob);
        pickr.leaveRoom(ROOM1);

        (,,,,,, uint256 totalP,) = pickr.rooms(ROOM1);
        assertEq(totalP, 2);

        address[] memory parts = pickr.roomParticipants(ROOM1);
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

    function test_LeaveRoom_Revert_NotJoined() public {
        _createRoom(creator, ROOM1, 1, 3, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPickr.ErrorUserIsNotParticipant.selector, ROOM1));
        pickr.leaveRoom(ROOM1);
    }

    // startRoom
    function test_StartRoom_Success() public {
        _createRoom(creator, ROOM1, 2, 5, 1 ether);
        _join(alice, ROOM1);
        _join(bob, ROOM1);
        _join(carol, ROOM1); // Need more than minParticipant (2)
        vm.prank(creator);
        pickr.startRoom(ROOM1);

        (,, IPickr.RoomStatus status,,,,,) = pickr.rooms(ROOM1);
        assertEq(uint8(status), uint8(IPickr.RoomStatus.STARTED));
    }

    function test_StartRoom_Revert_NotEnoughParticipants() public {
        _createRoom(creator, ROOM1, 2, 5, 1 ether);
        _join(alice, ROOM1);
        _join(bob, ROOM1); // Only equals minParticipant (2), need more
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IPickr.ErrorNotEnoughParticipant.selector, ROOM1));
        pickr.startRoom(ROOM1);
    }

    function test_StartRoom_Revert_OnlyCreator() public {
        _createRoom(creator, ROOM1, 1, 5, 1 ether);
        _join(alice, ROOM1);
        _join(bob, ROOM1); // More than minParticipant (1)
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPickr.ErrorNotAuthorized.selector, alice));
        pickr.startRoom(ROOM1);
    }

    // winnerSelected
    function test_WinnerSelected_Success_TransfersPrizeAndCloses() public {
        _createRoom(creator, ROOM1, 2, 5, 2 ether);
        // extra deposit to have a clear prize
        vm.prank(creator); // Only creator can deposit
        pickr.deposit{value: 1 ether}(ROOM1);

        _join(alice, ROOM1);
        _join(bob, ROOM1);
        _join(carol, ROOM1); // Need more than minParticipant (2)

        vm.prank(creator);
        pickr.startRoom(ROOM1);

        uint256 prizeBefore;
        (, prizeBefore,,,,,,) = pickr.rooms(ROOM1);
        assertEq(prizeBefore, 3 ether);

        uint256 bobBalBefore = bob.balance;

        vm.prank(creator);
        pickr.winnerSelected(ROOM1, bob);

        // state changes
        (,, IPickr.RoomStatus statusAfter,,,,,) = pickr.rooms(ROOM1);
        assertEq(uint8(statusAfter), uint8(IPickr.RoomStatus.INACTIVE));
        (, uint256 balanceAfter,,,,,,) = pickr.rooms(ROOM1);
        assertEq(balanceAfter, 0);
        assertEq(pickr.winners(ROOM1), bob);

        // payout
        assertEq(bob.balance, bobBalBefore + prizeBefore);
    }

    function test_WinnerSelected_Revert_NotStarted() public {
        _createRoom(creator, ROOM1, 1, 5, 1 ether);
        _join(alice, ROOM1);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IPickr.ErrorRoomIsNotStarted.selector, ROOM1));
        pickr.winnerSelected(ROOM1, alice);
    }

    function test_WinnerSelected_Revert_InvalidWinner() public {
        _createRoom(creator, ROOM1, 1, 5, 1 ether);
        _join(alice, ROOM1);
        _join(bob, ROOM1); // More than minParticipant (1)
        vm.prank(creator);
        pickr.startRoom(ROOM1);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IPickr.ErrorInvalidWinner.selector, ROOM1));
        pickr.winnerSelected(ROOM1, address(0));
    }

    function test_WinnerSelected_Revert_NotParticipant() public {
        _createRoom(creator, ROOM1, 1, 5, 1 ether);
        _join(alice, ROOM1);
        _join(bob, ROOM1); // More than minParticipant (1)
        vm.prank(creator);
        pickr.startRoom(ROOM1);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IPickr.ErrorAddressIsNotParticipant.selector, ROOM1, carol));
        pickr.winnerSelected(ROOM1, carol);
    }

    // closeRoom
    function test_CloseRoom_Success_RefundsCreator() public {
        _createRoom(creator, ROOM1, 1, 5, 2 ether);
        // add extra deposit from creator only (only creator can deposit)
        vm.prank(creator);
        pickr.deposit{value: 1.5 ether}(ROOM1);

        (, uint256 balanceBefore,,,,,,) = pickr.rooms(ROOM1);
        assertEq(balanceBefore, 3.5 ether);

        uint256 creatorBefore = creator.balance;
        vm.prank(creator);
        pickr.closeRoom(ROOM1);

        // status & balance
        (,, IPickr.RoomStatus statusAfter,,,,,) = pickr.rooms(ROOM1);
        assertEq(uint8(statusAfter), uint8(IPickr.RoomStatus.INACTIVE));
        (, uint256 balanceAfter,,,,,,) = pickr.rooms(ROOM1);
        assertEq(balanceAfter, 0);

        // refund
        assertEq(creator.balance, creatorBefore + balanceBefore);
    }

    function test_CloseRoom_Revert_IfStarted() public {
        _createRoom(creator, ROOM1, 1, 5, 1 ether);
        _join(alice, ROOM1);
        _join(bob, ROOM1); // More than minParticipant (1)
        vm.prank(creator);
        pickr.startRoom(ROOM1);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IPickr.ErrorRoomIsNotActive.selector, ROOM1));
        pickr.closeRoom(ROOM1);
    }

    // receive()
    function test_Receive_Reverts() public {
        vm.expectRevert(bytes("use createRoom/deposit with code"));
        (bool ok,) = address(pickr).call{value: 1 ether}("");
        ok; // silence unused var warning when not using expectRevert messages
    }
}
