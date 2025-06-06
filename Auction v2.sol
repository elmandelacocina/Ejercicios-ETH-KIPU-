// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Simple Auction with Auto-Extension and Partial Refunds
 * @author Hipolito Alonso
 * @notice Implements a basic ETH auction where users can place bids, 
 *         with auto-extension if a bid is placed in the last 10 minutes, 
 *         and a partial refund mechanism for losing bidders.
 * @dev    This version of the auction implements the OpenZeppelin library 
 *         and features complete code optimization. As we saw in the 5/6 class
 *         we can save a lot of code by effectively utilizing programming logic.
 */

contract AuctionTP is ReentrancyGuard { 
    address public owner; // Owner address
    uint256 public startTime; // Start time in seconds
    uint256 public endTime; // End time in seconds (starts + duration)

    address public highestBidder; // Highest bider address
    uint256 public highestBid; // Highest bider amount
    bool public ended; // Whether the auction ended or not

    mapping(address => uint256) public balances; // Balances of each bidder

    uint256 public constant FEE_PERCENT = 2;            // 2% fee for losers
    uint256 public constant MIN_INCREMENT_PERCENT = 5;  // Bids must be 5% higher
    uint256 public constant EXTEND_TIME = 10 minutes;   // Extend duration
    uint256 public constant EXTEND_WINDOW = 10 minutes; // If bid placed near the end

    event NewBid(address bidder, uint256 amount, uint256 newEndTime); // Event emitted when a new bid is placed
    event AuctionEnded(address winner, uint256 amount); // Event emitted when the auction is ended
    event Withdrawal(address bidder, uint256 refund, uint256 fee); // Event emitted when a bider withdrew ETH and lost fees
    /**
     * @notice Initializes the auction with a specified duration.
     * @dev Sets the auction's start and end time. The owner is set to the deployer.
     * @param durationSeconds Duration of the auction in seconds.
     */

    constructor(uint256 durationSeconds) {
        require(durationSeconds > 0, "Duration must be greater than 0");

        owner = msg.sender; // Sets owner address to caller
        startTime = block.timestamp; // Sets start time to current timestamp
        endTime = block.timestamp + durationSeconds; ///Sets end time to current timestamp + duration seconds
    }
    /**
     * @notice Allows a user to place a bid in the auction.
     * @dev Bids must be at least 5% higher than the current highest bid.
     *      If the bid is placed within the last 10 minutes, the auction is extended.
     *      Bidders can place multiple bids; they are cumulatively added.
     */ 
        function bid() external payable {
        require(block.timestamp >= startTime, "Auction has not started yet"); // Ensure auction is ongoing
        require(block.timestamp < endTime, "Auction has already ended"); // Ensure auction is not ended
        require(msg.value > 0, "Must send ETH to bid"); // Ensure amount is greater than 0

        balances[msg.sender] += msg.value; //  Adds amount to the bids of current address
        uint256 totalBid = balances[msg.sender]; // Adds bids to current address total balance

        if (highestBid > 0) { // Checks if there is an highest bider and checks if it is not
            uint256 minRequired = highestBid + (highestBid * MIN_INCREMENT_PERCENT) / 100; // Calculates minimum required amount
            require(totalBid >= minRequired, "Bid too low"); // Ensures bids are 5% higher than current highest bider
        }

        highestBid = totalBid; // Sets new higest bider
        highestBidder = msg.sender; // Sets new higest bider address

        if (block.timestamp + EXTEND_WINDOW >= endTime) {  // Checks if bids placed near the end for extended auction
            endTime = block.timestamp + EXTEND_TIME; // Sets extended auction end time
        }

        emit NewBid(msg.sender, totalBid, endTime); // Emits new bider
    }
    // Finalizes the auction
    function finalize() external nonReentrant { 
        require(msg.sender == owner, "Only owner can finalize");// Ensures only owner can finalize auction
        require(block.timestamp > endTime, "Auction is still ongoing");// Ensure auction is not ongoing
        require(!ended, "Auction already finalized"); //  Ensures auction is not ended

        ended = true;

        uint256 amount = highestBid; // Sets new amount to be withdrawn
        balances[highestBidder] = 0; // Sets bids of winner to 0

        (bool success, ) = payable(owner).call{value: amount}(""); // Transfers ETH to owner
        require(success, "Transfer to owner failed"); // Ensures transfer to owner is successful

        emit AuctionEnded(highestBidder, amount);
    }
    /**
     * @notice Withdraws the sender's bid minus a 2% fee.
     * @dev Only allowed for losing bidders after the auction has ended.
     *      The fee remains in the contract and is not refunded.
     */

        function withdraw() external nonReentrant {
        require(block.timestamp > endTime, "Auction not finished yet"); // Ensure auction is finished or not ongoing
        require(msg.sender != highestBidder, "Winner cannot withdraw"); // Ensure winner cannot withdraw

        uint256 amount = balances[msg.sender];// Sets amount to be withdrawn
        require(amount > 0, "Nothing to withdraw");// Ensures bids are greater than 0

        balances[msg.sender] = 0;// Sets current bids to 0

        uint256 fee = (amount * FEE_PERCENT) / 100; // Sets fee to 2% of amount
        uint256 refund = amount - fee; // Sets refund to amount - fee

        (bool success, ) = payable(msg.sender).call{value: refund}(""); // Transfers ETH to current address 
        require(success, "Refund failed");// Ensures refund is successful

        emit Withdrawal(msg.sender, refund, fee);
    }

    function getWinner() external view returns (address, uint256) {
        return (highestBidder, highestBid); // Returns winner address and amount
    }

    receive() external payable { 

        revert("Please use the bid() function");
    }

    fallback() external payable { 
        revert("Please use the bid() function");
    }
}
