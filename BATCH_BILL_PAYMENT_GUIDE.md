# Batch Bill Payment Feature Guide

## Overview

The `payBillBatch()` function allows you to buy airtime, data, TV subscriptions, or pay electricity bills for **multiple recipients in ONE transaction**. Perfect for giveaways, promotions, or bulk payments!

## Function Signature

```solidity
function payBillBatch(
    address token,              // Token to pay with (address(0) for native CELO)
    uint256[] calldata amounts, // Array of amounts for each recipient
    string calldata serviceType,// "airtime", "data", "tv", or "electricity"
    string calldata serviceId,  // e.g., "mtn", "airtel", "dstv", "ikedc"
    bytes32[] calldata recipientHashes // Array of hashed phone numbers/IDs
) external payable returns (uint256[] memory orderIds)
```

## Use Cases

### 1. Airtime Giveaway (Multiple Recipients, Same Amount)

```javascript
// Give 100 NGN airtime to 10 people on MTN
const recipients = [
  "2348012345678",
  "2348087654321",
  // ... 8 more numbers
];

// Hash phone numbers client-side (privacy!)
const recipientHashes = recipients.map((phone) =>
  ethers.keccak256(ethers.toUtf8Bytes(phone)),
);

// Each person gets 100 NGN worth of CELO
const amounts = Array(10).fill(ethers.parseEther("0.5")); // 0.5 CELO each

const tx = await gigipayContract.payBillBatch(
  ethers.ZeroAddress, // Native CELO
  amounts,
  "airtime",
  "mtn",
  recipientHashes,
  { value: ethers.parseEther("5.0") }, // Total: 10 × 0.5 = 5 CELO
);

const receipt = await tx.wait();
console.log("Order IDs:", receipt.logs); // Backend will process these
```

### 2. Variable Amounts (Different Amounts per Recipient)

```javascript
// Give different airtime amounts to different people
const recipients = [
  { phone: "2348012345678", amount: "1.0" }, // 1 CELO
  { phone: "2348087654321", amount: "0.5" }, // 0.5 CELO
  { phone: "2348098765432", amount: "2.0" }, // 2 CELO
];

const recipientHashes = recipients.map((r) =>
  ethers.keccak256(ethers.toUtf8Bytes(r.phone)),
);

const amounts = recipients.map((r) => ethers.parseEther(r.amount));
const totalAmount = amounts.reduce((a, b) => a + b, 0n);

const tx = await gigipayContract.payBillBatch(
  ethers.ZeroAddress,
  amounts,
  "airtime",
  "mtn",
  recipientHashes,
  { value: totalAmount }, // Total: 3.5 CELO
);
```

### 3. Using ERC20 Tokens (e.g., cUSD)

```javascript
const cUSD_ADDRESS = "0x765DE816845861e75A25fCA122bb6898B8B1282a"; // Celo Mainnet
const cUSD = new ethers.Contract(cUSD_ADDRESS, ERC20_ABI, signer);

// Approve contract to spend cUSD
const totalAmount = ethers.parseUnits("100", 18); // 100 cUSD
await cUSD.approve(GIGIPAY_ADDRESS, totalAmount);

// Buy airtime for 5 people (20 cUSD each)
const amounts = Array(5).fill(ethers.parseUnits("20", 18));

const tx = await gigipayContract.payBillBatch(
  cUSD_ADDRESS,
  amounts,
  "airtime",
  "mtn",
  recipientHashes,
  // No { value } needed for ERC20
);
```

### 4. Data Bundle Giveaway

```javascript
// Give 1GB data to 20 people
const amounts = Array(20).fill(ethers.parseEther("0.3")); // 0.3 CELO each

const tx = await gigipayContract.payBillBatch(
  ethers.ZeroAddress,
  amounts,
  "data", // Changed to "data"
  "mtn-data", // MTN data service ID
  recipientHashes,
  { value: ethers.parseEther("6.0") }, // 20 × 0.3 = 6 CELO
);
```

## Events Emitted

### Individual Order Events

For each recipient, a `BillPaymentInitiated` event is emitted:

```solidity
event BillPaymentInitiated(
    uint256 indexed orderId,
    address indexed buyer,
    address token,
    uint256 amount,
    string serviceType,
    string serviceId,
    bytes32 recipientHash
);
```

### Batch Summary Event

One `BatchBillPaymentCompleted` event for the entire batch:

```solidity
event BatchBillPaymentCompleted(
    address indexed buyer,
    address indexed token,
    uint256 totalAmount,
    string serviceType,
    uint256 recipientCount
);
```

## Backend Integration

Your backend should listen for `BillPaymentInitiated` events (works for both single and batch):

```typescript
// Listen for all bill payments (single + batch)
gigipayContract.on(
  "BillPaymentInitiated",
  async (
    orderId,
    buyer,
    token,
    amount,
    serviceType,
    serviceId,
    recipientHash,
    event,
  ) => {
    console.log(`Processing order ${orderId}`);

    // Call VTPass API to fulfill the order
    await vtpassService.purchaseAirtime({
      orderId: orderId.toString(),
      serviceId,
      amount: ethers.formatEther(amount),
      // You need to store phone number mapping off-chain
      // or have the user provide it via your API
    });
  },
);

// Optional: Listen for batch completion summary
gigipayContract.on(
  "BatchBillPaymentCompleted",
  (buyer, token, totalAmount, serviceType, recipientCount) => {
    console.log(
      `Batch completed: ${recipientCount} orders, ${ethers.formatEther(totalAmount)} total`,
    );
  },
);
```

## Limits & Validation

- **Max batch size:** 200 recipients (defined by `MAX_BATCH_SIZE`)
- **Service types:** Only `"airtime"`, `"data"`, `"tv"`, `"electricity"`
- **All recipients must use the same:**
  - Token (CELO or cUSD, etc.)
  - Service type (all airtime, or all data, etc.)
  - Service provider (all MTN, or all Airtel, etc.)
- **Amounts can be different** for each recipient

## Gas Optimization Tips

1. **Use native CELO** instead of ERC20 when possible (saves gas on transfers)
2. **Batch size sweet spot:** 20-50 recipients per transaction
3. **Pre-approve tokens** if using ERC20 to avoid separate approval transaction

## Error Handling

```javascript
try {
  const tx = await gigipayContract.payBillBatch(...);
  await tx.wait();
} catch (error) {
  if (error.message.includes("BatchTooLarge")) {
    console.error("Too many recipients! Max 200 per batch");
  } else if (error.message.includes("IncorrectNativeAmount")) {
    console.error("Total amount doesn't match sum of individual amounts");
  } else if (error.message.includes("InsufficientAllowance")) {
    console.error("Need to approve token spending first");
  }
}
```

## Frontend Example (React Hook)

```typescript
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseEther, keccak256, toUtf8Bytes } from "viem";

export function useBatchBillPayment() {
  const { writeContract, data: hash } = useWriteContract();
  const { isLoading, isSuccess } = useWaitForTransactionReceipt({ hash });

  const buyBatchAirtime = async (
    phoneNumbers: string[],
    amounts: string[], // in CELO
    serviceId: string = "mtn",
  ) => {
    // Hash phone numbers for privacy
    const recipientHashes = phoneNumbers.map((phone) =>
      keccak256(toUtf8Bytes(phone)),
    );

    const amountsWei = amounts.map((a) => parseEther(a));
    const totalAmount = amountsWei.reduce((a, b) => a + b, 0n);

    writeContract({
      address: GIGIPAY_ADDRESS,
      abi: GIGIPAY_ABI,
      functionName: "payBillBatch",
      args: [
        "0x0000000000000000000000000000000000000000", // Native CELO
        amountsWei,
        "airtime",
        serviceId,
        recipientHashes,
      ],
      value: totalAmount,
    });
  };

  return { buyBatchAirtime, isLoading, isSuccess };
}
```

## Comparison: Single vs Batch

| Feature      | `payBill()`         | `payBillBatch()`          |
| ------------ | ------------------- | ------------------------- |
| Recipients   | 1                   | Up to 200                 |
| Gas Cost     | ~50k gas            | ~30k + (15k × recipients) |
| Transactions | 1 per recipient     | 1 for all                 |
| Use Case     | Individual purchase | Giveaways, bulk payments  |

**Example:** Buying airtime for 10 people

- **Single:** 10 transactions × 50k gas = 500k gas
- **Batch:** 1 transaction × 180k gas = 180k gas
- **Savings:** 64% less gas! 🎉
