// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {SGoldToken} from "src/SGoldToken.sol";
import {SGoldProtocol} from "src/SGoldProtocol.sol";
import {IVRFSubscriptionV2Plus} from "../lib/chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";

contract SGoldProtocolScript is Script {
    IVRFSubscriptionV2Plus vrfCoordinator = IVRFSubscriptionV2Plus(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B);
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        uint256 subId = vrfCoordinator.createSubscription();
        console.log("Subscription created with ID:", subId);
        vrfCoordinator.fundSubscriptionWithNative{value: 0.05 ether}(subId);

        SGoldToken token = new SGoldToken(msg.sender);
        SGoldProtocol protocol = new SGoldProtocol(subId, address(token));

        vrfCoordinator.addConsumer(subId, address(protocol));

        token.updateMinter(address(protocol));

        console2.log("SGoldToken deployed at:", address(token));
        console2.log("SGoldProtocol deployed at:", address(protocol));

        vm.stopBroadcast();
    }
}
