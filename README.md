# `PROJECT NAME`

## Getting Started

Recommended Node version is 16.0.0.

```bash
$ yarn
$ yarn compile
$ yarn testf
```

## Project Structure

This a hardhat typescript project with `hardhat-deploy` extension.
Solidity version `0.8.15` `CHECK COMPILER VERSION`

### Tests

Tests are found in the `./test/` folder.

To run tests

```bash
$ yarn testf
```

To run coverage

```bash
$ yarn coverage
```

### Contracts

Solidity smart contracts are found in `./contracts/`.
`./contracts/mock` folder contains contracts mocks that are used for testing purposes.

### Deploy

Deploy script can be found in the `./deploy/localhost` for local testing and `./deploy/mainnet` for mainnet deploy

Generate `.env` file

```bash
$ cp .env.example .env
```

Add .env file to the project root.

To add the private key of a deployer account, assign the following variable

```
PRIVATE_TEST=
PRIVATE_MAIN=
```

To add API Keys for verifying

```
API_ETH=
API_BSC=
API_POLYGON=
API_AVAX=
API_FTM=
API_ARBITRUM=
```

To deploy contracts on `CHAINNAME chain`

`PASTE YOUR DEPLOY INSTRUCTION`

```bash
$ yarn deploy --network CHAINNAME_mainnet
```

### Deployments

Deployments on mainnets and testnets are stored in `./deployments`

### Verify

To verify contracts on `CHAINNAME chain`

```bash
$ yarn verify --network CHAINNAME_mainnet
```

### Setup

`DESCRIBE SETUP FUNCTIONS`

## Test Coverage

`PASTE COVERAGE CONSOLE OUTPUT`
```text
```

Contracts in contracts/mock/ will not be deployed to mainnet so they are not tested.

## Technical Requirements

The technical requirement document describes the product's functionality and purpose.
It can be found [here](`PASTE DOCS LINK`).

## Implementation Details

### Audit scope

The following files contain code that will be deployed on mainnet and thus require a security audit:

`LIST CONTRACTS FOR AUDIT`

### Architecture

`DESCRIBE CONTRACTS SYSTEM`

### Role Model

`DESCRIBE ROLE MODEL`

### Backend

`SPECIFY BACKEND INFO`

### Usage Scenarios

Below are detailed step-by-step usage scenarios. They may duplicate the ones described in the technical requirement document, but they are written with much more detail, i.e. who calls what function with what parameters, and where do these parameters come from.

#### Scenario 1

#### Scenario 2


