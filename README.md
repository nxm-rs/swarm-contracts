# Swarm Smart Contracts

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.30-363636.svg)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)

Unified Solidity smart contracts for [Ethereum Swarm](https://www.ethswarm.org/), combining storage incentives and swap payment channels.

## Contracts

- **Incentives** - Postage stamps, staking, redistribution (Schelling game), and storage pricing
- **Swap** - Payment channel (chequebook) contracts for the SWAP protocol

## Quick Start

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Clone and build
git clone https://github.com/nxm-rs/swarm-contracts.git
cd swarm-contracts
forge install && forge build

# Run tests
forge test
```

## Project Structure

```
src/
├── incentives/          # Storage incentive contracts
│   ├── PostageStamp.sol
│   ├── Staking.sol
│   ├── Redistribution.sol
│   └── StoragePriceOracle.sol
└── swap/                # Payment channel contracts
    ├── ERC20SimpleSwap.sol
    ├── SimpleSwapFactory.sol
    └── SwapPriceOracle.sol
```

## Deployment

```bash
# Local
anvil &
forge script script/DeployAll.s.sol --rpc-url localhost --broadcast

# Testnet/Mainnet
forge script script/DeployAll.s.sol --rpc-url $RPC_URL --broadcast --verify
```

## Dependencies

- [Solady](https://github.com/Vectorized/solady) - Gas-optimized utilities

## Related

- [Swarm Docs](https://docs.ethswarm.org/)
- [Bee Node](https://github.com/ethersphere/bee)

## License

[AGPL-3.0-or-later](LICENSE)
