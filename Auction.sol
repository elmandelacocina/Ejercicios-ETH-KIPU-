// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Dynamic Auction with Extension and Partial Refunds
/// @author Hipolito Alonso polinux@gmail.com
/// @notice This contract allows an auction in which each new bid exceeding the previous one by at least 5% 
///         extends the auction if placed within the last 10 minutes. Losing bidders can withdraw their deposits 
///         minus a 2% fee. The owner can claim the winning bid funds once the auction is finalized.
/// @dev Security patterns such as a reentrancy guard (nonReentrant) and immutable/constant variables are used 
///      for gas savings.
contract Auction {
    /// @notice Address of the auction owner
    address public immutable owner;

    /// @notice Timestamp when the auction starts
    uint256 public immutable startTime;

    /// @notice Timestamp of the initial auction end time
    uint256 public immutable initialEndTime;

    /// @notice Timestamp of the current auction end time (updates if extended)
    uint256 public currentEndTime;

    /// @notice Address of the highest bidder
    address public highestBidder;

    /// @notice Amount of the highest bid in wei
    uint256 public highestBidAmount;

    /// @notice Indicates whether the auction has been finalized
    bool public ended;

    /// @notice Fee applied to losing bidders when they withdraw (in basis points). 200 = 2%
    uint256 public constant COMMISSION_BPS = 200;

    /// @notice Minimum increment required to outbid the current highest bid (5% = 500 basis points)
    uint256 public constant MIN_INCREMENT_BPS = 500;

    /// @notice Time window (last 10 minutes) during which a new bid extends the auction
    uint256 public constant EXTENSION_WINDOW = 10 minutes;

    /// @notice Duration by which the auction is extended if a valid bid arrives within EXTENSION_WINDOW
    uint256 public constant EXTENSION_DURATION = 10 minutes;

    /// @notice Mapping of each address to its total deposited amount (bid balance)
    mapping(address => uint256) public bidBalances;

    /// @notice List of unique bidder addresses
    address[] public bidders;

    /// @notice Simple reentrancy guard
    bool private locked;

    // ===========================
    // ======== EVENTS ===========
    // ===========================

    /// @notice Emitted when a new valid bid is placed
    /// @param bidder Address of the bidder
    /// @param amount New total bid amount for this bidder
    /// @param newEndTime Updated auction end time
    event NewBid(address indexed bidder, uint256 amount, uint256 newEndTime);

    /// @notice Emitted when the auction is finalized
    /// @param winner Address of the highest bidder
    /// @param amount Winning bid amount
    event AuctionEnded(address indexed winner, uint256 amount);

    /// @notice Emitted when a bidder withdraws excess funds during the auction
    /// @param bidder Address of the bidder
    /// @param amount Amount withdrawn
    event WithdrawExcess(address indexed bidder, uint256 amount);

    /// @notice Emitted when a losing bidder withdraws their deposit after auction end
    /// @param bidder Address of the bidder
    /// @param refund Amount refunded to the bidder
    /// @param fee Fee deducted (2%)
    event WithdrawDeposit(address indexed bidder, uint256 refund, uint256 fee);

    // ===========================
    // ======== MODIFIERS ========
    // ===========================

    /// @notice Restricts function to be called only by the owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can execute");
        _;
    }

    /// @notice Restricts function to be called only while the auction is active
    modifier onlyWhileActive() {
        require(block.timestamp >= startTime, "Auction not started");
        require(block.timestamp <= currentEndTime, "Auction has ended");
        _;
    }

    /// @notice Restricts function to be called only after the auction has ended (and not already finalized)
    modifier onlyAfterEnd() {
        require(block.timestamp > currentEndTime, "Auction is still active");
        require(!ended, "Auction already finalized");
        _;
    }

    /// @notice Prevents reentrancy on critical functions
    modifier nonReentrant() {
        require(!locked, "Reentrancy detected");
        locked = true;
        _;
        locked = false;
    }

    // ===========================
    // ======= CONSTRUCTOR =======
    // ===========================

    /// @notice Initializes a new auction
    /// @dev _duration is the length (in seconds) from startTime to initialEndTime
    /// @param _duration Duration of the auction in seconds
    constructor(uint256 _duration) {
        require(_duration > 0, "Invalid duration");
        owner = msg.sender;
        startTime = block.timestamp;
        initialEndTime = block.timestamp + _duration;
        currentEndTime = initialEndTime;
    }

    // ===========================
    // ======= AUCTION LOGIC ======
    // ===========================

    /// @notice Place a bid. Must exceed the current highest bid by at least 5%.
    ///         If placed within the last 10 minutes, extends the auction by 10 minutes.
    /// @dev Uses a reentrancy guard on withdrawals only, not on bid itself.
    function bid() external payable onlyWhileActive {
        require(msg.value > 0, "Must send Ether to bid");

        // Calculate new total balance for this bidder
        uint256 newBalance = bidBalances[msg.sender] + msg.value;

        // Determine minimum required if there is an existing highest bid
        if (highestBidAmount > 0) {
            uint256 minRequired = highestBidAmount + (highestBidAmount * MIN_INCREMENT_BPS) / 10000;
            require(newBalance >= minRequired, "Bid must exceed current by at least 5%");
        }

        // If first time bidding, register the bidder
        if (bidBalances[msg.sender] == 0) {
            bidders.push(msg.sender);
        }

        // Update bidder's balance and highest bid info
        bidBalances[msg.sender] = newBalance;
        highestBidAmount = newBalance;
        highestBidder = msg.sender;

        // If bid arrives within the extension window, extend the auction
        if (block.timestamp >= currentEndTime - EXTENSION_WINDOW) {
            currentEndTime = block.timestamp + EXTENSION_DURATION;
        }

        emit NewBid(msg.sender, newBalance, currentEndTime);
    }

    /// @notice Allows a bidder (who is not currently the highest) to withdraw part of their deposit 
    ///         during the auction.
    /// @param amount Amount (in wei) to withdraw; must be ≤ bidder's deposited balance.
    function withdrawExcess(uint256 amount) external onlyWhileActive nonReentrant {
        uint256 balance = bidBalances[msg.sender];
        require(balance > 0, "No funds deposited");
        require(msg.sender != highestBidder, "Winner cannot withdraw");
        require(amount > 0 && amount <= balance, "Invalid withdrawal amount");

        // Decrease bidder's deposit balance
        bidBalances[msg.sender] = balance - amount;

        // Transfer requested amount back
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Withdrawal failed");

        emit WithdrawExcess(msg.sender, amount);
    }

    /// @notice Finalizes the auction. Marks it ended and emits an event.
    /// @dev After finalizeAuction, no more bids are possible, and losing bidders can withdraw their deposits.
    function finalizeAuction() external onlyAfterEnd {
        ended = true;
        emit AuctionEnded(highestBidder, highestBidAmount);
    }

    /// @notice Allows the owner to claim the winning bid amount once the auction is finalized.
    /// @dev Transfers the highest bid amount to the owner. Sets highestBidAmount to zero afterwards.
    function claimFunds() external onlyOwner onlyAfterEnd nonReentrant {
        uint256 amount = highestBidAmount;
        require(amount > 0, "No winning bid to claim");

        highestBidAmount = 0;
        (bool sent, ) = owner.call{value: amount}("");
        require(sent, "Owner withdrawal failed");
    }

    /// @notice Allows losing bidders to withdraw their deposited amount minus a 2% fee 
    ///         after the auction has been finalized.
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
    // ======= VIEW FUNCTIONS =====
    // ===========================

    /// @notice Returns the list of all bidders and their respective bid balances.
    /// @return addresses Array of bidder addresses.
    /// @return amounts  Array of bid amounts corresponding to each bidder.
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

    /// @notice Returns the current highest bidder and their bid amount.
    /// @return winner Address of the highest bidder.
    /// @return amount Amount of the highest bid in wei.
    function showWinner() external view returns (address winner, uint256 amount) {
        return (highestBidder, highestBidAmount);
    }

    /// @notice Returns the number of unique bidders in the auction.
    /// @return count Number of participants who have placed at least one bid.
    function numBidders() external view returns (uint256 count) {
        return bidders.length;
    }

    // ===========================
    // ======= FALLBACKS =========
    // ===========================

    /// @dev Rejects plain Ether transfers to prevent accidental deposits. Always use bid().
    fallback() external payable {
        revert("Use bid()");
    }

    /// @dev Rejects plain Ether transfers to prevent accidental deposits. Always use bid().
    receive() external payable {
        revert("Use bid()");
    }
}
