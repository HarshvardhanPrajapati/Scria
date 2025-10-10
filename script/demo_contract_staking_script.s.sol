// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/demo_contract_staking.sol"; // Adjust path if needed, based on typical Foundry structure

contract DeployDecentralizedMarketplace is Script {
    function run() external returns (DecentralizedMarketplace) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the DecentralizedMarketplace contract with a platform fee (e.g., 2.5% or 250 basis points)
        // The constructor expects a uint256 for _platformFee.
        // For 2.5%, we pass 250 (since it's typically in basis points, i.e., 10000 = 100%)
        DecentralizedMarketplace marketplace = new DecentralizedMarketplace(250);

        vm.stopBroadcast();

        return marketplace;
    }
}