// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {Gigipay} from "../src/Gigipay.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployGigipay is Script {
    function run() public returns (address) {
        address defaultAdmin = vm.envAddress("DEFAULT_ADMIN");
        address pauser = vm.envAddress("PAUSER");

        vm.startBroadcast();

        // Deploy implementation
        Gigipay implementation = new Gigipay();
        console.log("Gigipay Implementation deployed at:", address(implementation));

        // Encode initialize call
        bytes memory initData = abi.encodeWithSelector(
            Gigipay.initialize.selector,
            defaultAdmin,
            pauser
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        console.log("Gigipay Proxy deployed at:", address(proxy));

        vm.stopBroadcast();

        return address(proxy);
    }
}
