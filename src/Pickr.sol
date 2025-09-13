// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Pickr {
    constructor() {
        owner = msg.sender;
    }

    modifier onlyCreator(string memory code) {
        require(_isRaffleExist(code), "Raffle does not exist");
        require(raffles[code].creator == msg.sender, "Not authorized");
        _;
    }

    enum RaffleStatus {
        ACTIVE,
        INACTIVE,
        STARTED
    }

    // models
    struct Raffle {
        address creator;
        uint256 balance;
        RaffleStatus status;
        uint256 maxParticipant;
        uint256 minParticipant;
        uint256 totalParticipant;
        uint64 createdAt;
    }

    address public owner;

    mapping(string => Raffle) public raffles;
    mapping(string => mapping(address => bool)) private hasJoined;
    mapping(string => address[]) private participants;
    mapping(string => address) public winners;
    mapping(address => string[]) private raffleCodesByCreator;

    // events
    event RaffleCreated(string indexed code, address indexed creator, uint256 initialDeposit);
    event RaffleStarted(string indexed code);
    event WinnerSelected(string indexed code, address indexed user, uint256 amount);
    event Deposited(string indexed code, address indexed creator, uint256 amount);
    event JoinRaffle(string indexed code, address indexed user);
    event LeaveRaffle(string indexed code, address indexed user);
    event Claimed(string indexed code, address indexed userClaim, uint256 claimAmount);
    event RaffleClosed(string indexed code);

    // main functions
    function createRaffle(uint256 maxParticipant, uint256 minParticipant, string calldata code)
        external
        payable
        returns (string memory)
    {
        require(msg.value > 0, "Initial deposit is required");
        require(maxParticipant > minParticipant, "Max participant must be greater than min participant");
        require(minParticipant > 0, "Min participant must be greater than 0");
        require(bytes(code).length > 0, "Code is required");
        require(!_isRaffleExist(code), "Code already used"); // added

        raffles[code] = Raffle(
            msg.sender, msg.value, RaffleStatus.ACTIVE, maxParticipant, minParticipant, 0, uint64(block.timestamp)
        );

        raffleCodesByCreator[msg.sender].push(code);

        emit RaffleCreated(code, msg.sender, msg.value);
        return code;
    }

    function deposit(string calldata code) external payable {
        require(_isRaffleExist(code), "Raffle does not exist");
        Raffle storage raffle = raffles[code];
        require(raffle.status == RaffleStatus.ACTIVE, "Raffle is already inactive or started");
        require(msg.value > 0, "Deposit must be greater than 0");

        raffle.balance += msg.value;

        emit Deposited(code, msg.sender, msg.value);
    }

    function startRaffle(string calldata code) external onlyCreator(code) {
        Raffle storage raffle = raffles[code];
        require(raffle.status == RaffleStatus.ACTIVE, "Raffle is already inactive or started");
        require(raffle.totalParticipant >= raffle.minParticipant, "Not enough participants");

        raffle.status = RaffleStatus.STARTED;

        emit RaffleStarted(code);
    }

    function winnerSelected(string calldata code, address winner) external onlyCreator(code) {
        Raffle storage raffle = raffles[code];
        require(raffle.status == RaffleStatus.STARTED, "Raffle is not started");
        require(winner != address(0), "Invalid winner");
        require(hasJoined[code][winner], "Winner not a participant");

        uint256 prize = raffle.balance;
        require(prize > 0, "No prize balance");

        winners[code] = winner;
        raffle.status = RaffleStatus.INACTIVE;
        raffle.balance = 0;

        (bool ok,) = payable(winner).call{value: prize}("");
        require(ok, "Winner payout failure");

        emit WinnerSelected(code, winner, prize);
    }

    function raffleParticipants(string calldata code) external view returns (address[] memory) {
        return participants[code];
    }

    function joinRaffle(string calldata code) external {
        require(_isRaffleExist(code), "Raffle does not exist");
        Raffle storage raffle = raffles[code];
        require(raffle.creator != msg.sender, "You can't join to your own raffle");
        require(raffle.status == RaffleStatus.ACTIVE, "Raffle is already inactive or started");
        require(raffle.totalParticipant < raffle.maxParticipant, "Raffle is full");

        bool joined = hasJoined[code][msg.sender];
        require(!joined, "You have already joined");

        hasJoined[code][msg.sender] = true;
        raffle.totalParticipant++;
        participants[code].push(msg.sender);

        emit JoinRaffle(code, msg.sender);
    }

    function leaveRaffle(string calldata code) external {
        require(_isRaffleExist(code), "Raffle does not exist");
        Raffle storage raffle = raffles[code];
        require(raffle.status == RaffleStatus.ACTIVE, "Raffle is already inactive or started");
        bool joined = hasJoined[code][msg.sender];
        require(joined, "You have not joined the raffle yet");

        raffle.totalParticipant--;
        hasJoined[code][msg.sender] = false;

        uint256 length = participants[code].length;
        for (uint256 i = 0; i < length; i++) {
            if (participants[code][i] == msg.sender) {
                participants[code][i] = participants[code][length - 1];
                participants[code].pop();
                break;
            }
        }

        emit LeaveRaffle(code, msg.sender);
    }

    function closeRaffle(string calldata code) external onlyCreator(code) {
        Raffle storage raffle = raffles[code];
        require(raffle.status == RaffleStatus.ACTIVE, "Raffle can only be closed before start");

        uint256 refund = raffle.balance;
        raffle.balance = 0;
        raffle.status = RaffleStatus.INACTIVE;

        if (refund > 0) {
            (bool ok,) = payable(raffle.creator).call{value: refund}("");
            require(ok, "Refund failure");
        }

        emit RaffleClosed(code);
    }

    function _isRaffleExist(string memory code) private view returns (bool) {
        return raffles[code].creator != address(0);
    }

    function getUserRaffleCodes(address creator) external view returns (string[] memory) {
        return raffleCodesByCreator[creator];
    }

    function getUserRaffles(address creator) external view returns (Raffle[] memory, string[] memory) {
        string[] memory codes = raffleCodesByCreator[creator];
        Raffle[] memory list = new Raffle[](codes.length);
        for (uint256 i = 0; i < codes.length; i++) {
            list[i] = raffles[codes[i]];
        }
        return (list, codes);
    }

    receive() external payable {
        revert("use createRaffle/deposit with code");
    }
}
