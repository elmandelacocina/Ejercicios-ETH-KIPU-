// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Dynamic Auction with Extension and Partial Refunds
 * @author Hipolito Alonso
 * @notice This auction contract allows bids with a minimum 5% increase,
 *         extends the auction by 10 minutes if a valid bid is made in the last 10 minutes,
 *         and allows losing bidders to withdraw their balance minus a 2% fee.
 * @dev This version was written before the class on June 5th,
 *      where we discussed various options to optimize the code
 *      and the use of the OpenZeppelin library.
 *      In the next version, which I will submit for the assignment,
 *      the OpenZeppelin import will be properly applied.
 *      Here, I included a custom modifier that, to the best of my understanding,
 *      behaves in a similar way.
 *      As a result of the optimizations, the code was reduced
 *      from approximately 250 lines to around 150 lines.
 */

contract Auctionv2 {
    // @notice Address of the auction owner
    address public immutable owner;

    // @notice Timestamp when the auction starts
    uint256 public immutable startTime;

    // @notice Timestamp of the initial auction end time
    uint256 public immutable initialEndTime;

    // @notice Current end time of the auction (can be extended)
    uint256 public currentEndTime;

    // @notice Address of the highest bidder
    address public highestBidder;

    // @notice Amount of the highest bid
    uint256 public highestBidAmount;

    // @notice Indicates whether the auction has been finalized
    bool public ended;

    // @notice Fee applied to losing bidders upon withdrawal (in basis points)
    uint256 public constant COMMISSION_BPS = 200;

    // @notice Minimum increment required to outbid (in basis points)
    uint256 public constant MIN_INCREMENT_BPS = 500;

    // @notice Time window in which a new bid extends the auction
    uint256 public constant EXTENSION_WINDOW = 10 minutes;

    // @notice Duration by which the auction is extended
    uint256 public constant EXTENSION_DURATION = 10 minutes;

    // @notice Mapping of bidder addresses to their total deposited amount
    mapping(address => uint256) public bidBalances;

    // @notice Array of unique bidder addresses
    address[] public bidders;

    // @notice Mapping to track if an address has been registered as a bidder
    mapping(address => bool) public isBidder;

    // @notice Simple reentrancy guard
    bool private locked;

    // ===========================
    // ========= EVENTS ==========
    // ===========================

    event NewBid(address indexed bidder, uint256 amount, uint256 newEndTime);
    event AuctionEnded(address indexed winner, uint256 amount);
    event WithdrawExcess(address indexed bidder, uint256 amount);
    event WithdrawDeposit(address indexed bidder, uint256 refund, uint256 fee);

    // ===========================
    // ======== MODIFIERS ========
    // ===========================

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can execute");
        _;
    }

    modifier onlyWhileActive() {
        require(block.timestamp >= startTime, "Auction not started");
        require(block.timestamp < currentEndTime, "Auction has ended");
        _;
    }

    modifier onlyAfterEnd() {
        require(block.timestamp > currentEndTime, "Auction is still active");
        require(!ended, "Auction already finalized");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "Reentrancy detected");
        locked = true;
        _;
        locked = false;
    }

    // ===========================
    // ======= CONSTRUCTOR =======
    // ===========================

    // @notice Initializes a new auction
    // @param _duration Duration of the auction in seconds
    constructor(uint256 _duration) {
        require(_duration > 0, "Invalid duration");
        owner = msg.sender;
        startTime = block.timestamp;
        initialEndTime = block.timestamp + _duration;
        currentEndTime = initialEndTime;
    }

    // ===========================
    // ======== BID LOGIC ========
    // ===========================

    // @notice Place a bid exceeding the current highest by at least 5%
    // @dev If bid occurs in final 10 minutes, auction is extended
    function bid() external payable onlyWhileActive {
        require(msg.value > 0, "Must send Ether to bid");

        uint256 newBalance = bidBalances[msg.sender] + msg.value;

        if (highestBidAmount > 0) {
            uint256 minRequired = highestBidAmount + (highestBidAmount * MIN_INCREMENT_BPS) / 10000;
            require(newBalance >= minRequired, "Bid must exceed current by at least 5%");
        }

        // Register bidder only if it's the first time
        if (!isBidder[msg.sender]) {
            isBidder[msg.sender] = true;
            bidders.push(msg.sender);
        }

        bidBalances[msg.sender] = newBalance;
        highestBidAmount = newBalance;
        highestBidder = msg.sender;

        if (block.timestamp >= currentEndTime - EXTENSION_WINDOW) {
            currentEndTime = block.timestamp + EXTENSION_DURATION;
        }

        emit NewBid(msg.sender, newBalance, currentEndTime);
    }

    // @notice Withdraw a portion of your bid during the auction if you're not the highest bidder
    // @param amount Amount to withdraw in wei
    function withdrawExcess(uint256 amount) external onlyWhileActive nonReentrant {
        uint256 balance = bidBalances[msg.sender];
        require(balance > 0, "No funds deposited");
        require(msg.sender != highestBidder, "Winner cannot withdraw");
        require(amount > 0 && amount <= balance, "Invalid withdrawal amount");

        bidBalances[msg.sender] = balance - amount;

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Withdrawal failed");

        emit WithdrawExcess(msg.sender, amount);
    }

    // @notice Finalizes the auction and emits the result
    function finalizeAuction() external onlyAfterEnd {
        ended = true;

        // Optional cleanup
        bidBalances[highestBidder] = 0;

        emit AuctionEnded(highestBidder, highestBidAmount);
    }

    // @notice Allows the owner to claim the winning bid amount after auction ends
    function claimFunds() external onlyOwner nonReentrant {
        require(block.timestamp > currentEndTime, "Auction is still active");

        if (!ended) {
            ended = true;
            emit AuctionEnded(highestBidder, highestBidAmount);
        }

        uint256 amount = highestBidAmount;
        require(amount > 0, "No winning bid to claim");

        highestBidAmount = 0;
        bidBalances[highestBidder] = 0;

        (bool sent, ) = owner.call{value: amount}("");
        require(sent, "Owner withdrawal failed");
    }

    // @notice Allows losing bidders to withdraw their bid minus 2% fee
    function withdrawDeposit() external nonReentrant {
        require(ended, "Auction not finalized");
        require(msg.sender != highestBidder, "Winner cannot withdraw here");

        uint256 amount = bidBalances[msg.sender];
        require(amount > 0, "Nothing to withdraw");

        bidBalances[msg.sender] = 0;

        uint256 fee = (amount * COMMISSION_BPS) / 10000;
        uint256 refund = amount - fee;

        (bool sent, ) = msg.sender.call{value: refund}("");
        require(sent, "Refund failed");

        emit WithdrawDeposit(msg.sender, refund, fee);
    }

    // ===========================
    // ========= VIEWS ==========
    // ===========================

    // @notice Returns all bidders and their respective balances
    // @dev This function may fail if there are too many bidders. Recommended for off-chain use only.
    function showBids() external view returns (address[] memory addresses, uint256[] memory amounts) {
        uint256 len = bidders.length;
        addresses = new address[](len);
        amounts = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            address b = bidders[i];
            addresses[i] = b;
            amounts[i] = bidBalances[b];
        }
    }

    // @notice Returns the current highest bidder and amount
    function showWinner() external view returns (address winner, uint256 amount) {
        return (highestBidder, highestBidAmount);
    }

    // @notice Returns number of unique bidders
    function numBidders() external view returns (uint256 count) {
        return bidders.length;
    }

    // ===========================
    // ========= FALLBACK ========
    // ===========================

    fallback() external payable {
        revert("Use bid()");
    }

    receive() external payable {
        revert("Use bid()");
    }
}
