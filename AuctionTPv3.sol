// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title AuctionTP - ETH auction with auto-extension, secure withdrawals and fee system
/// @author Hipolito Alonso
/// @notice Secure and extensible ETH auction contract with auto-extension and refund mechanism
/// @dev Uses OpenZeppelin's ReentrancyGuard. Optimized for gas and secure access control.
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

    /// @notice Fee percentage taken from losing bids (2%)
    uint256 public constant FEE_PERCENT = 2;

    /// @notice Minimum percentage increment required to outbid (5%)
    uint256 public constant MIN_INCREMENT_PERCENT = 5;

    /// @notice Time added if bid is near auction end
    uint256 public constant EXTEND_TIME = 10 minutes;

    /// @notice Time window before auction end to trigger extension
    uint256 public constant EXTEND_WINDOW = 10 minutes;

    /// @notice List of all bidders (used for mass refunds)
    address[] public bidders;

    /// @notice Mapping of address to total amount bid
    mapping(address => uint256) public balances;

    /// @notice Prevents duplicate bidder entries in `bidders`
    mapping(address => bool) internal _hasBid;

    /// @notice Enum for auction status
    enum AuctionStatus { Ongoing, Ended }

    /// @notice Current auction state
    AuctionStatus public status;

    /// @notice Emitted when a new bid is placed
    event NewBid(address indexed bidder, uint256 amount, uint256 newEndTime);

    /// @notice Emitted when the auction is finalized
    event AuctionEnded(address indexed winner, uint256 amount);

    /// @notice Emitted when a losing bidder withdraws funds
    event Withdrawal(address indexed bidder, uint256 refund, uint256 fee);

    /// @notice Emitted when a partial withdrawal is made
    event PartialWithdrawal(address indexed bidder, uint256 requested, uint256 refunded, uint256 fee);

    /// @notice Emitted when the owner withdraws remaining contract funds
    event EmergencyWithdraw(address indexed to, uint256 amount);

    /// @notice Initializes the auction with a given duration
    /// @param durationSeconds Duration of the auction in seconds
    constructor(uint256 durationSeconds) {
        require(durationSeconds > 0, "dur=0");
        owner = msg.sender;
        startTime = block.timestamp;
        endTime = block.timestamp + durationSeconds;
        status = AuctionStatus.Ongoing;
    }

    /// @notice Place or increase a bid
    /// @dev Adds sender to bidders list if first bid. Enforces minimum increment.
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

    /// @notice Finalizes auction and sends winning bid to the owner
    /// @dev Only callable by the owner. Can only be called once.
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

    /// @notice Allows losing bidders to withdraw their full bid minus fee
    function withdraw() external nonReentrant {
        address sender = msg.sender;
        require(block.timestamp > endTime, "not ended");
        require(sender != highestBidder, "winner");

        uint256 balance = balances[sender];
        require(balance > 0, "no funds");

        balances[sender] = 0;
        uint256 fee = (balance * FEE_PERCENT) / 100;
        uint256 refund = balance - fee;

        (bool sent, ) = payable(sender).call{value: refund}("");
        require(sent, "fail send");

        emit Withdrawal(sender, refund, fee);
    }

    /// @notice Allows partial withdrawal of a losing bid
    /// @param amount Amount to withdraw
    function withdrawPartial(uint256 amount) external nonReentrant {
        address sender = msg.sender;
        require(block.timestamp > endTime, "not ended");
        require(sender != highestBidder, "winner");
        require(amount > 0, "0 amt");

        uint256 balance = balances[sender];
        require(balance >= amount, "insuf bal");

        balances[sender] = balance - amount;
        uint256 fee = (amount * FEE_PERCENT) / 100;
        uint256 refund = amount - fee;

        (bool sent, ) = payable(sender).call{value: refund}("");
        require(sent, "fail send");

        emit PartialWithdrawal(sender, amount, refund, fee);
    }

    /// @notice Refunds all losing bidders minus fee
    /// @dev Optimized for gas, skips winner
    function distributeLosingBids() external nonReentrant {
        require(block.timestamp > endTime, "not ended");

        address winner = highestBidder;
        uint256 len = bidders.length;

        for (uint256 i = 0; i < len; ++i) {
            address bidder = bidders[i];
            if (bidder == winner) continue;

            uint256 balance = balances[bidder];
            if (balance == 0) continue;

            balances[bidder] = 0;

            uint256 fee = (balance * FEE_PERCENT) / 100;
            uint256 refund = balance - fee;

            (bool sent, ) = payable(bidder).call{value: refund}("");
            require(sent, "fail send");

            emit Withdrawal(bidder, refund, fee);
        }
    }

    /// @notice Allows the owner to recover stuck ETH after auction ends
    function emergencyWithdraw() external nonReentrant {
        require(msg.sender == owner, "not owner");
        require(block.timestamp > endTime, "not ended");

        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "no eth");

        (bool sent, ) = payable(owner).call{value: contractBalance}("");
        require(sent, "fail send");

        emit EmergencyWithdraw(owner, contractBalance);
    }

    /// @notice Reject ETH sent directly to the contract
    receive() external payable {
        revert("use bid()");
    }

    /// @notice Reject fallback function calls
    fallback() external payable {
        revert("use bid()");
    }
}
