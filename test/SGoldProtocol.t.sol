// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "../lib/forge-std/src/Test.sol";
import {SGoldToken} from "../src/SGoldToken.sol";
import {SGoldProtocol} from "../src/SGoldProtocol.sol";
import {MockV3Aggregator} from "lib/chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";
import {AggregatorV3Interface} from "../lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract RevertingReceiver {
    receive() external payable { revert(); }
}

contract SGoldProtocolTestable is SGoldProtocol {
    bool public mockTrigger = false;
    constructor(
        uint256 subscriptionId,
        address sgoldToken,
        address goldFeed,
        address ethFeed
    ) SGoldProtocol(subscriptionId, sgoldToken) {
        goldPriceFeed = AggregatorV3Interface(goldFeed);
        ethPriceFeed = AggregatorV3Interface(ethFeed);
    }
    function callFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) public {
        fulfillRandomWords(requestId, randomWords);
    }
    function triggerLottery() public override onlyAdmin canTriggerLottery {
        if (mockTrigger) {
            lastRequestId = 42;
            emit LotteryTriggered(42);
        } else {
            super.triggerLottery();
        }
    }
    function setMockTrigger(bool val) public {
        mockTrigger = val;
    }
}

contract SGoldProtocolTest is Test {
    SGoldProtocolTestable protocol;
    SGoldToken token;
    MockV3Aggregator goldFeed;
    MockV3Aggregator ethFeed;
    address user = address(0x2);
    address admin = address(this);
    uint256 constant INITIAL_GOLD_PRICE = 2000e8; // 2000 USD (8 décimales)
    uint256 constant INITIAL_ETH_PRICE = 2000e8;  // 2000 USD (8 décimales)
    uint256 constant SUB_ID = 1;

    function setUp() public {
        goldFeed = new MockV3Aggregator(8, int256(INITIAL_GOLD_PRICE));
        ethFeed = new MockV3Aggregator(8, int256(INITIAL_ETH_PRICE));
        token = new SGoldToken(address(this));
        protocol = new SGoldProtocolTestable(SUB_ID, address(token), address(goldFeed), address(ethFeed));
        token.updateMinter(address(protocol));
    }

    function testMintEmitsAndBalances() public {
        uint256 ethAmount = 1 ether;
        vm.deal(user, ethAmount);
        vm.prank(user);
        protocol.mint{value: ethAmount}();

        uint256 sgoldBalance = token.balanceOf(user);
        assertGt(sgoldBalance, 0);

        assertGt(protocol.lotteryPot(), 0);

        address[] memory participants = protocol.getParticipants();
        assertEq(participants[0], user);
    }

    function testMintRevertsIfNoEth() public {
        vm.expectRevert(SGoldProtocol.NoEthSent.selector);
        protocol.mint{value: 0}();
    }

    function testRedeemSGold() public {
        uint256 ethAmount = 1 ether;
        vm.deal(user, ethAmount);
        vm.prank(user);
        protocol.mint{value: ethAmount}();
        uint256 sgoldAmount = token.balanceOf(user);

        vm.deal(address(protocol), 10 ether);
        vm.prank(user);
        protocol.redeem(sgoldAmount);

        assertGt(user.balance, 0);

        assertEq(token.balanceOf(user), 0);
    }

    function testRedeemRevertsIfNotEnoughSGold() public {
        vm.expectRevert(SGoldProtocol.NotEnoughSgold.selector);
        protocol.redeem(1 ether);
    }

    function testGetLatestPriceGoldAndEth() public {
        int256 gold = protocol.getLatestPrice("gold");
        int256 eth = protocol.getLatestPrice("eth");
        assertEq(gold, int256(INITIAL_GOLD_PRICE));
        assertEq(eth, int256(INITIAL_ETH_PRICE));
    }

    function testGetLatestPriceRevertsOnUnknownAsset() public {
        vm.expectRevert(SGoldProtocol.UnsupportedAssert.selector);
        protocol.getLatestPrice("banana");
    }

    function testMintRevertsIfInvalidPriceFeed() public {
        goldFeed.updateAnswer(0);
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(SGoldProtocol.InvalidPriceFeed.selector);
        protocol.mint{value: 1 ether}();
    }

    function testRedeemRevertsIfInvalidPriceFeed() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        protocol.mint{value: 1 ether}();
        uint256 sgoldAmount = token.balanceOf(user);
        goldFeed.updateAnswer(0);
        vm.deal(address(protocol), 10 ether);
        vm.prank(user);
        vm.expectRevert(SGoldProtocol.InvalidPriceFeed.selector);
        protocol.redeem(sgoldAmount);
    }

    function testRedeemRevertsIfAmountZero() public {
        vm.expectRevert(SGoldProtocol.IncorrectAmount.selector);
        protocol.redeem(0);
    }

    function testTriggerLotteryRevertsIfNotAdmin() public {
        address notAdmin = address(0x123);
        vm.prank(notAdmin);
        vm.expectRevert("Not admin");
        protocol.triggerLottery();
    }

    function testTriggerLotteryRevertsIfNotEnoughParticipants() public {
        vm.expectRevert();
        protocol.triggerLottery();
    }

    function testTriggerLotteryWorksWithEnoughParticipants() public {

        for (uint256 i = 0; i < 10; i++) {
            address p = address(uint160(0x100 + i));
            vm.deal(p, 1 ether);
            vm.prank(p);
            protocol.mint{value: 1 ether}();
        }

        protocol.setMockTrigger(true);
        protocol.triggerLottery();

        assertEq(protocol.lastRequestId(), 42);
    }

    function testResolveLotteryRevertsIfNotEnoughParticipants() public {
        vm.expectRevert(SGoldProtocol.NotEnoughParticipants.selector);
        protocol.resolveLottery(42);
    }

    function testResolveLotteryDistributesPrizeAndResets() public {

        for (uint256 i = 0; i < 10; i++) {
            address p = address(uint160(0x200 + i));
            vm.deal(p, 1 ether);
            vm.prank(p);
            protocol.mint{value: 1 ether}();
        }

        uint256 pot = protocol.lotteryPot();

        address winner = protocol.getParticipants()[3];
        uint256 winnerBalanceBefore = winner.balance;

        vm.prank(admin);
        protocol.resolveLottery(3); 

        assertEq(protocol.lotteryPot(), 0);

        assertEq(protocol.getParticipants().length, 0);

        assertEq(winner.balance, winnerBalanceBefore + pot);
 
        assertEq(protocol.lotteryActive(), false);
    }

    function testFulfillRandomWordsRevertsIfNoRandomWord() public {
        uint256 reqId = 1;
        uint256[] memory emptyWords = new uint256[](0);
        vm.expectRevert(SGoldProtocol.NoRandomWord.selector);
        protocol.callFulfillRandomWords(reqId, emptyWords);
    }

    function testOnlyAdminModifier() public {
        address notAdmin = address(0x123);

        vm.prank(notAdmin);
        vm.expectRevert("Not admin");
        protocol.triggerLottery();

        vm.prank(notAdmin);
        vm.expectRevert("Not admin");
        protocol.resolveLottery(1);
    }

    function testCanTriggerLotteryModifier() public {

        protocol = new SGoldProtocolTestable(SUB_ID, address(token), address(goldFeed), address(ethFeed));

        vm.store(address(protocol), bytes32(uint256(8)), bytes32(uint256(0)));
        vm.expectRevert();
        protocol.triggerLottery();
    }

    function testGetParticipantsReturnsCorrectList() public {
        address p1 = address(0x111);
        address p2 = address(0x222);
        vm.deal(p1, 1 ether);
        vm.deal(p2, 1 ether);
        vm.prank(p1);
        protocol.mint{value: 1 ether}();
        vm.prank(p2);
        protocol.mint{value: 1 ether}();
        address[] memory parts = protocol.getParticipants();
        assertEq(parts.length, 2);
        assertEq(parts[0], p1);
        assertEq(parts[1], p2);
    }

    function testMintRevertsIfGoldPriceNegative() public {
        goldFeed.updateAnswer(-1);
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(SGoldProtocol.InvalidPriceFeed.selector);
        protocol.mint{value: 1 ether}();
    }

    function testMintRevertsIfEthPriceNegative() public {
        ethFeed.updateAnswer(-1);
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(SGoldProtocol.InvalidPriceFeed.selector);
        protocol.mint{value: 1 ether}();
    }

    function testResolveLotteryRevertsIfTransferFails() public {

        for (uint256 i = 0; i < 9; i++) {
            address p = address(uint160(0x300 + i));
            vm.deal(p, 1 ether);
            vm.prank(p);
            protocol.mint{value: 1 ether}();
        }

        RevertingReceiver badWinner = new RevertingReceiver();
        vm.deal(address(badWinner), 1 ether);
        vm.prank(address(badWinner));
        protocol.mint{value: 1 ether}();

        vm.prank(admin);
        vm.expectRevert(SGoldProtocol.TransferFailed.selector);
        protocol.resolveLottery(9);
    }

    function testFulfillRandomWordsSuccess() public {

        for (uint256 i = 0; i < 10; i++) {
            address p = address(uint160(0x400 + i));
            vm.deal(p, 1 ether);
            vm.prank(p);
            protocol.mint{value: 1 ether}();
        }

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 3;
        protocol.setMockTrigger(true);
        protocol.triggerLottery();
        protocol.callFulfillRandomWords(protocol.lastRequestId(), randomWords);

        assertEq(protocol.lotteryActive(), false);
        assertEq(protocol.getParticipants().length, 0);
    }
}

contract SGoldTokenTest is Test {
    SGoldToken token;
    address minter = address(0x1);
    address owner = address(this);
    address user = address(0x2);

    function setUp() public {
        token = new SGoldToken(minter);
    }

    function testOnlyMinterModifierAllowsMinter() public {
        vm.prank(minter);
        token.mint(user, 1 ether);
        assertEq(token.balanceOf(user), 1 ether);
    }

    function testOnlyMinterModifierRejectsNonMinter() public {
        vm.expectRevert("Not authorized");
        token.mint(user, 1 ether);
    }

    function testOnlyOwnerOrMinterIfNotTransferredAllowsOwnerBeforeTransfer() public {
        token.updateMinter(address(0x5));
        assertEq(token.minter(), address(0x5));
    }

    function testOnlyOwnerOrMinterIfNotTransferredAllowsMinterBeforeTransfer() public {
        vm.prank(minter);
        token.mint(minter, 1 ether);
        assertEq(token.balanceOf(minter), 1 ether);
    }

    function testOnlyOwnerOrMinterIfNotTransferredRejectsNonOwnerOrMinterBeforeTransfer() public {
        vm.prank(user);
        vm.expectRevert("Not authorized");
        token.updateMinter(address(0x3));
    }

    function testOnlyOwnerOrMinterIfNotTransferredAllowsOnlyMinterAfterTransfer() public {
        token.updateMinter(user);
        vm.prank(user);
        token.updateMinter(address(0x4));
        assertEq(token.minter(), address(0x4));
    }

    function testOnlyOwnerOrMinterIfNotTransferredRejectsOwnerAfterTransfer() public {
        token.updateMinter(user);
        vm.expectRevert("Not authorized");
        token.updateMinter(address(0x5));
    }

    function testOnlyOwnerOrMinterIfNotTransferredRejectsNonMinterAfterTransfer() public {
        token.updateMinter(user);
        vm.prank(address(0x123));
        vm.expectRevert("Not authorized");
        token.updateMinter(address(0x456));
    }
}
