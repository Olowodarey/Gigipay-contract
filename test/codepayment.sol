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

    address constant NATIVE_TOKEN = address(0);

    // Plain-text codes (never sent on-chain — only their hashes are)
    string constant CODE1 = "SECRET123";
    string constant CODE2 = "GIFT2024";
    string constant CODE3 = "PROMO999";
    string constant WRONG_CODE = "WRONGCODE";

    // Pre-computed hashes — keccak256(voucherName + claimCode), same as frontend
    bytes32 constant HASH1 = keccak256(abi.encodePacked(VOUCHER1, "SECRET123"));
    bytes32 constant HASH2 = keccak256(abi.encodePacked(VOUCHER1, "GIFT2024"));
    bytes32 constant HASH3 = keccak256(abi.encodePacked(VOUCHER1, "PROMO999"));
    bytes32 constant WRONG_HASH = keccak256(abi.encodePacked(VOUCHER1, "WRONGCODE"));

    string constant VOUCHER1 = "TestVoucher1";
    string constant VOUCHER2 = "TestVoucher2";
    string constant VOUCHER3 = "TestVoucher3";

    function setUp() public {
        admin = makeAddr("admin");
        pauser = makeAddr("pauser");
        sender = makeAddr("sender");
        claimer1 = makeAddr("claimer1");
        claimer2 = makeAddr("claimer2");

        Gigipay implementation = new Gigipay();
        bytes memory initData = abi.encodeWithSelector(
            Gigipay.initialize.selector,
            admin,
            pauser
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        gigipay = Gigipay(payable(address(proxy)));

        vm.deal(sender, 100 ether);
    }

    function test_CreateSingleVoucher() public {
        uint256 amount = 1 ether;
        uint256 expiresAt = block.timestamp + 7 days;

        vm.expectEmit(true, true, false, true);
        emit VoucherCreated(0, sender, amount, expiresAt);

        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = HASH1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256[] memory expirationTimes = new uint256[](1);
        expirationTimes[0] = expiresAt;

        vm.prank(sender);
        uint256[] memory voucherIds = gigipay.createVoucherBatch{value: amount}(
            NATIVE_TOKEN, VOUCHER1, hashes, amounts, expirationTimes
        );
        uint256 voucherId = voucherIds[0];

        assertEq(voucherId, 0, "First voucher should have ID 0");

        (
            address voucherSender,
            ,
            uint256 voucherAmount,
            bytes32 storedHash,
            uint256 voucherExpiresAt,
            bool claimed,
            bool refunded,
            string memory voucherName
        ) = gigipay.vouchers(voucherId);

        assertEq(voucherSender, sender);
        assertEq(voucherAmount, amount);
        assertEq(storedHash, HASH1, "Hash should be stored as-is");
        assertEq(voucherExpiresAt, expiresAt);
        assertFalse(claimed);
        assertFalse(refunded);
        assertEq(voucherName, VOUCHER1);

        console.log("[SUCCESS] Single voucher created - hash stored, plain code never on-chain");
    }

    function test_CreateBatchVouchers() public {
        bytes32[] memory hashes = new bytes32[](3);
        hashes[0] = HASH1;
        hashes[1] = HASH2;
        hashes[2] = HASH3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;

        uint256[] memory expirationTimes = new uint256[](3);
        expirationTimes[0] = block.timestamp + 1 days;
        expirationTimes[1] = block.timestamp + 7 days;
        expirationTimes[2] = block.timestamp + 30 days;

        vm.prank(sender);
        uint256[] memory voucherIds = gigipay.createVoucherBatch{value: 6 ether}(
            NATIVE_TOKEN, VOUCHER1, hashes, amounts, expirationTimes
        );

        assertEq(voucherIds.length, 3);
        assertEq(gigipay.getSenderVouchers(sender).length, 3);
        assertEq(gigipay.getVouchersByName(VOUCHER1).length, 3);

        console.log("[SUCCESS] Batch of 3 vouchers created with hashed codes");
    }

    function test_ClaimVoucherWithCorrectCode() public {
        uint256 amount = 5 ether;
        uint256 expiresAt = block.timestamp + 7 days;

        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = HASH1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256[] memory expirationTimes = new uint256[](1);
        expirationTimes[0] = expiresAt;

        vm.prank(sender);
        uint256[] memory voucherIds = gigipay.createVoucherBatch{value: amount}(
            NATIVE_TOKEN, VOUCHER1, hashes, amounts, expirationTimes
        );
        uint256 voucherId = voucherIds[0];

        uint256 claimerBalanceBefore = claimer1.balance;

        vm.expectEmit(true, true, false, true);
        emit VoucherClaimed(voucherId, claimer1, amount);

        // Claimer passes the hash of their code — plain text never on-chain
        vm.prank(claimer1);
        gigipay.claimVoucher(HASH1);

        assertEq(claimer1.balance - claimerBalanceBefore, amount);
        (, , , , , bool claimed, , ) = gigipay.vouchers(voucherId);
        assertTrue(claimed);

        console.log("[SUCCESS] Voucher claimed using hash - plain code never exposed");
    }

    function test_RevertClaimWithWrongHash() public {
        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = HASH1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        uint256[] memory expirationTimes = new uint256[](1);
        expirationTimes[0] = block.timestamp + 7 days;

        vm.prank(sender);
        gigipay.createVoucherBatch{value: 1 ether}(
            NATIVE_TOKEN, VOUCHER1, hashes, amounts, expirationTimes
        );

        vm.prank(claimer1);
        vm.expectRevert(InvalidClaimCode.selector);
        gigipay.claimVoucher(WRONG_HASH);
    }

    function test_SameCodeDifferentCampaignsNoCollision() public {
        // Two senders use the same plain-text code "happybirthday" in different campaigns
        address sender2 = makeAddr("sender2");
        vm.deal(sender2, 10 ether);

        // Hash is scoped: keccak256(voucherName + code)
        bytes32 hash_alice = keccak256(abi.encodePacked("AliceBirthday", "happybirthday"));
        bytes32 hash_bob   = keccak256(abi.encodePacked("BobBirthday",   "happybirthday"));

        // They must be different
        assertTrue(hash_alice != hash_bob, "Hashes must differ across campaigns");

        bytes32[] memory hashes1 = new bytes32[](1);
        hashes1[0] = hash_alice;
        uint256[] memory amounts1 = new uint256[](1);
        amounts1[0] = 1 ether;
        uint256[] memory exp1 = new uint256[](1);
        exp1[0] = block.timestamp + 1 days;

        bytes32[] memory hashes2 = new bytes32[](1);
        hashes2[0] = hash_bob;
        uint256[] memory amounts2 = new uint256[](1);
        amounts2[0] = 2 ether;
        uint256[] memory exp2 = new uint256[](1);
        exp2[0] = block.timestamp + 1 days;

        // Both can be created without collision
        vm.prank(sender);
        gigipay.createVoucherBatch{value: 1 ether}(
            NATIVE_TOKEN, "AliceBirthday", hashes1, amounts1, exp1
        );
        vm.prank(sender2);
        gigipay.createVoucherBatch{value: 2 ether}(
            NATIVE_TOKEN, "BobBirthday", hashes2, amounts2, exp2
        );

        // claimer1 claims Alice's voucher — gets 1 ether
        uint256 before = claimer1.balance;
        vm.prank(claimer1);
        gigipay.claimVoucher(hash_alice);
        assertEq(claimer1.balance - before, 1 ether, "Should get Alice's amount");

        // claimer2 claims Bob's voucher — gets 2 ether
        address claimerB = makeAddr("claimerB");
        vm.prank(claimerB);
        gigipay.claimVoucher(hash_bob);
        assertEq(claimerB.balance, 2 ether, "Should get Bob's amount");

        console.log("[SUCCESS] Same code word in different campaigns - no collision");
    }

    function test_RefundExpiredVoucher() public {
        uint256 amount = 2 ether;
        uint256 expiresAt = block.timestamp + 1 hours;

        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = HASH1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256[] memory expirationTimes = new uint256[](1);
        expirationTimes[0] = expiresAt;

        vm.prank(sender);
        gigipay.createVoucherBatch{value: amount}(
            NATIVE_TOKEN, VOUCHER1, hashes, amounts, expirationTimes
        );

        uint256 senderBalanceBefore = sender.balance;
        vm.warp(block.timestamp + 2 hours);

        vm.prank(sender);
        uint256 refundedCount = gigipay.refundVouchersByName(VOUCHER1);

        assertEq(refundedCount, 1);
        assertEq(sender.balance - senderBalanceBefore, amount);

        console.log("[SUCCESS] Expired voucher refunded");
    }
}
