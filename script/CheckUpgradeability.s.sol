// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";

contract CheckUpgradeability is Script {
    address constant PROXY = 0x88D7034cc9409f78F6B00D34FeA5B0941FbeC69b;
    
    function run() external view {
        console.log("=== Checking Upgradeability ===");
        console.log("Proxy Address:", PROXY);
        
        // Check if contract exists
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(PROXY)
        }
        console.log("Code Size:", codeSize);
        
        if (codeSize == 0) {
            console.log("ERROR: Contract not found!");
            return;
        }
        
        // Try to get implementation address (ERC1967 slot)
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 implSlot = vm.load(PROXY, IMPLEMENTATION_SLOT);
        address implementation = address(uint160(uint256(implSlot)));
        console.log("Implementation:", implementation);
        
        // Try to get admin address (ERC1967 admin slot)
        bytes32 ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        bytes32 adminSlot = vm.load(PROXY, ADMIN_SLOT);
        address admin = address(uint160(uint256(adminSlot)));
        console.log("Admin (if Transparent Proxy):", admin);
        
        // Check for UUPS UUID
        try this.checkUUPS(PROXY) returns (bytes32 uuid) {
            console.log("UUPS UUID found:");
            console.logBytes32(uuid);
            console.log("=> This is a UUPS Proxy!");
        } catch {
            console.log("No UUPS UUID found");
            if (admin != address(0)) {
                console.log("=> This is a Transparent Proxy with ProxyAdmin");
            } else {
                console.log("=> Proxy type unclear");
            }
        }
        
        // Check for upgradeToAndCall function
        try this.checkUpgradeFunction(PROXY) {
            console.log("upgradeToAndCall function: EXISTS");
        } catch {
            console.log("upgradeToAndCall function: NOT FOUND");
        }
        
        // Check for DEFAULT_ADMIN_ROLE
        try this.checkAdminRole(PROXY) returns (address roleAdmin) {
            console.log("DEFAULT_ADMIN_ROLE holder:", roleAdmin);
        } catch {
            console.log("Could not check admin role");
        }
    }
    
    function checkUUPS(address proxy) external view returns (bytes32) {
        (bool success, bytes memory data) = proxy.staticcall(
            abi.encodeWithSignature("proxiableUUID()")
        );
        require(success, "No UUPS");
        return abi.decode(data, (bytes32));
    }
    
    function checkUpgradeFunction(address proxy) external view {
        (bool success, ) = proxy.staticcall(
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(0), "")
        );
        // Will revert with authorization error if function exists
        // Will revert with "function not found" if it doesn't
        require(success, "Function check");
    }
    
    function checkAdminRole(address proxy) external view returns (address) {
        bytes32 DEFAULT_ADMIN_ROLE = 0x00;
        (bool success, bytes memory data) = proxy.staticcall(
            abi.encodeWithSignature("getRoleMember(bytes32,uint256)", DEFAULT_ADMIN_ROLE, 0)
        );
        require(success, "No role");
        return abi.decode(data, (address));
    }
}
