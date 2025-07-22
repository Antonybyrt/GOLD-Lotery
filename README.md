# Sgold Protocol

## Overview

**Sgold** is an ERC20-based protocol that allows users to mint a gold-pegged stablecoin (Sgold) by depositing Ether. The protocol features an integrated lottery system, where a portion of each deposit funds a prize pool. When a set number of participants is reached, a random winner is selected using Chainlink VRF, and the entire prize pool is awarded in Ether.

---

## Features

- **Gold-Pegged Stablecoin:**  
  Mint Sgold tokens by depositing Ether, with the value calculated using Chainlink Price Feeds for real-time gold pricing in USD.

- **Minting Mechanism:**  
  - Users receive 70% of their deposit value in Sgold (based on the current gold price in USD).
  - 10% of each deposit is allocated to a lottery prize pool.

- **Integrated Lottery:**  
  - When the participant threshold (e.g., 10 users) is reached, the admin can trigger a lottery draw.
  - The winner is selected randomly via Chainlink VRF and receives the entire prize pool in Ether.

- **Redemption:**  
  Users can burn their Sgold tokens to reclaim their Ether collateral.

---

## Architecture

- **Smart Contract:**  
  Handles minting, redemption, lottery pool management, and winner selection.

- **Chainlink Integration:**  
  - **Price Feed:** Fetches the latest gold price in USD for accurate Sgold minting.
  - **VRF (Verifiable Random Function):** Ensures fair and tamper-proof lottery draws.

---

## Getting Started

### Prerequisites

- Foundry
- An Ethereum node provider (e.g., Alchemy, Infura)
- Chainlink testnet contracts access

### Installation

```bash
git clone https://github.com/yourusername/sgold-protocol.git
cd sgold-protocol
forge install
```

### Deployment

1. Configure your environment variables (see `.env.example`).
2. Deploy the contract:

```bash

```

### Testing

- **Local tests:**
  ```bash
  forge test
  ```

---

## Project Structure

- `contracts/` — Sgold smart contract
- `scripts/` — Deployment and lottery scripts
- `test/` — Unit and integration tests

---

## How It Works

1. **Minting Sgold:**
   - User deposits Ether.
   - 70% of the deposit (in USD value of gold) is minted as Sgold.
   - 10% goes to the lottery pool.

2. **Lottery:**
   - When the participant threshold is reached, the admin triggers the draw.
   - Chainlink VRF selects a random winner.
   - Winner receives the Ether prize pool.

3. **Redemption:**
   - Users can burn Sgold to reclaim their Ether, based on the current gold price.

---

## Security

- Uses Chainlink oracles for reliable price feeds and randomness.
- Only the admin can trigger the lottery draw.
- All funds are managed by the smart contract.

---

## License

AGPL-3.0

---

## Acknowledgements

- [Chainlink](https://chain.link/) for decentralized oracles and VRF
- [OpenZeppelin](https://openzeppelin.com/) for secure ERC20 implementation

---

**Happy minting and good luck in the lottery!**
