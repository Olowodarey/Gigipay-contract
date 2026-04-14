// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.5.0
pragma solidity ^0.8.27;

import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    Initializable
} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IGigipayErrors} from "./interfaces/IGigipayErrors.sol";
import {IGigipayEvents} from "./interfaces/IGigipayEvents.sol";

contract Gigipay is
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    IGigipayErrors,
    IGigipayEvents
{
    using SafeERC20 for IERC20;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    // Max items per batch call — prevents block gas limit DoS
    uint256 public constant MAX_BATCH_SIZE = 200;

    // Valid service types
    bytes32 private constant _AIRTIME     = keccak256("airtime");
    bytes32 private constant _DATA        = keccak256("data");
    bytes32 private constant _TV          = keccak256("tv");
    bytes32 private constant _ELECTRICITY = keccak256("electricity");

    // Payment Voucher System
    struct PaymentVoucher {
        address sender;
        address token; // Token address (address(0) for native token)
        uint256 amount;
        bytes32 claimCodeHash; // keccak256(abi.encodePacked(claimCode))
        uint256 expiresAt;
        bool claimed;
        bool refunded;
        string voucherName; // Name/identifier for the voucher (e.g., "Birthday2024")
    }

    // Counter for unique voucher IDs
    uint256 private _voucherIdCounter;

    // Mapping from voucher ID to PaymentVoucher
    mapping(uint256 => PaymentVoucher) public vouchers;

    // Mapping from sender to their voucher IDs
    mapping(address => uint256[]) public senderVouchers;

    // Mapping from voucher name hash to array of voucher IDs (one name, multiple codes)
    mapping(bytes32 => uint256[]) public voucherNameToIds;

    // Mapping to check if a voucher name exists
    mapping(bytes32 => bool) public voucherNameExists;

    // Direct lookup: claimCodeHash => voucherId + 1 (0 means not registered)
    mapping(bytes32 => uint256) public claimHashToVoucherId;

    // Bill Payment
    uint256 private _billOrderCounter;

    // Reentrancy guard
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() internal {
        if (_status == _ENTERED) revert ReentrantCall();
        _status = _ENTERED;
    }

    function _nonReentrantAfter() internal {
        _status = _NOT_ENTERED;
    }

    function initialize(
        address defaultAdmin,
        address pauser
    ) public initializer {
        __Pausable_init();
        __AccessControl_init();
        _status = _NOT_ENTERED;

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(WITHDRAWER_ROLE, defaultAdmin);
    }

    /**
     * @notice Create multiple payment vouchers under ONE voucher name (gas efficient!)
     * @param voucherName The shared name for all vouchers (e.g., "december2024")
     * @param claimCodeHashes Array of keccak256 hashes of the secret codes — hashed CLIENT-SIDE before sending
     * @param amounts Array of amounts for each voucher
     * @param expirationTimes Array of expiration timestamps for each voucher
     * @return voucherIds Array of created voucher IDs
     */
    function createVoucherBatch(
        address token,
        string memory voucherName,
        bytes32[] memory claimCodeHashes,
        uint256[] memory amounts,
        uint256[] memory expirationTimes
    ) public payable nonReentrant whenNotPaused returns (uint256[] memory) {
        uint256 length = claimCodeHashes.length;

        // ── Input validation (all checks before any state change or transfer) ─
        if (length == 0) revert EmptyArray();
        if (length > MAX_BATCH_SIZE) revert BatchTooLarge();
        if (length != amounts.length || length != expirationTimes.length)
            revert InvalidAmount();
        if (bytes(voucherName).length == 0) revert InvalidClaimCode();

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < length; i++) {
            if (amounts[i] == 0) revert InvalidAmount();
            if (expirationTimes[i] <= block.timestamp) revert InvalidExpirationTime();
            if (claimCodeHashes[i] == bytes32(0)) revert InvalidClaimCode();
            // Prevent duplicate hashes — would silently overwrite claimHashToVoucherId
            if (claimHashToVoucherId[claimCodeHashes[i]] != 0) revert DuplicateClaimCode();
            totalAmount += amounts[i];
        }
        // ── Collect payment ───────────────────────────────────────────────────
        if (token == address(0)) {
            if (msg.value != totalAmount) revert InvalidAmount();
        } else {
            if (IERC20(token).allowance(msg.sender, address(this)) < totalAmount)
                revert InsufficientAllowance();
            IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);
        }

        // ── Write state ───────────────────────────────────────────────────────
        bytes32 voucherNameHash = keccak256(abi.encodePacked(voucherName));
        uint256[] memory voucherIds = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            uint256 voucherId = _voucherIdCounter++;

            vouchers[voucherId] = PaymentVoucher({
                sender: msg.sender,
                token: token,
                amount: amounts[i],
                claimCodeHash: claimCodeHashes[i],
                expiresAt: expirationTimes[i],
                claimed: false,
                refunded: false,
                voucherName: voucherName
            });

            senderVouchers[msg.sender].push(voucherId);
            voucherNameToIds[voucherNameHash].push(voucherId);
            claimHashToVoucherId[claimCodeHashes[i]] = voucherId + 1;
            voucherIds[i] = voucherId;

            emit VoucherCreated(voucherId, msg.sender, amounts[i], expirationTimes[i]);
        }

        voucherNameExists[voucherNameHash] = true;
        return voucherIds;
    }

    /**
     * @notice Claim a payment voucher using the hash of the claim code.
     *         The plain-text code is hashed CLIENT-SIDE — it never appears on-chain.
     * @param claimCodeHash keccak256(abi.encodePacked(claimCode)) — computed by the frontend
     */
    function claimVoucher(
        bytes32 claimCodeHash
    ) public nonReentrant whenNotPaused {
        // O(1) direct lookup — stored as voucherId + 1, so 0 means not registered
        uint256 stored = claimHashToVoucherId[claimCodeHash];
        if (stored == 0) revert InvalidClaimCode();
        uint256 voucherId = stored - 1;

        PaymentVoucher storage voucher = vouchers[voucherId];

        if (voucher.sender == address(0)) revert VoucherNotFound();
        if (voucher.claimed || voucher.refunded) revert VoucherAlreadyClaimed();
        if (block.timestamp > voucher.expiresAt) revert VoucherExpired();

        // Effects before interactions
        voucher.claimed = true;

        if (voucher.token == address(0)) {
            (bool success, ) = payable(msg.sender).call{value: voucher.amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(voucher.token).safeTransfer(msg.sender, voucher.amount);
        }

        emit VoucherClaimed(voucherId, msg.sender, voucher.amount);
    }

    /**
     * @notice Refund all expired vouchers under a voucher name back to the sender
     * @param voucherName The name of the voucher campaign to refund
     * @return refundedCount Number of vouchers successfully refunded
     */
    function refundVouchersByName(
        string memory voucherName
    ) public nonReentrant whenNotPaused returns (uint256) {
        bytes32 voucherNameHash = keccak256(abi.encodePacked(voucherName));
        uint256[] memory voucherIds = voucherNameToIds[voucherNameHash];

        if (voucherIds.length == 0) revert VoucherNotFound();

        uint256 refundedCount = 0;
        uint256 totalRefundAmount = 0;
        address tokenToRefund = address(0);
        bool isFirstRefund = true;

        // ── Effects: mark all eligible vouchers as refunded first ────────────
        for (uint256 i = 0; i < voucherIds.length; i++) {
            PaymentVoucher storage voucher = vouchers[voucherIds[i]];

            if (voucher.claimed || voucher.refunded) continue;
            if (block.timestamp <= voucher.expiresAt) continue;
            if (msg.sender != voucher.sender) continue;

            if (isFirstRefund) {
                tokenToRefund = voucher.token;
                isFirstRefund = false;
            }

            if (voucher.token != tokenToRefund) continue;

            // State change BEFORE any transfer
            voucher.refunded = true;
            totalRefundAmount += voucher.amount;
            refundedCount++;

            emit VoucherRefunded(voucherIds[i], voucher.sender, voucher.amount);
        }

        if (refundedCount == 0) revert VoucherNotExpired();

        // ── Interactions: single transfer after all state is updated ─────────
        if (tokenToRefund == address(0)) {
            (bool success, ) = payable(msg.sender).call{value: totalRefundAmount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(tokenToRefund).safeTransfer(msg.sender, totalRefundAmount);
        }

        return refundedCount;
    }

    /**
     * @notice Get all voucher IDs created by a sender
     * @param sender The address of the sender
     * @return Array of voucher IDs
     */
    function getSenderVouchers(
        address sender
    ) public view returns (uint256[] memory) {
        return senderVouchers[sender];
    }

    /**
     * @notice Get all voucher IDs under a voucher name
     * @param voucherName The name of the voucher campaign
     * @return Array of voucher IDs
     */
    function getVouchersByName(
        string memory voucherName
    ) public view returns (uint256[] memory) {
        bytes32 voucherNameHash = keccak256(abi.encodePacked(voucherName));
        return voucherNameToIds[voucherNameHash];
    }

    /**
     * @notice Check if a voucher is claimable (not claimed, not refunded, not expired)
     * @param voucherId The ID of the voucher to check
     * @return True if the voucher can be claimed
     */
    function isVoucherClaimable(uint256 voucherId) public view returns (bool) {
        PaymentVoucher memory voucher = vouchers[voucherId];
        return
            voucher.sender != address(0) &&
            !voucher.claimed &&
            !voucher.refunded &&
            block.timestamp <= voucher.expiresAt;
    }

    /**
     * @notice Check if a voucher is refundable (not claimed, not refunded, expired)
     * @param voucherId The ID of the voucher to check
     * @return True if the voucher can be refunded
     */
    function isVoucherRefundable(uint256 voucherId) public view returns (bool) {
        PaymentVoucher memory voucher = vouchers[voucherId];
        return
            voucher.sender != address(0) &&
            !voucher.claimed &&
            !voucher.refunded &&
            block.timestamp > voucher.expiresAt;
    }

    /**
     * @notice Batch transfer native tokens (ETH/CELO) or ERC20 tokens to multiple recipients
     * @param token Address of the ERC20 token (use address(0) for native token)
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts to send to each recipient
     */
    function batchTransfer(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external payable nonReentrant whenNotPaused {
        if (recipients.length != amounts.length) revert LengthMismatch();
        if (recipients.length == 0) revert EmptyArray();
        if (recipients.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        if (token == address(0)) {
            // Native CELO transfer
            if (msg.value != totalAmount) revert IncorrectNativeAmount();

            for (uint256 i = 0; i < recipients.length; i++) {
                if (recipients[i] == address(0)) revert InvalidRecipient();
                (bool success, ) = payable(recipients[i]).call{
                    value: amounts[i]
                }("");
                if (!success) revert TransferFailed();
            }
        } else {
            // ERC20 token transfer
            IERC20 tokenContract = IERC20(token);

            if (
                tokenContract.allowance(msg.sender, address(this)) < totalAmount
            ) {
                revert InsufficientAllowance();
            }

            for (uint256 i = 0; i < recipients.length; i++) {
                if (recipients[i] == address(0)) revert InvalidRecipient();
                tokenContract.safeTransferFrom(
                    msg.sender,
                    recipients[i],
                    amounts[i]
                );
            }
        }

        emit BatchTransferCompleted(
            msg.sender,
            token,
            totalAmount,
            recipients.length
        );
    }

    /**
     * @notice Pay for a bill service (airtime, data, TV, electricity) using any supported token.
     *         Funds are held in the contract; backend listens for the event and fulfils the order.
     * @param token        ERC20 token address, or address(0) for native CELO/ETH
     * @param amount       Amount of tokens to pay (in token's smallest unit)
     * @param serviceType  One of: "airtime", "data", "tv", "electricity"
     * @param serviceId    VTPass service ID e.g. "mtn", "airtel", "dstv", "ikedc"
     * @param recipientHash keccak256(abi.encodePacked(phoneNumber / smartcardNo / meterNo))
     * @return orderId     Unique order ID emitted in the event for backend tracking
     */
    function payBill(
        address token,
        uint256 amount,
        string calldata serviceType,
        string calldata serviceId,
        bytes32 recipientHash
    ) external payable nonReentrant whenNotPaused returns (uint256 orderId) {
        // Validate inputs
        if (amount == 0) revert InvalidAmount();
        if (bytes(serviceId).length == 0) revert InvalidServiceId();
        if (recipientHash == bytes32(0)) revert InvalidRecipientHash();

        // Validate serviceType is one of the four allowed values
        bytes32 serviceTypeHash = keccak256(bytes(serviceType));
        if (
            serviceTypeHash != _AIRTIME &&
            serviceTypeHash != _DATA &&
            serviceTypeHash != _TV &&
            serviceTypeHash != _ELECTRICITY
        ) revert InvalidServiceType();

        // Collect payment
        if (token == address(0)) {
            if (msg.value != amount) revert IncorrectNativeAmount();
        } else {
            if (IERC20(token).allowance(msg.sender, address(this)) < amount)
                revert InsufficientAllowance();
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        orderId = _billOrderCounter++;

        emit BillPaymentInitiated(
            orderId,
            msg.sender,
            token,
            amount,
            serviceType,
            serviceId,
            recipientHash
        );
    }

    /**
     * @notice Withdraw collected bill payment funds to a given address.
     *         Only callable by accounts with WITHDRAWER_ROLE.
     * @param token  Token to withdraw (address(0) for native)
     * @param to     Recipient address
     * @param amount Amount to withdraw
     */
    function withdrawBillFunds(
        address token,
        address to,
        uint256 amount
    ) external nonReentrant onlyRole(WITHDRAWER_ROLE) {
        if (to == address(0)) revert InvalidRecipient();
        if (amount == 0) revert InvalidAmount();

        if (token == address(0)) {
            if (address(this).balance < amount) revert InsufficientContractBalance();
            emit BillFundsWithdrawn(to, token, amount);
            (bool success, ) = payable(to).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            if (IERC20(token).balanceOf(address(this)) < amount)
                revert InsufficientContractBalance();
            emit BillFundsWithdrawn(to, token, amount);
            IERC20(token).safeTransfer(to, amount);
        }
    }

    /**
     * @notice Recover native tokens accidentally sent directly to the contract
     *         (not via payBill or createVoucherBatch).
     *         Only callable by WITHDRAWER_ROLE.
     */
    function recoverNative(address to, uint256 amount)
        external
        nonReentrant
        onlyRole(WITHDRAWER_ROLE)
    {
        if (to == address(0)) revert InvalidRecipient();
        if (amount == 0) revert InvalidAmount();
        if (address(this).balance < amount) revert InsufficientContractBalance();
        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Allow contract to receive native tokens (ETH/CELO)
     */
    receive() external payable {}
}
