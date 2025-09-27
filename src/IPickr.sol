// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPickr {
    enum RoomStatus {
        ACTIVE,
        INACTIVE,
        STARTED
    }

    enum RoomAccessMode {
        PUBLIC,
        PRIVATE
    }

    // models
    struct Room {
        address creator;
        uint256 balance;
        RoomStatus status;
        RoomAccessMode accessMode;
        uint256 maxParticipant;
        uint256 minParticipant;
        uint256 totalParticipant;
        uint64 createdAt;
    }

    // errors
    error ErrorNotAuthorized(address caller);
    error ErrorRoomIsNotExist(bytes32 docIdHash);
    error ErrorCodeIsRequired();
    error ErrorRoomIsNotActive(bytes32 docIdHash);
    error ErrorRoomIsNotStarted(bytes32 docIdHash);

    // create room errors
    error ErrorDepositRequired();
    error ErrorMaxParticipantLessThanMin();
    error ErrorMinParticipantMustBeGreaterThanZero();
    error ErrorCodeAlreadyUsed(bytes32 docIdHash);

    // start room errors
    error ErrorNotEnoughParticipant(bytes32 docIdHash);

    // winner selected errors
    error ErrorInvalidWinner(bytes32 docIdHash);
    error ErrorAddressIsNotParticipant(bytes32 docIdHash, address addr);
    error ErrorNoBalance(bytes32 docIdHash);

    // join room errors
    error ErrorUserIsTheRoomOwner(bytes32 docIdHash);
    error ErrorRoomIsFull(bytes32 docIdHash);
    error ErrorUserAlreadyJoinRoom(bytes32 docIdHash);

    // leave room errors
    error ErrorUserIsNotParticipant(bytes32 docIdHash);
}
