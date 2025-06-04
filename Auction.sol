// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Dynamic Auction with Extension and Partial Refunds
/// @notice Allows bidding on an item, extending the end time with each valid new bid.

contract Auction {
    /// @notice Address of the auction owner
    address public immutable owner;

    /// @notice Marks the start of the auction (timestamp)
    uint256 public immutable startTime;

    /// @notice Marks the original end time of the auction (timestamp)
    uint256 public immutable setFinalTime;

    /// @notice Marks the updated end time of the auction (timestamp)
    uint256 public timeUpdated;

    /// @notice Address of the bidder with the highest bid
    address public highBidder;

    /// @notice Value of the highest bid
    uint256 public highBid;

    /// @notice Indicates whether the auction has been finalized
    bool public ended;

    /// @notice Refund fee: 2% for non-winning bidders
    uint256 public constant comision = 200; // 2% in basis points (1% = 100 bps)

    /// @notice Mapping of bids by address
    mapping(address => uint256) public bids;

    /// @notice List of unique bidders
    address[] public bidders;

    /// @notice Emitted when a new valid bid is placed
    event newBid(address indexed bidder, uint256 amount, uint256 newtimeUpdated);

    /// @notice Emitted when the auction is finalized
    event endedBid(address winner, uint256 amount);

    /// @notice Modifier to restrict access to the owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can execute");
        _;
    }

    /// @notice Modifier to check if the auction is active
    modifier onlyWhileActive() {
        require(block.timestamp >= startTime, "Auction has not started");
        require(block.timestamp <= timeUpdated, "Auction has ended");
        _;
    }

    /// @notice Modifier for a single execution after the auction ends
    modifier onlyAfterEnd() {
        require(block.timestamp > timeUpdated, "Auction is still active");
        require(!ended, "Auction already finalized");
        _;
    }

    /**
     * @notice Auction constructor
     * @dev _duration: Duration in seconds from start to initial end
     */
    constructor(uint256 _duration) {
        require(_duration > 0, "Invalid duration"); // Value must be greater than 0
        owner = msg.sender;
        startTime = block.timestamp;
        setFinalTime = block.timestamp + _duration;
        timeUpdated = setFinalTime;
    }

    /**
     * @notice Place a bid. The bid must exceed the current highest bid by at least 5%.
     * @notice If placed within the last 10 minutes, extend the auction by 10 minutes.
     */
    function bid() external payable onlyWhileActive {
        require(msg.value > 0, "Must send Ether"); // Value must be greater than 0
        uint256 currentBid = bids[msg.sender] + msg.value;
        uint256 minRequired = highBid + (highBid * 5) / 100; // Calculate 5% above the last bid

        // @notice First bid is always valid
        if (highBid > 0) {
            require(currentBid >= minRequired, "Bid must exceed at least 5%");
        }

        // @notice New bidder
        if (bids[msg.sender] == 0) {
            bidders.push(msg.sender);
        }

        bids[msg.sender] = currentBid;

        highBid = currentBid;
        highBidder = msg.sender;

        // @notice Dynamic extension if within 10 minutes of end
        if (block.timestamp >= timeUpdated - 10 minutes) {
            timeUpdated = block.timestamp + 10 minutes;
        }

        emit newBid(msg.sender, currentBid, timeUpdated); // Emit the event
    }

    /**
     * @notice Allows withdrawing part of the bidder’s excess deposit during the auction.
     * @param amount: Amount to withdraw (must be less than or equal to total deposited)
     */
    function withdrawExcess(uint256 amount) external onlyWhileActive {
        uint256 bidAmount = bids[msg.sender];
        require(bidAmount > 0, "No funds deposited");
        require(msg.sender != highBidder, "Winner cannot withdraw");
        require(amount > 0 && amount <= bidAmount, "Invalid amount");

        // @notice Reduce the user's deposit
        bids[msg.sender] = bidAmount - amount;

        // @notice Transfer the requested amount
        // Use call to avoid send or transfer
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Withdrawal failed");
    }

    /**
     * @notice Finalizes the auction and allows non-winning bidders to withdraw deposits minus a 2% fee.
     */
    function finalizeAuction() external onlyAfterEnd {
        ended = true;

        emit endedBid(highBidder, highBid); // Emit the event
    }

    /**
     * @notice Allows non-winning bidders to withdraw their deposit with a 2% fee.
     */
    function withdrawDeposit() external {
        require(ended, "Auction has not ended");
        require(msg.sender != highBidder, "Winner cannot withdraw here");

        uint256 amount = bids[msg.sender];
        require(amount > 0, "Nothing to withdraw");

        bids[msg.sender] = 0;

        uint256 fee = (amount * comision) / 10000;
        uint256 refund = amount - fee;

        (bool sent, ) = msg.sender.call{value: refund}("");
        require(sent, "Refund failed");
    }

    /**
     * @notice Returns the list of all bidders and their bids.
     * @return addresses Array of bidder addresses.
     * @return amounts Array of bid amounts for each address.
     */
    function showBids() external view returns (address[] memory addresses, uint256[] memory amounts) {
        uint256 len = bidders.length;
        addresses = new address[](len);
        amounts = new uint256[](len);

        for (uint256 i = 0; i < len; ++i) {
            address bidder = bidders[i];
            addresses[i] = bidder;
            amounts[i] = bids[bidder];
        }
    }

    /**
     * @notice Returns the current winner and the winning bid.
     * @return winner Address of the bidder with the highest bid
     * @return amount Amount of the highest bid
     */
    function showWinner() external view returns (address winner, uint256 amount) {
        return (highBidder, highBid);
    }

    /**
     * @notice Returns the number of unique bidders.
     * @return count Number of unique participants
     */
    function numbidders() external view returns (uint256) {
        return bidders.length;
    }

    /**
     * @dev Rejects direct deposits unless via the bid() function.
     */
    fallback() external payable {
        revert("Use bid()"); // Always use bid() for better control
    }

    receive() external payable {
        revert("Use bid()"); // Always use bid() for better control
    }
}
