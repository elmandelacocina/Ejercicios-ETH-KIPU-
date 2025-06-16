// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title AuctionTP - ETH auction with auto-extension, secure withdrawals, and fee system
/// @author Hipolito Alonso
/// @notice Secure and extensible ETH auction contract with auto-extension and refund mechanism
contract AuctionTP is ReentrancyGuard {
    address public immutable owner;
    uint256 public immutable startTime;
    uint256 public endTime;
    address public highestBidder;
    uint256 public highestBid;

    uint256 public constant FEE_PERCENT = 2;
    uint256 public constant MIN_INCREMENT_PERCENT = 5;
    uint256 public constant EXTEND_TIME = 10 minutes;
    uint256 public constant EXTEND_WINDOW = 10 minutes;

    address[] public bidders;
    mapping(address => uint256) public balances;

    /// @notice Enum representing bidder participation
    enum ParticipationStatus { NotEntered, Entered }

    /// @notice Tracks each address's status
    mapping(address => ParticipationStatus) internal participationStatus;

    enum AuctionStatus { Ongoing, Ended }
    AuctionStatus public status;

    event NewBid(address indexed bidder, uint256 amount, uint256 newEndTime);
    event AuctionEnded(address indexed winner, uint256 amount);
    event Withdrawal(address indexed bidder, uint256 refund, uint256 fee);
    event PartialWithdrawal(address indexed bidder, uint256 requested, uint256 refunded, uint256 fee);
    event EmergencyWithdraw(address indexed to, uint256 amount);

    modifier onlyWhileOngoing() {
        require(status == AuctionStatus.Ongoing, "auction ended");
        require(block.timestamp >= startTime && block.timestamp < endTime, "not in bidding window");
        _;
    }

    modifier onlyWhenEnded() {
        require(block.timestamp > endTime, "auction not ended");
        _;
    }

    /// @notice Initializes the auction with duration
    /// @param durationSeconds Auction duration in seconds
    constructor(uint256 durationSeconds) {
        require(durationSeconds > 0, "invalid duration");
        owner = msg.sender;
        startTime = block.timestamp;
        endTime = block.timestamp + durationSeconds;
        status = AuctionStatus.Ongoing;
    }

    /// @notice Place or increase a bid
    /// @dev Extends auction if bid is near end
    function bid() external payable onlyWhileOngoing {
        address sender = msg.sender;
        uint256 value = msg.value;
        require(value > 0, "no ETH sent");

        if (participationStatus[sender] == ParticipationStatus.NotEntered) {
            participationStatus[sender] = ParticipationStatus.Entered;
            bidders.push(sender);
        }

        uint256 newBalance = balances[sender] + value;
        require(
            highestBid == 0 || newBalance >= highestBid + (highestBid * MIN_INCREMENT_PERCENT) / 100,
            "bid too low"
        );

        balances[sender] = newBalance;
        highestBid = newBalance;
        highestBidder = sender;

        if (block.timestamp + EXTEND_WINDOW >= endTime) {
            endTime = block.timestamp + EXTEND_TIME;
        }

        emit NewBid(sender, newBalance, endTime);
    }

    /// @notice Finalize the auction and transfer funds to owner
    function finalize() external nonReentrant onlyWhenEnded {
        require(msg.sender == owner, "not owner");

        status = AuctionStatus.Ended;
        address winner = highestBidder;
        uint256 amount = highestBid;

        balances[winner] = 0;

        (bool sent, ) = payable(owner).call{value: amount}("");
        require(sent, "send failed");

        emit AuctionEnded(winner, amount);
    }

    /// @notice Withdraws full balance for losing bidders
    function withdraw() external nonReentrant onlyWhenEnded {
        address sender = msg.sender;
        address winner = highestBidder;
        uint256 balance = balances[sender];

        require(sender != winner && balance > 0, "invalid withdrawal");

        balances[sender] = 0;

        uint256 fee = (balance * FEE_PERCENT) / 100;
        uint256 refund = balance - fee;

        (bool sent, ) = payable(sender).call{value: refund}("");
        require(sent, "send failed");

        emit Withdrawal(sender, refund, fee);
    }

    /// @notice Withdraws a partial amount for losing bidders
    /// @param amount The amount to withdraw
    function withdrawPartial(uint256 amount) external nonReentrant onlyWhenEnded {
        address sender = msg.sender;
        address winner = highestBidder;

        require(sender != winner, "winner can't withdraw");
        require(amount > 0, "amount zero");

        uint256 senderBalance = balances[sender];
        require(amount <= senderBalance, "amount exceeds balance");

        balances[sender] = senderBalance - amount;

        uint256 fee = (amount * FEE_PERCENT) / 100;
        uint256 refund = amount - fee;

        (bool sent, ) = payable(sender).call{value: refund}("");
        require(sent, "send failed");

        emit PartialWithdrawal(sender, amount, refund, fee);
    }

    /// @notice Refunds all losing bidders after auction ends
    function distributeLosingBids() external nonReentrant onlyWhenEnded {
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
            require(sent, "send failed");

            emit Withdrawal(bidder, refund, fee);
        }
    }

    /// @notice Emergency withdrawal of remaining ETH
    function emergencyWithdraw() external nonReentrant onlyWhenEnded {
        require(msg.sender == owner, "not owner");

        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "no ETH");

        (bool sent, ) = payable(owner).call{value: contractBalance}("");
        require(sent, "send failed");

        emit EmergencyWithdraw(owner, contractBalance);
    }

    /// @notice Rejects direct ETH transfers
    receive() external payable {
        revert("use bid()");
    }

    /// @notice Rejects unexpected function calls
    fallback() external payable {
        revert("use bid()");
    }
}
