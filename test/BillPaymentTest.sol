// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/Gigipay.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10**18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract BillPaymentTest is Test {
    Gigipay public gigipay;
    MockToken public token;
    
    address public admin = address(1);
    address public pauser = address(2);
    address public user1 = address(3);
    address public user2 = address(4);
    address public user3 = address(5);
    
    // Events to test
    event BillPaymentInitiated(
        uint256 indexed orderId,
        address indexed buyer,
        address token,
        uint256 amount,
        string serviceType,
        string serviceId,
        bytes32 recipientHash
    );
    
    event BatchBillPaymentCompleted(
        address indexed buyer,
        address indexed token,
        uint256 totalAmount,
        string serviceType,
        uint256 recipientCount
    );
    
    event BillFundsWithdrawn(
        address indexed to,
        address indexed token,
        uint256 amount
    );

    function setUp() public {
        // Deploy implementation
        Gigipay implementation = new Gigipay();
        
        // Deploy proxy
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
        
        // Deploy mock token
        token = new MockToken();
        
        // Fund test accounts
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        
        token.mint(user1, 1000 ether);
        token.mint(user2, 1000 ether);
        token.mint(user3, 1000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // WITHDRAWAL PROTECTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_WithdrawOnlyBillFunds_NotVoucherFunds() public {
        // Scenario: User creates vouchers (10 ETH) and pays bills (5 ETH)
        // Admin should only be able to withdraw 5 ETH (bill funds), not 15 ETH
        
        // 1. User1 creates vouchers worth 10 ETH
        vm.startPrank(user1);
        bytes32[] memory claimHashes = new bytes32[](2);
        claimHashes[0] = keccak256(abi.encodePacked("code1"));
        claimHashes[1] = keccak256(abi.encodePacked("code2"));
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 4 ether;
        amounts[1] = 6 ether;
        
        uint256[] memory expirations = new uint256[](2);
        expirations[0] = block.timestamp + 1 days;
        expirations[1] = block.timestamp + 1 days;
        
        gigipay.createVoucherBatch{value: 10 ether}(
            address(0),
            "TestVouchers",
            claimHashes,
            amounts,
            expirations
        );
        vm.stopPrank();
        
        // 2. User2 pays for airtime (5 ETH)
        vm.startPrank(user2);
        bytes32 phoneHash = keccak256(abi.encodePacked("2348012345678"));
        gigipay.payBill{value: 5 ether}(
            address(0),
            5 ether,
            "airtime",
            "mtn",
            phoneHash
        );
        vm.stopPrank();
        
        // 3. Check contract balance and locked funds
        assertEq(address(gigipay).balance, 15 ether, "Contract should have 15 ETH");
        assertEq(gigipay.lockedVoucherFunds(address(0)), 10 ether, "10 ETH should be locked");
        assertEq(gigipay.getAvailableBillFunds(address(0)), 5 ether, "Only 5 ETH available");
        
        // 4. Admin tries to withdraw 10 ETH (should fail - only 5 available)
        vm.startPrank(admin);
        vm.expectRevert(IGigipayErrors.InsufficientContractBalance.selector);
        gigipay.withdrawBillFunds(address(0), admin, 10 ether);
        
        // 5. Admin withdraws 5 ETH (should succeed)
        uint256 adminBalanceBefore = admin.balance;
        gigipay.withdrawBillFunds(address(0), admin, 5 ether);
        assertEq(admin.balance - adminBalanceBefore, 5 ether, "Admin should receive 5 ETH");
        
        // 6. Contract should still have 10 ETH (voucher funds)
        assertEq(address(gigipay).balance, 10 ether, "Contract should have 10 ETH left");
        assertEq(gigipay.lockedVoucherFunds(address(0)), 10 ether, "10 ETH still locked");
        assertEq(gigipay.getAvailableBillFunds(address(0)), 0, "No bill funds left");
        vm.stopPrank();
    }

    function test_WithdrawAfterVoucherClaimed() public {
        // Scenario: After voucher is claimed, those funds should be unlocked
        
        // 1. Create voucher (5 ETH)
        vm.startPrank(user1);
        bytes32[] memory claimHashes = new bytes32[](1);
        claimHashes[0] = keccak256(abi.encodePacked("secretcode"));
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;
        
        uint256[] memory expirations = new uint256[](1);
        expirations[0] = block.timestamp + 1 days;
        
        gigipay.createVoucherBatch{value: 5 ether}(
            address(0),
            "ClaimTest",
            claimHashes,
            amounts,
            expirations
        );
        vm.stopPrank();
        
        // 2. Pay bill (3 ETH)
        vm.startPrank(user2);
        gigipay.payBill{value: 3 ether}(
            address(0),
            3 ether,
            "airtime",
            "mtn",
            keccak256(abi.encodePacked("2348012345678"))
        );
        vm.stopPrank();
        
        // 3. Check state before claim
        assertEq(gigipay.lockedVoucherFunds(address(0)), 5 ether, "5 ETH locked");
        assertEq(gigipay.getAvailableBillFunds(address(0)), 3 ether, "3 ETH available");
        
        // 4. User3 claims the voucher
        vm.prank(user3);
        gigipay.claimVoucher(keccak256(abi.encodePacked("secretcode")));
        
        // 5. After claim, locked funds should decrease
        assertEq(gigipay.lockedVoucherFunds(address(0)), 0, "No funds locked");
        assertEq(gigipay.getAvailableBillFunds(address(0)), 3 ether, "Still 3 ETH available");
        
        // 6. Admin can now withdraw the 3 ETH
        vm.prank(admin);
        gigipay.withdrawBillFunds(address(0), admin, 3 ether);
        assertEq(address(gigipay).balance, 0, "Contract should be empty");
    }

    function test_WithdrawAfterVoucherRefunded() public {
        // Scenario: After voucher is refunded, those funds should be unlocked
        
        // 1. Create voucher that expires in 1 second
        vm.startPrank(user1);
        bytes32[] memory claimHashes = new bytes32[](1);
        claimHashes[0] = keccak256(abi.encodePacked("expirecode"));
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5 ether;
        
        uint256[] memory expirations = new uint256[](1);
        expirations[0] = block.timestamp + 1;
        
        gigipay.createVoucherBatch{value: 5 ether}(
            address(0),
            "RefundTest",
            claimHashes,
            amounts,
            expirations
        );
        
        // 2. Wait for expiration
        vm.warp(block.timestamp + 2);
        
        // 3. Refund the voucher
        uint256 balanceBefore = user1.balance;
        gigipay.refundVouchersByName("RefundTest");
        assertEq(user1.balance - balanceBefore, 5 ether, "User should get refund");
        
        // 4. Locked funds should be 0
        assertEq(gigipay.lockedVoucherFunds(address(0)), 0, "No funds locked after refund");
        vm.stopPrank();
    }

    function test_WithdrawWithERC20Tokens() public {
        // Test the same protection with ERC20 tokens
        
        // 1. Create voucher with tokens (10 tokens)
        vm.startPrank(user1);
        token.approve(address(gigipay), 10 ether);
        
        bytes32[] memory claimHashes = new bytes32[](1);
        claimHashes[0] = keccak256(abi.encodePacked("tokencode"));
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10 ether;
        
        uint256[] memory expirations = new uint256[](1);
        expirations[0] = block.timestamp + 1 days;
        
        gigipay.createVoucherBatch(
            address(token),
            "TokenVoucher",
            claimHashes,
            amounts,
            expirations
        );
        vm.stopPrank();
        
        // 2. Pay bill with tokens (5 tokens)
        vm.startPrank(user2);
        token.approve(address(gigipay), 5 ether);
        gigipay.payBill(
            address(token),
            5 ether,
            "airtime",
            "mtn",
            keccak256(abi.encodePacked("2348012345678"))
        );
        vm.stopPrank();
        
        // 3. Check locked funds
        assertEq(gigipay.lockedVoucherFunds(address(token)), 10 ether, "10 tokens locked");
        assertEq(gigipay.getAvailableBillFunds(address(token)), 5 ether, "5 tokens available");
        
        // 4. Admin can only withdraw 5 tokens
        vm.startPrank(admin);
        vm.expectRevert(IGigipayErrors.InsufficientContractBalance.selector);
        gigipay.withdrawBillFunds(address(token), admin, 10 ether);
        
        gigipay.withdrawBillFunds(address(token), admin, 5 ether);
        assertEq(token.balanceOf(admin), 5 ether, "Admin should have 5 tokens");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BATCH BILL PAYMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_BatchBillPayment_Success() public {
        // Test batch airtime purchase for 3 people
        
        vm.startPrank(user1);
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;
        
        bytes32[] memory phoneHashes = new bytes32[](3);
        phoneHashes[0] = keccak256(abi.encodePacked("2348012345678"));
        phoneHashes[1] = keccak256(abi.encodePacked("2348087654321"));
        phoneHashes[2] = keccak256(abi.encodePacked("2348098765432"));
        
        uint256 totalAmount = 6 ether;
        
        // Expect individual events for each order
        vm.expectEmit(true, true, false, true);
        emit BillPaymentInitiated(0, user1, address(0), 1 ether, "airtime", "mtn", phoneHashes[0]);
        
        vm.expectEmit(true, true, false, true);
        emit BillPaymentInitiated(1, user1, address(0), 2 ether, "airtime", "mtn", phoneHashes[1]);
        
        vm.expectEmit(true, true, false, true);
        emit BillPaymentInitiated(2, user1, address(0), 3 ether, "airtime", "mtn", phoneHashes[2]);
        
        // Expect batch completion event
        vm.expectEmit(true, true, false, true);
        emit BatchBillPaymentCompleted(user1, address(0), totalAmount, "airtime", 3);
        
        uint256[] memory orderIds = gigipay.payBillBatch{value: totalAmount}(
            address(0),
            amounts,
            "airtime",
            "mtn",
            phoneHashes
        );
        
        // Verify order IDs
        assertEq(orderIds.length, 3, "Should return 3 order IDs");
        assertEq(orderIds[0], 0, "First order ID should be 0");
        assertEq(orderIds[1], 1, "Second order ID should be 1");
        assertEq(orderIds[2], 2, "Third order ID should be 2");
        
        // Verify contract received funds
        assertEq(address(gigipay).balance, 6 ether, "Contract should have 6 ETH");
        assertEq(gigipay.getAvailableBillFunds(address(0)), 6 ether, "6 ETH available for withdrawal");
        
        vm.stopPrank();
    }

    function test_BatchBillPayment_WithERC20() public {
        // Test batch payment with ERC20 tokens
        
        vm.startPrank(user1);
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10 ether;
        amounts[1] = 20 ether;
        
        bytes32[] memory phoneHashes = new bytes32[](2);
        phoneHashes[0] = keccak256(abi.encodePacked("2348012345678"));
        phoneHashes[1] = keccak256(abi.encodePacked("2348087654321"));
        
        uint256 totalAmount = 30 ether;
        token.approve(address(gigipay), totalAmount);
        
        uint256[] memory orderIds = gigipay.payBillBatch(
            address(token),
            amounts,
            "data",
            "mtn-data",
            phoneHashes
        );
        
        assertEq(orderIds.length, 2, "Should return 2 order IDs");
        assertEq(token.balanceOf(address(gigipay)), 30 ether, "Contract should have 30 tokens");
        
        vm.stopPrank();
    }

    function test_BatchBillPayment_LargeGiveaway() public {
        // Test giving airtime to 50 people (realistic giveaway scenario)
        
        vm.startPrank(user1);
        
        uint256 recipientCount = 50;
        uint256[] memory amounts = new uint256[](recipientCount);
        bytes32[] memory phoneHashes = new bytes32[](recipientCount);
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipientCount; i++) {
            amounts[i] = 0.1 ether; // 0.1 ETH each
            phoneHashes[i] = keccak256(abi.encodePacked("phone", i));
            totalAmount += amounts[i];
        }
        
        uint256[] memory orderIds = gigipay.payBillBatch{value: totalAmount}(
            address(0),
            amounts,
            "airtime",
            "mtn",
            phoneHashes
        );
        
        assertEq(orderIds.length, 50, "Should return 50 order IDs");
        assertEq(address(gigipay).balance, 5 ether, "Contract should have 5 ETH");
        
        vm.stopPrank();
    }

    function test_BatchBillPayment_VariableAmounts() public {
        // Test with different amounts for each recipient
        
        vm.startPrank(user1);
        
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 0.5 ether;
        amounts[1] = 1.0 ether;
        amounts[2] = 1.5 ether;
        amounts[3] = 2.0 ether;
        amounts[4] = 2.5 ether;
        
        bytes32[] memory phoneHashes = new bytes32[](5);
        for (uint256 i = 0; i < 5; i++) {
            phoneHashes[i] = keccak256(abi.encodePacked("phone", i));
        }
        
        uint256 totalAmount = 7.5 ether;
        
        uint256[] memory orderIds = gigipay.payBillBatch{value: totalAmount}(
            address(0),
            amounts,
            "airtime",
            "mtn",
            phoneHashes
        );
        
        assertEq(orderIds.length, 5, "Should return 5 order IDs");
        assertEq(address(gigipay).balance, 7.5 ether, "Contract should have 7.5 ETH");
        
        vm.stopPrank();
    }

    function test_BatchBillPayment_RevertEmptyArray() public {
        vm.startPrank(user1);
        
        uint256[] memory amounts = new uint256[](0);
        bytes32[] memory phoneHashes = new bytes32[](0);
        
        vm.expectRevert(IGigipayErrors.EmptyArray.selector);
        gigipay.payBillBatch{value: 0}(
            address(0),
            amounts,
            "airtime",
            "mtn",
            phoneHashes
        );
        
        vm.stopPrank();
    }

    function test_BatchBillPayment_RevertLengthMismatch() public {
        vm.startPrank(user1);
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;
        
        bytes32[] memory phoneHashes = new bytes32[](2); // Wrong length!
        phoneHashes[0] = keccak256(abi.encodePacked("phone1"));
        phoneHashes[1] = keccak256(abi.encodePacked("phone2"));
        
        vm.expectRevert(IGigipayErrors.LengthMismatch.selector);
        gigipay.payBillBatch{value: 6 ether}(
            address(0),
            amounts,
            "airtime",
            "mtn",
            phoneHashes
        );
        
        vm.stopPrank();
    }

    function test_BatchBillPayment_RevertIncorrectAmount() public {
        vm.startPrank(user1);
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        
        bytes32[] memory phoneHashes = new bytes32[](2);
        phoneHashes[0] = keccak256(abi.encodePacked("phone1"));
        phoneHashes[1] = keccak256(abi.encodePacked("phone2"));
        
        // Send wrong amount (2 ETH instead of 3 ETH)
        vm.expectRevert(IGigipayErrors.IncorrectNativeAmount.selector);
        gigipay.payBillBatch{value: 2 ether}(
            address(0),
            amounts,
            "airtime",
            "mtn",
            phoneHashes
        );
        
        vm.stopPrank();
    }

    function test_BatchBillPayment_RevertInvalidServiceType() public {
        vm.startPrank(user1);
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        
        bytes32[] memory phoneHashes = new bytes32[](1);
        phoneHashes[0] = keccak256(abi.encodePacked("phone1"));
        
        vm.expectRevert(IGigipayErrors.InvalidServiceType.selector);
        gigipay.payBillBatch{value: 1 ether}(
            address(0),
            amounts,
            "invalid_service", // Invalid!
            "mtn",
            phoneHashes
        );
        
        vm.stopPrank();
    }

    function test_BatchBillPayment_RevertBatchTooLarge() public {
        vm.startPrank(user1);
        
        // Try to create 201 orders (max is 200)
        uint256[] memory amounts = new uint256[](201);
        bytes32[] memory phoneHashes = new bytes32[](201);
        
        for (uint256 i = 0; i < 201; i++) {
            amounts[i] = 0.1 ether;
            phoneHashes[i] = keccak256(abi.encodePacked("phone", i));
        }
        
        vm.expectRevert(IGigipayErrors.BatchTooLarge.selector);
        gigipay.payBillBatch{value: 20.1 ether}(
            address(0),
            amounts,
            "airtime",
            "mtn",
            phoneHashes
        );
        
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTEGRATION TESTS (Batch + Withdrawal)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Integration_BatchPaymentAndWithdrawal() public {
        // Complete flow: batch payment → withdrawal
        
        // 1. User1 does batch airtime purchase
        vm.startPrank(user1);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;
        
        bytes32[] memory phoneHashes = new bytes32[](3);
        phoneHashes[0] = keccak256(abi.encodePacked("phone1"));
        phoneHashes[1] = keccak256(abi.encodePacked("phone2"));
        phoneHashes[2] = keccak256(abi.encodePacked("phone3"));
        
        gigipay.payBillBatch{value: 6 ether}(
            address(0),
            amounts,
            "airtime",
            "mtn",
            phoneHashes
        );
        vm.stopPrank();
        
        // 2. Admin withdraws the funds
        vm.startPrank(admin);
        uint256 adminBalanceBefore = admin.balance;
        gigipay.withdrawBillFunds(address(0), admin, 6 ether);
        assertEq(admin.balance - adminBalanceBefore, 6 ether, "Admin should receive 6 ETH");
        assertEq(address(gigipay).balance, 0, "Contract should be empty");
        vm.stopPrank();
    }

    function test_Integration_MixedFunds() public {
        // Complex scenario: vouchers + single bill + batch bill + withdrawal
        
        // 1. User1 creates vouchers (10 ETH)
        vm.startPrank(user1);
        bytes32[] memory claimHashes = new bytes32[](1);
        claimHashes[0] = keccak256(abi.encodePacked("vouchercode"));
        uint256[] memory voucherAmounts = new uint256[](1);
        voucherAmounts[0] = 10 ether;
        uint256[] memory expirations = new uint256[](1);
        expirations[0] = block.timestamp + 1 days;
        
        gigipay.createVoucherBatch{value: 10 ether}(
            address(0),
            "MixedTest",
            claimHashes,
            voucherAmounts,
            expirations
        );
        vm.stopPrank();
        
        // 2. User2 pays single bill (3 ETH)
        vm.startPrank(user2);
        gigipay.payBill{value: 3 ether}(
            address(0),
            3 ether,
            "airtime",
            "mtn",
            keccak256(abi.encodePacked("phone1"))
        );
        vm.stopPrank();
        
        // 3. User3 does batch payment (5 ETH)
        vm.startPrank(user3);
        uint256[] memory batchAmounts = new uint256[](2);
        batchAmounts[0] = 2 ether;
        batchAmounts[1] = 3 ether;
        
        bytes32[] memory phoneHashes = new bytes32[](2);
        phoneHashes[0] = keccak256(abi.encodePacked("phone2"));
        phoneHashes[1] = keccak256(abi.encodePacked("phone3"));
        
        gigipay.payBillBatch{value: 5 ether}(
            address(0),
            batchAmounts,
            "airtime",
            "mtn",
            phoneHashes
        );
        vm.stopPrank();
        
        // 4. Check state
        assertEq(address(gigipay).balance, 18 ether, "Total: 10 + 3 + 5 = 18 ETH");
        assertEq(gigipay.lockedVoucherFunds(address(0)), 10 ether, "10 ETH locked in vouchers");
        assertEq(gigipay.getAvailableBillFunds(address(0)), 8 ether, "8 ETH available (3 + 5)");
        
        // 5. Admin can only withdraw 8 ETH
        vm.startPrank(admin);
        gigipay.withdrawBillFunds(address(0), admin, 8 ether);
        assertEq(address(gigipay).balance, 10 ether, "10 ETH left (voucher funds)");
        vm.stopPrank();
    }
}
