## Defi StableCoin
### Features
- Relative Stability - Anchored or Pegged -> $1
  - Price Feed -> Chainlik Price Feed
  - Oracle -> Chainlink Oracle
  - FUnction to exchange ETH and BTC to $$$
- Stablility Mechanism for Minting - Algortihmic -> Decentralised Stablecoin (No centralised entity)
  - People can mint stablecoin only with enough collateral
- Collateral Type - Exogenous (Crypto)
  - wETH
  - wBTC

- Invariants - properties in the system that should always hold!

### Properties
- **Price Feed** - Chainlink Price Feed
- **Oracle** - Chainlink Oracle
- **Stability Mechanism** - Algorithmic
- **Minting** - Collateralized
- **Collateral** - Exogeneous (Crypto)
- **Exogenous** - wETH, wBTC
- **Invariants** - Price of stablecoin should be $1 and collateral value should always be 2x greater than the minted DSC.

### Caveats
- If the price of collateral assets collapses too quickly, the protocol becomes insolvent.
- If the price of collateral assets doensn't get updated within threshold, the procol becomes unusable.

# Notes
- **Stablecoin** - A cryptocurrency that is pegged to a stable asset, such as gold or the US dollar. Stablecoins are designed to minimize the volatility of the price of the stablecoin, relative to some "stable" asset or basket of assets.
- **Pegged** - A pegged currency is a currency that is tied to another currency or asset, or a basket of currencies or assets, at a fixed rate.
- **Anchored** - Anchored currency is a currency that is pegged to a stable asset, such as gold or the US dollar. Stablecoins are designed to minimize the volatility of the price of the stablecoin, relative to some "stable" asset or basket of assets.
- **Price Feed** - A price feed is a data feed that provides the latest price of an asset or commodity. Price feeds are used by traders, investors, and other market participants to make informed decisions about buying or selling assets.
- **Oracle** - An oracle is a data feed that provides information about the state of the world, such as the price of an asset or the outcome of an event. Oracles are used in decentralized finance (DeFi) to provide external data to smart contracts on the blockchain.
- **Stability Mechanism** - A stability mechanism is a mechanism that is designed to stabilize the price of an asset or currency. Stability mechanisms are used in decentralized finance (DeFi) to maintain the value of stablecoins and other assets.
- **Minting** - Minting is the process of creating new coins or tokens. Minting is used in decentralized finance (DeFi) to create new stablecoins and other assets.
- **Collateral** - Collateral is an asset that is used to secure a loan or other financial transaction. Collateral is used in decentralized finance (DeFi) to back stablecoins and other assets.
- **Exogenous** - Exogenous variables are variables that are determined outside of the system being studied. Exogenous variables are used in decentralized finance (DeFi) to model external factors that can affect the value of assets and currencies.
- **Invariants** - Invariants are properties in the system that should always hold. Invariants are used in decentralized finance (DeFi) to ensure that the system is functioning correctly and that assets are secure.
- **Properties** - Properties are characteristics or attributes of an object or system. Properties are used in decentralized finance (DeFi) to describe the behavior of smart contracts and other components of the system.
- **Decentralised Stablecoin** - A decentralized stablecoin is a stablecoin that is not controlled by a central authority. Decentralized stablecoins are used in decentralized finance (DeFi) to provide a stable store of value that is not subject to the control of a single entity.


## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
