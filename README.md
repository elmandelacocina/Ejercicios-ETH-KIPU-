# Simple Auction with Auto-Extension and Partial Refunds

### Author: Hipolito Alonso  
### Date: June 2025  
### Solidity Version: ^0.8.20

---

## 📋 Description

This smart contract implements a simple auction mechanism where users can place ETH bids.  
If a new bid is placed within the final 10 minutes of the auction, the end time is automatically extended by another 10 minutes.

Losing bidders may withdraw their funds with a 2% fee.  
Only the highest bidder wins, and the owner can claim the winning bid after the auction ends.

---

## ⚙️ Features

- Minimum bid increase: **5%**
- Auto-extension window: **10 minutes**
- Fee on refunds: **2%**
- Reentrancy protection via OpenZeppelin's `ReentrancyGuard`
- Custom modifiers for access and auction state checks
- Events for external indexing: `NewBid`, `AuctionEnded`, `Withdrawal`

---

## 🏗️ Deployment

The contract is deployed by calling the constructor with the auction duration in seconds.

Example:

```solidity
new Auction(3600); // 1-hour auction
```

The auction duration is specified in seconds. Once deployed, bidders can start placing bids immediately.
