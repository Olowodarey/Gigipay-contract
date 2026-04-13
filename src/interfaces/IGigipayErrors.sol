// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IGigipayErrors
 * @notice Custom errors for the Gigipay payment voucher system
 */
interface IGigipayErrors {
    /// @notice Thrown when trying to access a voucher that doesn't exist
    error VoucherNotFound();
    
    /// @notice Thrown when trying to claim a voucher that has already been claimed
    error VoucherAlreadyClaimed();
    
    /// @notice Thrown when trying to refund a voucher that has already been refunded
    error VoucherAlreadyRefunded();
    
    /// @notice Thrown when trying to refund a voucher that hasn't expired yet
    error VoucherNotExpired();
    
    /// @notice Thrown when trying to claim a voucher that has expired
    error VoucherExpired();
    
    /// @notice Thrown when an invalid claim code is provided
    error InvalidClaimCode();
    
    /// @notice Thrown when an invalid amount is provided (zero or mismatched)
    error InvalidAmount();
    
    /// @notice Thrown when an invalid expiration time is provided
    error InvalidExpirationTime();
    
    /// @notice Thrown when a transfer fails
    error TransferFailed();
    
    // Batch Transfer Errors
    /// @notice Thrown when array lengths don't match
    error LengthMismatch();
    
    /// @notice Thrown when an empty array is provided
    error EmptyArray();
    
    /// @notice Thrown when incorrect native token amount is sent
    error IncorrectNativeAmount();
    
    /// @notice Thrown when insufficient token allowance
    error InsufficientAllowance();
    
    /// @notice Thrown when an invalid recipient address is provided
    error InvalidRecipient();
}
