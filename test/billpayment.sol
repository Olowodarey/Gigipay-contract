// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Gigipay} from "../src/Gigipay.sol";
import {IGigipayEvents} from "../src/interfaces/IGigipayEvents.sol";
import {IGigipayErrors} from "../src/interfaces/IGigipayErrors.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockERC20Bill is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract BillPaymentTest is Test, IGigipayEvents, IGigipayErrors {
    Gigipay public gigipay;
    MockERC20Bill public usdc;

    address public admin;
    address public pauser;
    address public user;
    address public treasury;

    // Helpers
    address constant NATIVE = address(0);
    string constant PHONE = "08012345678";
    string constant SMARTCARD = "1234567890";
    string constant METER = "45012345678";

    bytes32 phoneHash;
    bytes32 smartcardHash;
    bytes32 meterHash;

    function setUp() public {
        admin     = makeAddr("admin");
        pauser    = makeAddr("pauser");
        user      = makeAddr("user");
        treasury  = makeAddr("treasury");

        // Deploy proxy
        Gigipay impl = new Gigipay();
        bytes memory initData = abi.encodeWithSelector(
            Gigipay.initialize.selector,
            admin,
            pauser
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        gigipay = Gigipay(payable(address(proxy)));

        // Deploy mock token and fund user
        usdc = new MockERC20Bill();
        usdc.mint(user, 10_000 * 10 ** 18);
        vm.deal(user, 100 ether);

        // Pre-compute recipient hashes
        phoneHash     = keccak256(abi.encodePacked(PHONE));
        smartcardHash = keccak256(abi.encodePacked(SMARTCARD));
        meterHash     = keccak256(abi.encodePacked(METER));
    }

    // ─── payBill - native token ───────────────────────────────────────────────

    function test_PayBill_Airtime_Native() public {
        uint256 amount = 0.5 ether;

        vm.expectEmit(true, true, false, true);
        emit BillPaymentInitiated(0, user, NATIVE, amount, "airtime", "mtn", phoneHash);

        vm.prank(user);
        uint256 orderId = gigipay.payBill{value: amount}(
            NATIVE, amount, "airtime", "mtn", phoneHash
        );

        assertEq(orderId, 0, "First order should be ID 0");
        assertEq(address(gigipay).balance, amount, "Contract should hold the funds");
        console.log("[SUCCESS] Airtime payment (native) - orderId:", orderId);
    }

    function test_PayBill_Data_Native() public {
        uint256 amount = 1 ether;

        vm.prank(user);
        uint256 orderId = gigipay.payBill{value: amount}(
            NATIVE, amount, "data", "airtel-data", phoneHash
        );

        assertEq(orderId, 0);
        assertEq(address(gigipay).balance, amount);
        console.log("[SUCCESS] Data payment (native) - orderId:", orderId);
    }

    function test_PayBill_TV_Native() public {
        uint256 amount = 2 ether;

        vm.prank(user);
        uint256 orderId = gigipay.payBill{value: amount}(
            NATIVE, amount, "tv", "dstv", smartcardHash
        );

        assertEq(orderId, 0);
        assertEq(address(gigipay).balance, amount);
        console.log("[SUCCESS] TV payment (native) - orderId:", orderId);
    }

    function test_PayBill_Electricity_Native() public {
        uint256 amount = 3 ether;

        vm.prank(user);
        uint256 orderId = gigipay.payBill{value: amount}(
            NATIVE, amount, "electricity", "ikedc", meterHash
        );

        assertEq(orderId, 0);
        assertEq(address(gigipay).balance, amount);
        console.log("[SUCCESS] Electricity payment (native) - orderId:", orderId);
    }

    // ─── payBill - ERC20 token ────────────────────────────────────────────────

    function test_PayBill_Airtime_ERC20() public {
        uint256 amount = 500 * 10 ** 18;

        vm.startPrank(user);
        usdc.approve(address(gigipay), amount);

        vm.expectEmit(true, true, false, true);
        emit BillPaymentInitiated(0, user, address(usdc), amount, "airtime", "glo", phoneHash);

        uint256 orderId = gigipay.payBill(
            address(usdc), amount, "airtime", "glo", phoneHash
        );
        vm.stopPrank();

        assertEq(orderId, 0);
        assertEq(usdc.balanceOf(address(gigipay)), amount, "Contract should hold ERC20");
        console.log("[SUCCESS] Airtime payment (ERC20) - orderId:", orderId);
    }

    function test_PayBill_Electricity_ERC20() public {
        uint256 amount = 1000 * 10 ** 18;

        vm.startPrank(user);
        usdc.approve(address(gigipay), amount);

        uint256 orderId = gigipay.payBill(
            address(usdc), amount, "electricity", "ekedc", meterHash
        );
        vm.stopPrank();

        assertEq(orderId, 0);
        assertEq(usdc.balanceOf(address(gigipay)), amount);
        console.log("[SUCCESS] Electricity payment (ERC20) - orderId:", orderId);
    }

    // ─── orderId increments ───────────────────────────────────────────────────

    function test_OrderId_Increments() public {
        uint256 amount = 0.1 ether;

        vm.startPrank(user);
        uint256 id0 = gigipay.payBill{value: amount}(NATIVE, amount, "airtime", "mtn", phoneHash);
        uint256 id1 = gigipay.payBill{value: amount}(NATIVE, amount, "data",    "mtn-data", phoneHash);
        uint256 id2 = gigipay.payBill{value: amount}(NATIVE, amount, "tv",      "gotv", smartcardHash);
        uint256 id3 = gigipay.payBill{value: amount}(NATIVE, amount, "electricity", "aedc", meterHash);
        vm.stopPrank();

        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);
        console.log("[SUCCESS] Order IDs increment correctly: 0, 1, 2, 3");
    }

    // ─── payBill - revert cases ───────────────────────────────────────────────

    function test_Revert_PayBill_ZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(InvalidAmount.selector);
        gigipay.payBill{value: 0}(NATIVE, 0, "airtime", "mtn", phoneHash);
    }

    function test_Revert_PayBill_InvalidServiceType() public {
        vm.prank(user);
        vm.expectRevert(InvalidServiceType.selector);
        gigipay.payBill{value: 1 ether}(NATIVE, 1 ether, "invalid", "mtn", phoneHash);
    }

    function test_Revert_PayBill_EmptyServiceId() public {
        vm.prank(user);
        vm.expectRevert(InvalidServiceId.selector);
        gigipay.payBill{value: 1 ether}(NATIVE, 1 ether, "airtime", "", phoneHash);
    }

    function test_Revert_PayBill_ZeroRecipientHash() public {
        vm.prank(user);
        vm.expectRevert(InvalidRecipientHash.selector);
        gigipay.payBill{value: 1 ether}(NATIVE, 1 ether, "airtime", "mtn", bytes32(0));
    }

    function test_Revert_PayBill_WrongNativeAmount() public {
        // Send 0.5 ether but declare 1 ether
        vm.prank(user);
        vm.expectRevert(IncorrectNativeAmount.selector);
        gigipay.payBill{value: 0.5 ether}(NATIVE, 1 ether, "airtime", "mtn", phoneHash);
    }

    function test_Revert_PayBill_InsufficientAllowance() public {
        uint256 amount = 500 * 10 ** 18;
        // No approval given
        vm.prank(user);
        vm.expectRevert(InsufficientAllowance.selector);
        gigipay.payBill(address(usdc), amount, "airtime", "mtn", phoneHash);
    }

    function test_Revert_PayBill_WhenPaused() public {
        vm.prank(pauser);
        gigipay.pause();

        vm.prank(user);
        vm.expectRevert();
        gigipay.payBill{value: 1 ether}(NATIVE, 1 ether, "airtime", "mtn", phoneHash);
    }

    // ─── withdrawBillFunds ────────────────────────────────────────────────────

    function test_WithdrawBillFunds_Native() public {
        // First fund the contract via payBill
        uint256 amount = 5 ether;
        vm.prank(user);
        gigipay.payBill{value: amount}(NATIVE, amount, "airtime", "mtn", phoneHash);

        uint256 treasuryBefore = treasury.balance;

        vm.expectEmit(true, true, false, true);
        emit BillFundsWithdrawn(treasury, NATIVE, amount);

        vm.prank(admin);
        gigipay.withdrawBillFunds(NATIVE, treasury, amount);

        assertEq(treasury.balance, treasuryBefore + amount, "Treasury should receive funds");
        assertEq(address(gigipay).balance, 0, "Contract should be empty");
        console.log("[SUCCESS] Native funds withdrawn to treasury:", amount);
    }

    function test_WithdrawBillFunds_ERC20() public {
        uint256 amount = 1000 * 10 ** 18;

        vm.startPrank(user);
        usdc.approve(address(gigipay), amount);
        gigipay.payBill(address(usdc), amount, "tv", "dstv", smartcardHash);
        vm.stopPrank();

        uint256 treasuryBefore = usdc.balanceOf(treasury);

        vm.prank(admin);
        gigipay.withdrawBillFunds(address(usdc), treasury, amount);

        assertEq(usdc.balanceOf(treasury), treasuryBefore + amount, "Treasury should receive ERC20");
        assertEq(usdc.balanceOf(address(gigipay)), 0, "Contract should be empty");
        console.log("[SUCCESS] ERC20 funds withdrawn to treasury:", amount / 10 ** 18, "USDC");
    }

    function test_WithdrawBillFunds_Partial() public {
        uint256 deposited = 10 ether;
        uint256 withdraw  = 3 ether;

        vm.prank(user);
        gigipay.payBill{value: deposited}(NATIVE, deposited, "electricity", "phedc", meterHash);

        vm.prank(admin);
        gigipay.withdrawBillFunds(NATIVE, treasury, withdraw);

        assertEq(address(gigipay).balance, deposited - withdraw, "Remaining balance incorrect");
        assertEq(treasury.balance, withdraw, "Treasury received wrong amount");
        console.log("[SUCCESS] Partial withdrawal - remaining:", deposited - withdraw);
    }

    function test_Revert_Withdraw_NotWithdrawerRole() public {
        uint256 amount = 1 ether;
        vm.prank(user);
        gigipay.payBill{value: amount}(NATIVE, amount, "airtime", "mtn", phoneHash);

        // user does not have WITHDRAWER_ROLE
        vm.prank(user);
        vm.expectRevert();
        gigipay.withdrawBillFunds(NATIVE, treasury, amount);
    }

    function test_Revert_Withdraw_ZeroAddress() public {
        uint256 amount = 1 ether;
        vm.prank(user);
        gigipay.payBill{value: amount}(NATIVE, amount, "airtime", "mtn", phoneHash);

        vm.prank(admin);
        vm.expectRevert(InvalidRecipient.selector);
        gigipay.withdrawBillFunds(NATIVE, address(0), amount);
    }

    function test_Revert_Withdraw_ZeroAmount() public {
        vm.prank(admin);
        vm.expectRevert(InvalidAmount.selector);
        gigipay.withdrawBillFunds(NATIVE, treasury, 0);
    }

    // ─── all four service types accepted ─────────────────────────────────────

    function test_AllServiceTypes_Accepted() public {
        uint256 amount = 0.1 ether;

        vm.startPrank(user);
        gigipay.payBill{value: amount}(NATIVE, amount, "airtime",     "mtn",   phoneHash);
        gigipay.payBill{value: amount}(NATIVE, amount, "data",        "mtn-data", phoneHash);
        gigipay.payBill{value: amount}(NATIVE, amount, "tv",          "dstv",  smartcardHash);
        gigipay.payBill{value: amount}(NATIVE, amount, "electricity", "ikedc", meterHash);
        vm.stopPrank();

        assertEq(address(gigipay).balance, amount * 4, "All 4 payments should be held");
        console.log("[SUCCESS] All 4 service types accepted");
    }
}
