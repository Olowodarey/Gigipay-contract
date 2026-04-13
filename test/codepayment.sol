// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Gigipay} from "../src/Gigipay.sol";
import {IGigipayEvents} from "../src/interfaces/IGigipayEvents.sol";
import {IGigipayErrors} from "../src/interfaces/IGigipayErrors.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract CodePaymentTest is Test, IGigipayEvents, IGigipayErrors {
    Gigipay public gigipay;

    address public admin;
    address public pauser;
    address public sender;
    address public claimer1;
    address public claimer2;

    // Native token address (0x0 for ETH/CELO)
    address constant NATIVE_TOKEN = address(0);

    // Test claim codes
    string constant CODE1 = "SECRET123";
    string constant CODE2 = "GIFT2024";
    string constant CODE3 = "PROMO999";
    string constant WRONG_CODE = "WRONGCODE";

    // Test voucher names
    string constant VOUCHER1 = "TestVoucher1";
    string constant VOUCHER2 = "TestVoucher2";
    string constant VOUCHER3 = "TestVoucher3";
    string constant VOUCHER4 = "Birthday2024";
    string constant VOUCHER5 = "Christmas2024";

    function setUp() public {
        // Create test addresses
        admin = makeAddr("admin");
        pauser = makeAddr("pauser");
        sender = makeAddr("sender");
        claimer1 = makeAddr("claimer1");
        claimer2 = makeAddr("claimer2");

        // Deploy implementation
        Gigipay implementation = new Gigipay();

        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            Gigipay.initialize.selector,
            admin,
            pauser
        );
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        gigipay = Gigipay(payable(address(proxy)));

        // Fund sender with CELO
        vm.deal(sender, 100 ether);
    }

    function test_CreateSingleVoucher() public {
        uint256 amount = 1 ether;
        uint256 expiresAt = block.timestamp + 7 days;

        // Expect event emission
        vm.expectEmit(true, true, false, true);
        emit VoucherCreated(0, sender, amount, expiresAt);

        // Create single voucher using batch function
        string[] memory codes = new string[](1);
        codes[0] = CODE1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256[] memory expirationTimes = new uint256[](1);
        expirationTimes[0] = expiresAt;

        vm.prank(sender);
        uint256[] memory voucherIds = gigipay.createVoucherBatch{value: amount}(
            NATIVE_TOKEN,
            VOUCHER1,
            codes,
            amounts,
            expirationTimes
        );
        uint256 voucherId = voucherIds[0];

        // Verify voucher was created
        assertEq(voucherId, 0, "First voucher should have ID 0");

        // Check voucher details (8 fields now: sender, token, amount, claimCodeHash, expiresAt, claimed, refunded, voucherName)
        (
            address voucherSender,
            address token,
            uint256 voucherAmount,
            ,
            uint256 voucherExpiresAt,
            bool claimed,
            bool refunded,
            string memory voucherName
        ) = gigipay.vouchers(voucherId);

        assertEq(voucherSender, sender, "Sender mismatch");
        assertEq(token, NATIVE_TOKEN, "Token should be native");
        assertEq(voucherAmount, amount, "Amount mismatch");
        assertEq(voucherExpiresAt, expiresAt, "Expiration mismatch");
        assertFalse(claimed, "Should not be claimed");
        assertFalse(refunded, "Should not be refunded");
        assertEq(voucherName, VOUCHER1, "Voucher name mismatch");

        console.log("[SUCCESS] Single voucher created with ID:", voucherId);
        console.log("  Amount:", amount);
        console.log("  Expires at:", expiresAt);
    }

    function test_CreateBatchVouchers() public {
        // Create 3 vouchers under ONE campaign name
        string[] memory codes = new string[](3);
        codes[0] = CODE1;
        codes[1] = CODE2;
        codes[2] = CODE3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;

        uint256[] memory expirationTimes = new uint256[](3);
        expirationTimes[0] = block.timestamp + 1 days;
        expirationTimes[1] = block.timestamp + 7 days;
        expirationTimes[2] = block.timestamp + 30 days;

        uint256 totalAmount = 6 ether;

        vm.prank(sender);
        uint256[] memory voucherIds = gigipay.createVoucherBatch{
            value: totalAmount
        }(
            NATIVE_TOKEN,
            VOUCHER1, // ONE campaign name for all vouchers
            codes,
            amounts,
            expirationTimes
        );

        // Verify all vouchers were created
        assertEq(voucherIds.length, 3, "Should create 3 vouchers");
        assertEq(voucherIds[0], 0, "First voucher ID");
        assertEq(voucherIds[1], 1, "Second voucher ID");
        assertEq(voucherIds[2], 2, "Third voucher ID");

        // Check sender's vouchers
        uint256[] memory senderVouchers = gigipay.getSenderVouchers(sender);
        assertEq(senderVouchers.length, 3, "Sender should have 3 vouchers");

        // Check vouchers by campaign name
        uint256[] memory campaignVouchers = gigipay.getVouchersByName(VOUCHER1);
        assertEq(campaignVouchers.length, 3, "Campaign should have 3 vouchers");

        console.log(
            "[SUCCESS] Batch created 3 vouchers under ONE campaign:",
            VOUCHER1
        );
        console.log("  Voucher 0: 1 CELO, expires in 1 day");
        console.log("  Voucher 1: 2 CELO, expires in 7 days");
        console.log("  Voucher 2: 3 CELO, expires in 30 days");
    }

    function test_ClaimVoucherWithCorrectCode() public {
        uint256 amount = 5 ether;
        uint256 expiresAt = block.timestamp + 7 days;

        // Create voucher
        string[] memory codes = new string[](1);
        codes[0] = CODE1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256[] memory expirationTimes = new uint256[](1);
        expirationTimes[0] = expiresAt;

        vm.prank(sender);
        uint256[] memory voucherIds = gigipay.createVoucherBatch{value: amount}(
            NATIVE_TOKEN,
            VOUCHER1,
            codes,
            amounts,
            expirationTimes
        );
        uint256 voucherId = voucherIds[0];

        uint256 claimerBalanceBefore = claimer1.balance;
        uint256 contractBalanceBefore = address(gigipay).balance;

        console.log("[BEFORE CLAIM]");
        console.log("  Claimer balance:", claimerBalanceBefore);
        console.log("  Contract balance:", contractBalanceBefore);
        console.log("  Voucher amount:", amount);

        // Expect event emission
        vm.expectEmit(true, true, false, true);
        emit VoucherClaimed(voucherId, claimer1, amount);

        // Claim voucher by campaign name
        vm.prank(claimer1);
        gigipay.claimVoucher(VOUCHER1, CODE1);

        uint256 claimerBalanceAfter = claimer1.balance;
        uint256 contractBalanceAfter = address(gigipay).balance;
        uint256 amountClaimed = claimerBalanceAfter - claimerBalanceBefore;

        console.log("[AFTER CLAIM]");
        console.log("  Claimer balance:", claimerBalanceAfter);
        console.log("  Contract balance:", contractBalanceAfter);
        console.log("  Amount claimed:", amountClaimed);

        // Verify claim (8 fields now)
        (, , , , , bool claimed, , ) = gigipay.vouchers(voucherId);
        assertTrue(claimed, "Voucher should be claimed");
        assertEq(
            amountClaimed,
            amount,
            "Claimer should receive exact voucher amount"
        );
        assertEq(
            contractBalanceAfter,
            contractBalanceBefore - amount,
            "Contract balance should decrease"
        );

        console.log("[SUCCESS] Voucher claimed by name successfully");
        console.log("  Campaign:", VOUCHER1);
        console.log("  [OK] Claimed amount matches voucher amount:", amount);
    }

    function test_RefundExpiredVoucher() public {
        uint256 amount = 2 ether;
        uint256 expiresAt = block.timestamp + 1 hours;

        // Create voucher
        string[] memory codes = new string[](1);
        codes[0] = CODE1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256[] memory expirationTimes = new uint256[](1);
        expirationTimes[0] = expiresAt;

        vm.prank(sender);
        gigipay.createVoucherBatch{value: amount}(
            NATIVE_TOKEN,
            VOUCHER1,
            codes,
            amounts,
            expirationTimes
        );

        uint256 senderBalanceBefore = sender.balance;

        // Fast forward past expiration
        vm.warp(block.timestamp + 2 hours);

        // Refund voucher by name (new function)
        vm.prank(sender);
        uint256 refundedCount = gigipay.refundVouchersByName(VOUCHER1);

        uint256 amountRefunded = sender.balance - senderBalanceBefore;

        // Verify refund
        assertEq(refundedCount, 1, "Should refund 1 voucher");
        assertEq(
            amountRefunded,
            amount,
            "Sender should receive exact refund amount"
        );

        console.log("[SUCCESS] Expired voucher refunded by name");
        console.log("  [OK] Refund amount:", amountRefunded);
        console.log("  [OK] Refunded count:", refundedCount);
    }
}
