# Lending & Borrowing Protocol

A decentralized lending and borrowing protocol built on Ethereum that allows users to deposit tokens to earn interest and borrow tokens against their deposited collateral. The protocol includes advanced features such as gasless operations via off-chain signatures, liquidation mechanisms, and comprehensive collateralization management.

## Features

### Core Functionality

- **Deposit & Earn**: Users can deposit supported tokens to earn interest based on supply rates
- **Borrow Against Collateral**: Users can borrow tokens using their deposited assets as collateral
- **Repay Loans**: Borrowers can repay their loans at any time
- **Withdraw Deposits**: Users can withdraw their deposits while maintaining safe collateralization ratios

### Advanced Features

- **Gasless Operations**: Deposit tokens using off-chain signatures for improved UX
- **Liquidation System**: Undercollateralized positions can be liquidated with a penalty
- **Multi-Token Support**: Support for multiple ERC20 tokens as collateral and borrowable assets
- **Dynamic Interest Rates**: Configurable supply and borrow rates per market
- **Collateral Factors**: Different collateral factors per token for risk management
- **Emergency Controls**: Pausable functionality for emergency situations

### Security Features

- **Reentrancy Protection**: Uses OpenZeppelin's ReentrancyGuard
- **Safe Token Transfers**: Uses SafeERC20 for secure token operations
- **Access Control**: Ownable pattern for administrative functions
- **Collateralization Checks**: Prevents unsafe withdrawals and borrows

## Architecture

### Contracts

#### LendingProtocol.sol

The main protocol contract that handles all lending and borrowing operations.

**Key Components:**

- **User Management**: Tracks user deposits, borrows, and positions
- **Market Management**: Manages multiple token markets with individual parameters
- **Signature Verification**: Enables gasless operations using ECDSA signatures
- **Liquidation Engine**: Handles liquidations of undercollateralized positions

**Key Parameters:**

- `LIQUIDATION_THRESHOLD`: 80% (8000 basis points) - Position becomes liquidatable below this ratio
- `LIQUIDATION_PENALTY`: 5% (500 basis points) - Penalty applied during liquidation
- `BASIS_POINTS`: 10000 - Used for percentage calculations

#### MockToken.sol

A simple ERC20 token contract for testing purposes. Includes minting and burning functionality.

## Installation

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- Solidity ^0.8.30

### Setup

1. Clone the repository:

```bash
git clone <repository-url>
cd lending-borrowing
```

2. Install dependencies:

```bash
forge install
```

3. Build the contracts:

```bash
forge build
```

## Usage

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Format

```bash
forge fmt
```

### Gas Snapshots

```bash
forge snapshot
```

### Deploy

```bash
forge script script/Deploy.s.sol:DeployScript --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```

## Protocol Functions

### Market Management (Owner Only)

#### Add Market

```solidity
function addMarket(
    address token,
    uint256 collateralFactor,  // 0-10000 (0-100%)
    uint256 initialSupplyRate, // APY in basis points
    uint256 initialBorrowRate  // APY in basis points
)
```

#### Update Market

```solidity
function updateMarket(
    address token,
    uint256 collateralFactor,
    uint256 supplyRate,
    uint256 borrowRate
)
```

### User Operations

#### Deposit

```solidity
function deposit(address token, uint256 amount)
```

#### Withdraw

```solidity
function withdraw(address token, uint256 amount)
```

#### Borrow

```solidity
function borrow(address token, uint256 amount)
```

#### Repay

```solidity
function repay(address token, uint256 amount)
```

#### Gasless Deposit (with Signature)

```solidity
function depositWithSignature(
    address token,
    uint256 amount,
    SignatureData calldata sigData
)
```

### Liquidation

#### Liquidate Position

```solidity
function liquidate(
    address user,
    address token,
    uint256 amount
)
```

Liquidators can liquidate undercollateralized positions and receive collateral tokens with a 5% bonus.

### View Functions

- `getCollateralizationRatio(address user)`: Get user's current collateralization ratio
- `canWithdraw(address user, address token, uint256 amount)`: Check if withdrawal is safe
- `canBorrow(address user, address token, uint256 amount)`: Check if borrow is allowed
- `isLiquidatable(address user)`: Check if position can be liquidated
- `getMarket(address token)`: Get market information
- `getUser(address user)`: Get user information
- `getUserDeposit(address user, address token)`: Get user's deposit for a token
- `getUserBorrow(address user, address token)`: Get user's borrow for a token
- `getSupportedTokens()`: Get all supported token addresses
- `getNonce(address user)`: Get user's nonce for signature verification

## How It Works

### Collateralization Ratio

The protocol uses a collateralization ratio to ensure positions remain safe:

```
Collateralization Ratio = (Total Collateral Value × Collateral Factor) / Total Borrow Value
```

- Positions with a ratio below 80% can be liquidated
- Users cannot withdraw or borrow if it would bring their ratio below 80%

### Interest Rates

Each market has configurable:

- **Supply Rate**: Interest earned by depositors (APY in basis points)
- **Borrow Rate**: Interest paid by borrowers (APY in basis points)

### Liquidation

When a position's collateralization ratio falls below 80%:

1. Anyone can liquidate the position
2. Liquidator repays the borrowed amount
3. Liquidator receives collateral worth `(borrowed amount × 1.05)` (5% bonus)
4. The excess collateral is seized from the borrower

### Gasless Operations

Users can perform deposits without paying gas by:

1. Signing a message off-chain containing deposit details
2. A relayer submits the transaction with the signature
3. The protocol verifies the signature and processes the deposit

## Security Considerations

- **Reentrancy Protection**: All state-changing functions are protected against reentrancy attacks
- **Safe Math**: Uses Solidity 0.8.30's built-in overflow protection
- **Access Control**: Critical functions are restricted to the owner
- **Pausable**: Protocol can be paused in emergency situations
- **Collateral Checks**: Prevents unsafe operations that would make positions liquidatable

## Events

The protocol emits the following events:

- `MarketAdded`: When a new market is added
- `MarketUpdated`: When market parameters are updated
- `Deposit`: When tokens are deposited
- `Withdraw`: When tokens are withdrawn
- `Borrow`: When tokens are borrowed
- `Repay`: When tokens are repaid
- `Liquidate`: When a position is liquidated
- `RatesUpdated`: When interest rates are updated

## Dependencies

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts): Security-focused smart contract library
- [Forge Std](https://github.com/foundry-rs/forge-std): Foundry standard library

## License

MIT

## Contributing

Contributions are welcome! Please ensure all tests pass and code is properly formatted before submitting pull requests.

## Disclaimer

This is a protocol for educational purposes. Use at your own risk. Always conduct thorough security audits before deploying to mainnet.
