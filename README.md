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
