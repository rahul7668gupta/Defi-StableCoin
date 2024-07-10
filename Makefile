-include .env

install:;
	forge install OpenZeppelin/openzeppelin-contracts@v5.0.2 --no-commit &&
	forge install --no-commit smartcontractkit/chainlink-brownie-contracts@1.1.1