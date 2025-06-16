
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title AuctionTP - ETH auction with auto-extension, secure withdrawals and fee system
/// @author Hipolito Alonso
/// @notice Implements a secure and extensible ETH auction contract
/// @dev Uses ReentrancyGuard and gas optimizations. Includes auction states and partial/total refunds
contract AuctionTP is ReentrancyGuard {
    /// @notice Address of the contract owner
    address public immutable owner;

    /// @notice Auction start timestamp
    uint256 public immutable startTime;

    /// @notice Auction end timestamp
    uint256 public endTime;

    /// @notice Current highest bidder
    address public highestBidder;

    /// @notice Current highest bid amount
    uint256 public highestBid;

    /// @notice Fee percentage taken from losing bids
    uint256 public constant FEE_PERCENT = 2;

    /// @notice Minimum percentage increment for valid new bids
    uint256 public constant MIN_INCREMENT_PERCENT = 5;

    /// @notice Extra time added if bid occurs near auction end
    uint256 public constant EXTEND_TIME = 10 minutes;

    /// @notice Time window before auction end to trigger extension
    uint256 public constant EXTEND_WINDOW = 10 minutes;

    /// @notice List of all addresses that have placed bids
    address[] public bidders;

    /// @notice Mapping of bidder address to total bid amount
    mapping(address => uint256) public balances;

    /// @notice Prevents duplicate entries in bidders array
    mapping(address => bool) internal _hasBid;

    /// @notice Enum representing auction states
    enum AuctionStatus { Ongoing, Ended }

    /// @notice Current status of the auction
    AuctionStatus public status;

    /// @notice Emitted when a new bid is placed
    /// @param bidder Address of the bidder
    /// @param amount Total amount bid by the bidder
    /// @param newEndTime Updated auction end time if extended
    event NewBid(address indexed bidder, uint256 amount, uint256 newEndTime);

    /// @notice Emitted when the auction ends and a winner is determined
    /// @param winner Address of the highest bidder
    /// @param amount Winning bid amount
    event AuctionEnded(address indexed winner, uint256 amount);

    /// @notice Emitted when a losing bidder withdraws funds
    /// @param bidder Address withdrawing
    /// @param refund Amount refunded to the bidder
    /// @param fee Fee amount retained
    event Withdrawal(address indexed bidder, uint256 refund, uint256 fee);

    /// @notice Emitted on partial withdrawal of a losing bid
    /// @param bidder Address requesting withdrawal
    /// @param requested Amount requested to withdraw
    /// @param refunded Net amount refunded
    /// @param fee Fee retained
    event PartialWithdrawal(address indexed bidder, uint256 requested, uint256 refunded, uint256 fee);

    /// @notice Emitted when the owner withdraws remaining contract balance
    /// @param to Address that receives the ETH
    /// @param amount Amount withdrawn
    event EmergencyWithdraw(address indexed to, uint256 amount);

    /// @notice Constructor to initialize the auction
    /// @param durationSeconds Duration of the auction in seconds
    constructor(uint256 durationSeconds) {
        require(durationSeconds > 0, "dur=0");
        owner = msg.sender;
        startTime = block.timestamp;
        endTime = block.timestamp + durationSeconds;
        status = AuctionStatus.Ongoing;
    }

    /// @notice Place or increase a bid
    /// @dev Requires a minimum increment over current highest bid
    function bid() external payable {
        uint256 nowTime = block.timestamp;
        require(status == AuctionStatus.Ongoing, "not active");
        require(nowTime >= startTime, "not started");
        require(nowTime < endTime, "ended");
        require(msg.value > 0, "no eth");

        if (!_hasBid[msg.sender]) {
            _hasBid[msg.sender] = true;
            bidders.push(msg.sender);
        }

        uint256 newBalance = balances[msg.sender] + msg.value;
        balances[msg.sender] = newBalance;

        if (highestBid > 0) {
            uint256 minRequired = highestBid + (highestBid * MIN_INCREMENT_PERCENT) / 100;
            require(newBalance >= minRequired, "bid < min");
        }

        highestBid = newBalance;
        highestBidder = msg.sender;

        if (nowTime + EXTEND_WINDOW >= endTime) {
            endTime = nowTime + EXTEND_TIME;
        }

        emit NewBid(msg.sender, newBalance, endTime);
    }

    /// @notice Finalizes the auction and sends funds to the owner
    function finalize() external nonReentrant {
        require(msg.sender == owner, "not owner");
        require(block.timestamp > endTime, "ongoing");
        require(status == AuctionStatus.Ongoing, "finalized");

        status = AuctionStatus.Ended;

        uint256 amount = highestBid;
        balances[highestBidder] = 0;

        (bool sent, ) = payable(owner).call{value: amount}("");
        require(sent, "fail send");

        emit AuctionEnded(highestBidder, amount);
    }

    /// @notice Withdraws full bid amount minus fee for losing bidders
    function withdraw() external nonReentrant {
        require(block.timestamp > endTime, "not ended");
        require(msg.sender != highestBidder, "winner");

        uint256 amount = balances[msg.sender];
        require(amount > 0, "no funds");

        balances[msg.sender] = 0;
        uint256 fee = (amount * FEE_PERCENT) / 100;
        uint256 refund = amount - fee;

        (bool sent, ) = payable(msg.sender).call{value: refund}("");
        require(sent, "fail send");

        emit Withdrawal(msg.sender, refund, fee);
    }

    /// @notice Allows partial withdrawal of a losing bid
    /// @param amount Amount to withdraw
    function withdrawPartial(uint256 amount) external nonReentrant {
        require(block.timestamp > endTime, "not ended");
        require(msg.sender != highestBidder, "winner");
        require(amount > 0, "0 amt");

        uint256 balance = balances[msg.sender];
        require(balance >= amount, "insuf bal");

        balances[msg.sender] = balance - amount;
        uint256 fee = (amount * FEE_PERCENT) / 100;
        uint256 refund = amount - fee;

        (bool sent, ) = payable(msg.sender).call{value: refund}("");
        require(sent, "fail send");

        emit PartialWithdrawal(msg.sender, amount, refund, fee);
    }

    /// @notice Distributes funds to all losing bidders
    /// @dev Skips the winner. Optimizes storage reads
    function distributeLosingBids() external nonReentrant {
        require(block.timestamp > endTime, "not ended");

        uint256 len = bidders.length;
        address winner = highestBidder;
        address bidder;
        uint256 amount;
        uint256 fee;
        uint256 refund;

        for (uint256 i = 0; i < len; ++i) {
            bidder = bidders[i];
            if (bidder == winner) continue;

            amount = balances[bidder];
            if (amount == 0) continue;

            balances[bidder] = 0;
            fee = (amount * FEE_PERCENT) / 100;
            refund = amount - fee;

            (bool sent, ) = payable(bidder).call{value: refund}("");
            require(sent, "fail send");

            emit Withdrawal(bidder, refund, fee);
        }
    }

    /// @notice Allows the owner to recover trapped ETH
    /// @dev Only callable after the auction ends
    function emergencyWithdraw() external nonReentrant {
        require(msg.sender == owner, "not owner");
        require(block.timestamp > endTime, "not ended");

        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "no eth");

        (bool sent, ) = payable(owner).call{value: contractBalance}("");
        require(sent, "fail send");

        emit EmergencyWithdraw(owner, contractBalance);
    }

    /// @notice Rejects ETH sent directly
    receive() external payable {
        revert("use bid()");
    }

    /// @notice Rejects unknown function calls
    fallback() external payable {
        revert("use bid()");
    }
}
