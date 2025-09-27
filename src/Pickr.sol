// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IPickr.sol";

contract Pickr is IPickr {
    constructor() {
        owner = msg.sender;
    }

    modifier onlyCreator(bytes32 docIdHash) {
        if (!_isRoomExist(docIdHash)) {
            revert ErrorRoomIsNotExist(docIdHash);
        }
        if (msg.sender != rooms[docIdHash].creator) {
            revert ErrorNotAuthorized(msg.sender);
        }
        _;
    }

    address public immutable owner;

    mapping(bytes32 docIdHash => Room) public rooms;
    mapping(bytes32 docIdHash => mapping(address => bool)) private hasJoined;
    mapping(bytes32 docIdHash => address[]) private participants;
    mapping(bytes32 docIdHash => address) public winners;
    mapping(address user => bytes32[]) private roomCodesByCreator;

    // main functions
    function createRoom(bytes32 docIdHash, RoomAccessMode accessMode, uint256 minParticipant, uint256 maxParticipant)
        external
        payable
    {
        if (msg.value == 0) revert ErrorDepositRequired();

        if (maxParticipant < minParticipant) {
            revert ErrorMaxParticipantLessThanMin();
        }
        if (minParticipant == 0) {
            revert ErrorMinParticipantMustBeGreaterThanZero();
        }
        if (docIdHash == bytes32(0)) revert ErrorCodeIsRequired();
        if (_isRoomExist(docIdHash)) {
            revert ErrorCodeAlreadyUsed(docIdHash);
        }

        rooms[docIdHash] = Room(
            msg.sender,
            msg.value,
            RoomStatus.ACTIVE,
            accessMode,
            maxParticipant,
            minParticipant,
            0,
            uint64(block.timestamp)
        );

        roomCodesByCreator[msg.sender].push(docIdHash);
    }

    function deposit(bytes32 docIdHash) external payable onlyCreator(docIdHash) {
        if (!_isRoomExist(docIdHash)) revert ErrorRoomIsNotExist(docIdHash);

        Room storage room = rooms[docIdHash];
        if (room.status != RoomStatus.ACTIVE) {
            revert ErrorRoomIsNotActive(docIdHash);
        }

        if (msg.value == 0) revert ErrorDepositRequired();

        room.balance += msg.value;
    }

    function startRoom(bytes32 docIdHash) external onlyCreator(docIdHash) {
        Room storage room = rooms[docIdHash];
        if (room.status != RoomStatus.ACTIVE) {
            revert ErrorRoomIsNotActive(docIdHash);
        }

        if (room.totalParticipant <= room.minParticipant) {
            revert ErrorNotEnoughParticipant(docIdHash);
        }

        room.status = RoomStatus.STARTED;
    }

    function winnerSelected(bytes32 docIdHash, address winner) external onlyCreator(docIdHash) {
        Room storage room = rooms[docIdHash];
        if (room.status != RoomStatus.STARTED) {
            revert ErrorRoomIsNotStarted(docIdHash);
        }
        if (winner == address(0)) revert ErrorInvalidWinner(docIdHash);
        if (!hasJoined[docIdHash][winner]) {
            revert ErrorAddressIsNotParticipant(docIdHash, winner);
        }

        uint256 prize = room.balance;
        require(prize > 0, "No prize balance");

        winners[docIdHash] = winner;
        room.status = RoomStatus.INACTIVE;
        room.balance = 0;

        (bool ok,) = payable(winner).call{value: prize}("");
        require(ok, "Winner payout failure");
    }

    function roomParticipants(bytes32 docIdHash) external view returns (address[] memory) {
        return participants[docIdHash];
    }

    function joinRoom(bytes32 docIdHash) external {
        if (!_isRoomExist(docIdHash)) revert ErrorRoomIsNotExist(docIdHash);

        Room storage room = rooms[docIdHash];
        if (msg.sender == room.creator) {
            revert ErrorUserIsTheRoomOwner(docIdHash);
        }

        if (room.status != RoomStatus.ACTIVE) {
            revert ErrorRoomIsNotActive(docIdHash);
        }

        if (room.totalParticipant >= room.maxParticipant) {
            revert ErrorRoomIsFull(docIdHash);
        }

        bool joined = hasJoined[docIdHash][msg.sender];
        if (joined) revert ErrorUserAlreadyJoinRoom(docIdHash);

        hasJoined[docIdHash][msg.sender] = true;
        room.totalParticipant++;
        participants[docIdHash].push(msg.sender);
    }

    function leaveRoom(bytes32 docIdHash) external {
        if (!_isRoomExist(docIdHash)) {
            revert ErrorRoomIsNotExist(docIdHash);
        }

        Room storage room = rooms[docIdHash];
        if (room.status != RoomStatus.ACTIVE) {
            revert ErrorRoomIsNotActive(docIdHash);
        }

        bool joined = hasJoined[docIdHash][msg.sender];
        if (!joined) revert ErrorUserIsNotParticipant(docIdHash);

        room.totalParticipant--;
        hasJoined[docIdHash][msg.sender] = false;

        uint256 length = participants[docIdHash].length;
        for (uint256 i = 0; i < length; i++) {
            if (participants[docIdHash][i] == msg.sender) {
                participants[docIdHash][i] = participants[docIdHash][length - 1];
                participants[docIdHash].pop();
                break;
            }
        }
    }

    function closeRoom(bytes32 docIdHash) external onlyCreator(docIdHash) {
        Room storage room = rooms[docIdHash];
        if (room.status != RoomStatus.ACTIVE) {
            revert ErrorRoomIsNotActive(docIdHash);
        }

        uint256 refund = room.balance;
        room.balance = 0;
        room.status = RoomStatus.INACTIVE;

        if (refund > 0) {
            (bool ok,) = payable(room.creator).call{value: refund}("");
            require(ok, "Refund failure");
        }
    }

    function _isRoomExist(bytes32 docIdHash) private view returns (bool) {
        return rooms[docIdHash].creator != address(0);
    }

    function getUserRoomCodes(address creator) external view returns (bytes32[] memory) {
        return roomCodesByCreator[creator];
    }

    function getUserRooms(address creator) external view returns (Room[] memory, bytes32[] memory) {
        bytes32[] memory codes = roomCodesByCreator[creator];
        Room[] memory list = new Room[](codes.length);
        for (uint256 i = 0; i < codes.length; i++) {
            list[i] = rooms[codes[i]];
        }
        return (list, codes);
    }

    receive() external payable {
        revert("use createRoom/deposit with code");
    }
}
