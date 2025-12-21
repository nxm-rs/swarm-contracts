# Swarm Smart Contracts

Unified Solidity contracts for Ethereum Swarm, combining the storage incentives and swap payment channel systems.

## Overview

This repository contains:

- **Incentives Contracts** - Storage incentive mechanisms including postage stamps, staking, and redistribution
- **Swap Contracts** - Payment channel (chequebook) contracts for the SWAP protocol

## Dependencies

- [Solady](https://github.com/Vectorized/solady) - Gas-optimized Solidity utilities

## Building

```shell
forge build
```

## Testing

```shell
forge test
```

## Contract Structure

```
src/
├── common/           # Shared contracts
│   └── TestToken.sol # Test ERC20 token
├── incentives/       # Storage incentive contracts
│   ├── PostageStamp.sol
│   ├── Staking.sol
│   ├── Redistribution.sol
│   ├── StoragePriceOracle.sol
│   ├── interfaces/
│   └── libraries/
└── swap/             # Payment channel contracts
    ├── ERC20SimpleSwap.sol
    ├── SimpleSwapFactory.sol
    └── SwapPriceOracle.sol
```

## License

BSD-3-Clause
