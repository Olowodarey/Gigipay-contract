// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IGigipayEvents
 * @notice Events emitted by the Gigipay payment voucher system
 */
interface IGigipayEvents {
    /**
     * @notice Emitted when a new voucher is created
     * @param voucherId The unique ID of the voucher
     * @param sender The address that created the voucher
     * @param amount The amount of tokens locked in the voucher
     * @param expiresAt The timestamp when the voucher expires
     */
    event VoucherCreated(
        uint256 indexed voucherId,
        address indexed sender,
        uint256 amount,
        uint256 expiresAt
    );
    
    /**
     * @notice Emitted when a voucher is successfully claimed
     * @param voucherId The unique ID of the voucher
     * @param claimer The address that claimed the voucher
     * @param amount The amount of tokens claimed
     */
    event VoucherClaimed(
        uint256 indexed voucherId,
        address indexed claimer,
        uint256 amount
    );
    
    /**
     * @notice Emitted when a voucher is refunded to the sender
     * @param voucherId The unique ID of the voucher
     * @param sender The address that receives the refund
     * @param amount The amount of tokens refunded
     */
    event VoucherRefunded(
        uint256 indexed voucherId,
        address indexed sender,
        uint256 amount
    );
    
    /**
     * @notice Emitted when a batch transfer is completed
     * @param sender The address that initiated the batch transfer
     * @param token The token address (address(0) for native CELO)
     * @param totalAmount The total amount transferred
     * @param recipientCount The number of recipients
     */
    event BatchTransferCompleted(
        address indexed sender,
        address indexed token,
        uint256 totalAmount,
        uint256 recipientCount
    );

    /**
     * @notice Emitted when a bill payment is initiated (airtime, data, TV, electricity)
     * @param orderId Unique order ID for this payment
     * @param buyer The address that made the payment
     * @param token The token used for payment (address(0) for native)
     * @param amount The amount of tokens paid
     * @param serviceType "airtime" | "data" | "tv" | "electricity"
     * @param serviceId VTPass service identifier e.g. "mtn", "dstv", "ikedc"
     * @param recipientHash keccak256 hash of the recipient identifier (phone/smartcard/meter)
     */
    event BillPaymentInitiated(
        uint256 indexed orderId,
        address indexed buyer,
        address token,
        uint256 amount,
        string serviceType,
        string serviceId,
        bytes32 recipientHash
    );

    /**
     * @notice Emitted when admin withdraws collected bill payment funds
     * @param to Recipient of the withdrawal
     * @param token Token withdrawn (address(0) for native)
     * @param amount Amount withdrawn
     */
    event BillFundsWithdrawn(
        address indexed to,
        address indexed token,
        uint256 amount
    );
}
