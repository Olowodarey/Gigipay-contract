# Gigipay Smart Contracts

Solidity contracts powering the Gigipay protocol, deployed on **Celo** and **Base**. Built with Foundry.

## Deployed Addresses

| Network      | Address                                      |
| ------------ | -------------------------------------------- |
| Celo Mainnet | `0x70b92a67F391F674aFFfCE3Dd7EB3d99e1f1E9a8` |
| Base Mainnet | `0xEdc6abb2f1A25A191dAf8B648c1A3686EfFE6Dd6` |

## What the contract does

The `Gigipay.sol` contract is a single upgradeable contract (UUPS proxy) that handles three features:

**1. Payment Vouchers**
Create a voucher campaign with a name and secret claim codes. Recipients claim funds using the voucher name + their unique code. Supports ERC20 tokens and native CELO/ETH. Expired unclaimed vouchers can be refunded to the sender.

**2. Batch Transfer**
Send tokens to multiple recipients in one transaction. Supports native tokens and any ERC20. Gas-efficient for payroll and bulk payouts.

**3. Bill Payments (Airtime, Data, TV, Electricity)**
Users pay crypto into the contract for Nigerian utility services. The contract emits a `BillPaymentInitiated` event which the backend listens to and fulfils via the ClubKonnect API. Supports all tokens. Collected funds are withdrawable by the admin via `withdrawBillFunds`.

## Roles

| Role                 | What it can do                        |
| -------------------- | ------------------------------------- |
| `DEFAULT_ADMIN_ROLE` | Grant/revoke all roles                |
| `PAUSER_ROLE`        | Pause and unpause the contract        |
| `WITHDRAWER_ROLE`    | Withdraw collected bill payment funds |

## Project Structure

```
contracts/
├── src/
│   ├── Gigipay.sol                  # Main contract
│   └── interfaces/
│       ├── IGigipayEvents.sol       # All events
│       └── IGigipayErrors.sol       # All custom errors
├── script/
│   └── DeployGigipay.s.sol          # Deployment script
├── test/
│   ├── batchtest.sol                # Batch transfer tests
│   ├── codepayment.sol              # Voucher tests
│   └── billpayment.sol              # Bill payment tests
├── lib/                             # Dependencies (forge-std, openzeppelin)
├── foundry.toml                     # Foundry config
├── deploy-mainnet.sh                # Celo mainnet deploy script
└── deploy-base-mainnet.sh           # Base mainnet deploy script
```

## Setup

Install Foundry if you haven't:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Install dependencies:

```bash
forge install
```

## Build

```bash
forge build
```

## Test

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path test/billpayment.sol -v

# Run with gas report
forge test --gas-report
```

## Deploy

Copy the example env and fill in your values:

```bash
cp .env.example .env
```

Required `.env` variables:

```bash
PRIVATE_KEY=           # Deployer wallet private key (needs CELO for gas)
DEFAULT_ADMIN=         # Admin wallet address (gets DEFAULT_ADMIN + WITHDRAWER roles)
PAUSER=                # Pauser wallet address
ETHERSCAN_API_KEY=     # Celoscan API key for verification (optional)
CELO_RPC_URL=          # RPC endpoint (defaults to https://rpc.ankr.com/celo)
```

Deploy to Celo mainnet:

```bash
./deploy-mainnet.sh
```

Deploy to Base mainnet:

```bash
./deploy-base-mainnet.sh
```

After deploying, update the contract address in:

- `Gigipay/apps/web/.env.local` — `NEXT_PUBLIC_CONTRACT_ADDRESS_CELO`
- `Gigipay-backend/src/blockchain/blockchain.service.ts` — `CONTRACT_ADDRESSES`

## Contract Events

| Event                    | Emitted when                                          |
| ------------------------ | ----------------------------------------------------- |
| `VoucherCreated`         | A voucher batch is created                            |
| `VoucherClaimed`         | A voucher is claimed                                  |
| `VoucherRefunded`        | An expired voucher is refunded                        |
| `BatchTransferCompleted` | A batch transfer finishes                             |
| `BillPaymentInitiated`   | A bill payment is submitted (backend listens to this) |
| `BillFundsWithdrawn`     | Admin withdraws collected bill funds                  |

## Security Notes

- Never commit your `.env` file
- The private key in `.env` should only hold enough CELO for deployment gas
- Use a hardware wallet or multisig for `DEFAULT_ADMIN` on mainnet
- The contract is upgradeable — only the `DEFAULT_ADMIN` can upgrade
