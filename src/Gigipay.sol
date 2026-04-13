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

    // Reentrancy guard
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Gas-optimized keccak256 hashing using assembly
     * @param _claimCode The claim code to hash
     * @return result The keccak256 hash of the claim code
     */
    function _hashClaimCode(
        string memory _claimCode
    ) internal pure returns (bytes32 result) {
        bytes memory packed = abi.encodePacked(_claimCode);
        assembly {
            result := keccak256(add(packed, 0x20), mload(packed))
        }
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
        if (_status == _ENTERED) revert TransferFailed(); // Reusing error for reentrancy
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
    }

    /**
     * @notice Create multiple payment vouchers under ONE voucher name (gas efficient!)
     * @param voucherName The shared name for all vouchers (e.g., "december2024")
     * @param claimCodes Array of secret codes for each voucher
     * @param amounts Array of amounts for each voucher
     * @param expirationTimes Array of expiration timestamps for each voucher
     * @return voucherIds Array of created voucher IDs
     */
    function createVoucherBatch(
        address token,
        string memory voucherName,
        string[] memory claimCodes,
        uint256[] memory amounts,
        uint256[] memory expirationTimes
    ) public payable whenNotPaused returns (uint256[] memory) {
        uint256 length = claimCodes.length;
        if (length != amounts.length || length != expirationTimes.length) {
            revert InvalidAmount();
        }
        if (bytes(voucherName).length == 0) revert InvalidClaimCode();

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < length; i++) {
            totalAmount += amounts[i];
        }

        if (token == address(0)) {
            if (msg.value != totalAmount) revert InvalidAmount();
        } else {
            IERC20 tokenContract = IERC20(token);
            if (
                tokenContract.allowance(msg.sender, address(this)) < totalAmount
            ) {
                revert InsufficientAllowance();
            }

            tokenContract.safeTransferFrom(
                msg.sender,
                address(this),
                totalAmount
            );
        }

        bytes32 voucherNameHash = keccak256(abi.encodePacked(voucherName));
        uint256[] memory voucherIds = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            if (amounts[i] == 0) revert InvalidAmount();
            if (expirationTimes[i] <= block.timestamp)
                revert InvalidExpirationTime();
            if (bytes(claimCodes[i]).length == 0) revert InvalidClaimCode();

            uint256 voucherId = _voucherIdCounter++;
            bytes32 claimCodeHash = _hashClaimCode(claimCodes[i]);

            vouchers[voucherId] = PaymentVoucher({
                sender: msg.sender,
                token: token,
                amount: amounts[i],
                claimCodeHash: claimCodeHash,
                expiresAt: expirationTimes[i],
                claimed: false,
                refunded: false,
                voucherName: voucherName
            });

            senderVouchers[msg.sender].push(voucherId);
            voucherNameToIds[voucherNameHash].push(voucherId);
            voucherIds[i] = voucherId;

            emit VoucherCreated(
                voucherId,
                msg.sender,
                amounts[i],
                expirationTimes[i]
            );
        }

        voucherNameExists[voucherNameHash] = true;
        return voucherIds;
    }

    /**
     * @notice Claim a payment voucher using voucher name and claim code
     * @param voucherName The name of the voucher campaign (e.g., "Birthday2024")
     * @param claimCode The secret code to unlock the voucher
     */
    function claimVoucher(
        string memory voucherName,
        string memory claimCode
    ) public whenNotPaused {
        bytes32 voucherNameHash = keccak256(abi.encodePacked(voucherName));
        uint256[] memory voucherIds = voucherNameToIds[voucherNameHash];

        if (voucherIds.length == 0) revert VoucherNotFound();

        bytes32 providedCodeHash = _hashClaimCode(claimCode);

        // Find the voucher with matching claim code
        for (uint256 i = 0; i < voucherIds.length; i++) {
            PaymentVoucher storage voucher = vouchers[voucherIds[i]];

            // Skip if already claimed or refunded
            if (voucher.claimed || voucher.refunded) continue;

            // Check if claim code matches
            if (providedCodeHash == voucher.claimCodeHash) {
                // Check if expired
                if (block.timestamp > voucher.expiresAt)
                    revert VoucherExpired();

                // Mark as claimed
                voucher.claimed = true;

                // Transfer funds based on token type
                if (voucher.token == address(0)) {
                    // Native token transfer
                    (bool success, ) = payable(msg.sender).call{
                        value: voucher.amount
                    }("");
                    if (!success) revert TransferFailed();
                } else {
                    // ERC20 token transfer
                    IERC20(voucher.token).safeTransfer(
                        msg.sender,
                        voucher.amount
                    );
                }

                emit VoucherClaimed(voucherIds[i], msg.sender, voucher.amount);
                return;
            }
        }

        // If we get here, no matching unclaimed voucher was found
        revert InvalidClaimCode();
    }

    /**
     * @notice Refund all expired vouchers under a voucher name back to the sender
     * @param voucherName The name of the voucher campaign to refund
     * @return refundedCount Number of vouchers successfully refunded
     */
    function refundVouchersByName(
        string memory voucherName
    ) public whenNotPaused returns (uint256) {
        bytes32 voucherNameHash = keccak256(abi.encodePacked(voucherName));
        uint256[] memory voucherIds = voucherNameToIds[voucherNameHash];

        if (voucherIds.length == 0) revert VoucherNotFound();

        uint256 refundedCount = 0;
        uint256 totalRefundAmount = 0;
        address tokenToRefund = address(0);
        bool isFirstRefund = true;

        // Loop through all vouchers under this name
        for (uint256 i = 0; i < voucherIds.length; i++) {
            PaymentVoucher storage voucher = vouchers[voucherIds[i]];

            // Skip if already claimed or refunded
            if (voucher.claimed || voucher.refunded) continue;

            // Skip if not expired yet
            if (block.timestamp <= voucher.expiresAt) continue;

            // Only the original sender can refund
            if (msg.sender != voucher.sender) continue;

            // Store token type from first refundable voucher
            if (isFirstRefund) {
                tokenToRefund = voucher.token;
                isFirstRefund = false;
            }

            // All vouchers under same name should use same token
            if (voucher.token != tokenToRefund) continue;

            // Mark as refunded
            voucher.refunded = true;
            totalRefundAmount += voucher.amount;
            refundedCount++;

            emit VoucherRefunded(voucherIds[i], voucher.sender, voucher.amount);
        }

        // Revert if no vouchers were refunded
        if (refundedCount == 0) revert VoucherNotExpired(); // No refundable vouchers found

        // Transfer total refund amount based on token type
        if (tokenToRefund == address(0)) {
            // Native token refund
            (bool success, ) = payable(msg.sender).call{
                value: totalRefundAmount
            }("");
            if (!success) revert TransferFailed();
        } else {
            // ERC20 token refund
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
