// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Pickr} from "../src/Pickr.sol";

contract DeployPickrScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        new Pickr();
        vm.stopBroadcast();
    }
}
