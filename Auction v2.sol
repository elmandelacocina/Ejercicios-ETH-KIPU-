// SPDX-License-Identifier: MIT
// File: @openzeppelin/contracts/security/ReentrancyGuard.sol


// OpenZeppelin Contracts (last updated v4.9.0) (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }
}

// File: Auction v2.sol


pragma solidity ^0.8.0;


/**
 * @title Simple Auction with Auto-Extension and Partial Refunds
 * @author Hipolito Alonso
 * @notice Implements a basic ETH auction where users can place bids, 
 *         with auto-extension if a bid is placed in the last 10 minutes, 
 *         and a partial refund mechanism for losing bidders.
 * @dev    This version of the auction implements the OpenZeppelin library 
 *         and features complete code optimization. As we saw in the 5/6 class
 *         we can save a lot of code by effectively utilizing programming logic.
 *         Also I hace previus version of this contract, the first that is all in spanish
 *         and the second that has a Reentrancy checker, made it by myself
   
    modifier nonReentrant() {
        require(!locked, "Reentrancy detected");
        locked = true;
        _;
        locked = false;
    }
    This was made before the last meet, when we see how to implement OpenZeppelin

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
