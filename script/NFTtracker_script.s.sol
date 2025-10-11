// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {SimpleNFTTracker} from "../src/NFTtracker.sol"; // Adjust path if necessary

contract SimpleNFTTrackerDeploy is Script {
    function run() public returns (SimpleNFTTracker) {
        vm.startBroadcast();

        SimpleNFTTracker nftTracker = new SimpleNFTTracker();
        console.log("SimpleNFTTracker deployed at:", address(nftTracker));

        vm.stopBroadcast();

        return nftTracker;
    }
}