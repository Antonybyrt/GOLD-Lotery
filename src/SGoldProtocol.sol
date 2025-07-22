// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {VRFConsumerBaseV2Plus} from "chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {SGoldToken} from "./SGoldToken.sol";

contract SGoldProtocol is VRFConsumerBaseV2Plus {
    using VRFV2PlusClient for VRFV2PlusClient.RandomWordsRequest;

    // =============================================================
    //                          ERRORS
    // =============================================================

    error UnsupportedAssert();
    error NoEthSent();
    error InvalidPriceFeed();
    error NotEnoughParticipantsOrLotteryNotActive();
    error NotEnoughParticipants();
    error NoRandomWord();
    error TransferFailed();
    error NotEnoughSgold();
    error IncorrectAmount();

    // =============================================================
    //                          STATE VARIABLES
    // =============================================================

    AggregatorV3Interface internal goldPriceFeed;
    AggregatorV3Interface internal ethPriceFeed;
    SGoldToken public sgold;

    uint256 public constant MINT_PERCENT = 70;
    uint256 public constant LOTTERY_PERCENT = 10;
    uint256 public constant PERCENT_BASE = 100;

    uint256 public lotteryPot;
    mapping(address => uint256) public userDeposits;

    uint256 private immutable i_subscriptionId;
    address private constant vrfCoordinator = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B;
    bytes32 private constant keyHash = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;
    uint32 private constant callbackGasLimit = 40000;
    uint16 private constant requestConfirmations = 3;
    uint32 private constant numWords = 1;
    bool public nativePayment = true;

    // =============================================================
    //                      LOTTERY STATE
    // =============================================================
    
    uint256 public constant PARTICIPANT_THRESHOLD = 10;
    address[] public participants;
    address public admin;
    bool public lotteryActive = true;

    uint256 public lastRequestId;
    mapping(uint256 => bool) public requestFulfilled;
    mapping(uint256 => uint256) public requestRandomWord;

    // =============================================================
    //                          EVENTS
    // =============================================================

    event Mint(address indexed user, uint256 ethAmount, uint256 sgoldAmount);
    event DepositToLottery(address indexed user, uint256 amount);
    event LotteryTriggered(uint256 requestId);
    event LotteryWinner(address winner, uint256 amount);
    event Redeem(address indexed user, uint256 sgoldAmount, uint256 ethReturned);

    // =============================================================
    //                          Modifiers
    // =============================================================

    modifier canTriggerLottery() {
        if (participants.length < PARTICIPANT_THRESHOLD && !lotteryActive) revert NotEnoughParticipantsOrLotteryNotActive();
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(uint256 subscriptionId, address sgoldToken)
        VRFConsumerBaseV2Plus(vrfCoordinator)
    {
        i_subscriptionId = subscriptionId;
        goldPriceFeed = AggregatorV3Interface(0xC5981F461d74c46eB4b0CF3f4Ec79f025573B0Ea); // XAU-USD 
        ethPriceFeed = AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306); // ETH-USD
        sgold = SGoldToken(sgoldToken);
        admin = msg.sender;
    }

    // =============================================================
    //                          FUNCTIONS
    // =============================================================
    
    function getLatestPrice(string memory asset) public view returns (int256) {
        AggregatorV3Interface priceFeed;
        if (keccak256(bytes(asset)) == keccak256(bytes("gold"))) {
            priceFeed = goldPriceFeed;
        } else if (keccak256(bytes(asset)) == keccak256(bytes("eth"))) {
            priceFeed = ethPriceFeed;
        } else {
            revert UnsupportedAssert();
        }
        (
            ,
            int256 price,
            ,
            ,
        ) = priceFeed.latestRoundData();
        return price; // USD with 8 decimals
    }

    function mint() external payable {
        if (msg.value == 0) revert NoEthSent();
        int256 goldPrice = getLatestPrice("gold"); // 8 décimales
        int256 ethPrice = getLatestPrice("eth");   // 8 décimales

        if (goldPrice <= 0 || ethPrice <= 0) revert InvalidPriceFeed();

        uint256 ethUsdValue = (msg.value * uint256(ethPrice)) / 1e18;
        uint256 usdToMint = (ethUsdValue * MINT_PERCENT) / PERCENT_BASE;
        uint256 sgoldAmount = (usdToMint * 1e18) / uint256(goldPrice);

        sgold.mint(msg.sender, sgoldAmount);
        emit Mint(msg.sender, msg.value, sgoldAmount);

        uint256 lotteryShare = msg.value * LOTTERY_PERCENT / PERCENT_BASE;
        lotteryPot += lotteryShare;
        emit DepositToLottery(msg.sender, lotteryShare);

        userDeposits[msg.sender] += msg.value;

        if (lotteryActive) {
            participants.push(msg.sender);
        }
    }

    function getParticipants() external view returns (address[] memory) {
        return participants;
    }

    function triggerLottery() public virtual onlyAdmin canTriggerLottery() {
        VRFV2PlusClient.RandomWordsRequest memory req = VRFV2PlusClient.RandomWordsRequest({
            keyHash: keyHash,
            subId: i_subscriptionId,
            requestConfirmations: requestConfirmations,
            callbackGasLimit: callbackGasLimit,
            numWords: numWords,
            extraArgs: VRFV2PlusClient._argsToBytes(
                VRFV2PlusClient.ExtraArgsV1({nativePayment: nativePayment})
            )
        });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(req);
        lastRequestId = requestId;
        emit LotteryTriggered(requestId);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        if (randomWords.length <= 0) revert NoRandomWord();
        requestFulfilled[requestId] = true;
        requestRandomWord[requestId] = randomWords[0];
        resolveLottery(randomWords[0]);
    }

    function resolveLottery(uint256 random) public onlyAdmin {
        if (participants.length < PARTICIPANT_THRESHOLD) revert NotEnoughParticipants();

        uint256 winnerIndex = random % participants.length;
        address winner = participants[winnerIndex];
        uint256 prize = lotteryPot;
        lotteryPot = 0;
        lotteryActive = false;

        (bool sent, ) = winner.call{value: prize}("");
        
        if (!sent) revert TransferFailed();
        emit LotteryWinner(winner, prize);
        delete participants;
    }

    function redeem(uint256 sgoldAmount) external {
        if (sgoldAmount <= 0) revert IncorrectAmount();
        if (sgold.balanceOf(msg.sender) < sgoldAmount) revert NotEnoughSgold();

        int256 goldPrice = getLatestPrice("gold");
        int256 ethPrice = getLatestPrice("eth");
        if (goldPrice <= 0 || ethPrice <= 0) revert InvalidPriceFeed();

        uint256 usdValue = (sgoldAmount * uint256(goldPrice)) / 1e18;

        uint256 ethToReturn = (usdValue * 1e18) / uint256(ethPrice);

        sgold.burn(msg.sender, sgoldAmount);

        (bool sent, ) = msg.sender.call{value: ethToReturn}("");
        if (!sent) revert TransferFailed();
        emit Redeem(msg.sender, sgoldAmount, ethToReturn);
    }
}