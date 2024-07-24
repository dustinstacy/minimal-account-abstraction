// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {MinimalAccount} from "src/ethereum/MinimalAccount.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

/// @title DeployMinimalAccount
/// @author Dustin Stacy
/// @notice This script deploys a minimal account contract.
contract DeployMinimalAccount is Script {
    function run() public {
        deployMinimalAccount();
    }

    function deployMinimalAccount() public returns (HelperConfig helperConfig, MinimalAccount minimalAccount) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.account);
        minimalAccount = new MinimalAccount(config.entryPoint);
        minimalAccount.transferOwnership(config.account);
        vm.stopBroadcast();

        return (helperConfig, minimalAccount);
    }
}
