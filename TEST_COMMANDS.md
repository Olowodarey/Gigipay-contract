# Test Commands Quick Reference

## Run All Tests

```bash
cd contracts
forge test
```

## Run Specific Test Suite

### Bill Payment Tests (Withdrawal Protection + Batch)

```bash
forge test --match-path test/BillPaymentTest.sol -vv
```

### Single Bill Payment Tests

```bash
forge test --match-path test/billpayment.sol -vv
```

### Batch Transfer Tests

```bash
forge test --match-path test/batchtest.sol -vv
```

### Voucher Tests

```bash
forge test --match-path test/codepayment.sol -vv
```

## Run Specific Test

### Test Withdrawal Protection

```bash
forge test --match-test test_WithdrawOnlyBillFunds_NotVoucherFunds -vvv
```

### Test Batch Payment

```bash
forge test --match-test test_BatchBillPayment_Success -vvv
```

### Test Large Giveaway (50 recipients)

```bash
forge test --match-test test_BatchBillPayment_LargeGiveaway -vvv
```

### Test Mixed Funds Scenario

```bash
forge test --match-test test_Integration_MixedFunds -vvv
```

## Verbose Levels

- `-v`: Basic test results
- `-vv`: Show logs
- `-vvv`: Show stack traces
- `-vvvv`: Show setup traces
- `-vvvvv`: Show all traces

## Gas Reports

```bash
# Gas report for all tests
forge test --gas-report

# Gas report for specific test
forge test --match-path test/BillPaymentTest.sol --gas-report
```

## Coverage

```bash
# Generate coverage report
forge coverage

# Coverage for specific file
forge coverage --match-path test/BillPaymentTest.sol
```

## Watch Mode (Auto-rerun on changes)

```bash
forge test --watch
```

## Run Tests on Specific Fork

```bash
# Fork Celo mainnet
forge test --fork-url https://forno.celo.org

# Fork Alfajores testnet
forge test --fork-url https://alfajores-forno.celo-testnet.org
```

## Debug Specific Test

```bash
forge test --match-test test_WithdrawOnlyBillFunds_NotVoucherFunds --debug
```

## Snapshot (Save gas baseline)

```bash
forge snapshot
```

## Compare Gas Changes

```bash
# Save current gas usage
forge snapshot

# Make changes to contract

# Compare
forge snapshot --diff
```

## Test with Different Optimizer Runs

```bash
forge test --optimizer-runs 200
forge test --optimizer-runs 1000
forge test --optimizer-runs 10000
```

## Quick Test Commands

### Before Committing

```bash
forge test && forge fmt --check
```

### Full CI Pipeline

```bash
forge fmt --check && forge test --gas-report && forge coverage
```

### Test Only Changed Files

```bash
forge test --match-path test/BillPaymentTest.sol -vv
```

## Useful Flags

- `--match-test <PATTERN>`: Run tests matching pattern
- `--match-path <PATH>`: Run tests in specific file
- `--match-contract <NAME>`: Run tests in specific contract
- `--no-match-test <PATTERN>`: Skip tests matching pattern
- `--gas-report`: Show gas usage
- `--coverage`: Show code coverage
- `--watch`: Auto-rerun on changes
- `--fork-url <URL>`: Run on forked network
- `--debug`: Interactive debugger

## Examples

### Test withdrawal protection thoroughly

```bash
forge test --match-test "test_Withdraw" -vvv --gas-report
```

### Test all batch functionality

```bash
forge test --match-test "test_Batch" -vv
```

### Test all error cases

```bash
forge test --match-test "Revert" -vv
```

### Test integration scenarios

```bash
forge test --match-test "test_Integration" -vvv
```

## CI/CD Commands

### GitHub Actions

```yaml
- name: Run tests
  run: forge test --gas-report

- name: Check coverage
  run: forge coverage --report lcov
```

### Pre-commit Hook

```bash
#!/bin/bash
cd contracts
forge test || exit 1
forge fmt --check || exit 1
```

## Troubleshooting

### Tests failing after changes?

```bash
# Clean and rebuild
forge clean
forge build
forge test
```

### Need more details?

```bash
# Maximum verbosity
forge test --match-test <TEST_NAME> -vvvvv
```

### Gas too high?

```bash
# Compare with snapshot
forge snapshot --diff
```

### Coverage not showing?

```bash
# Generate detailed coverage
forge coverage --report lcov
genhtml lcov.info -o coverage
open coverage/index.html
```
