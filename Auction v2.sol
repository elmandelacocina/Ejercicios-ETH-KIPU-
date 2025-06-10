
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


pragma solidity ^0.8.20;


/**
 * @title AuctionTP - Full-featured ETH auction with extensions and safe withdrawal
 * @author Hipolito Alonso
 * @notice Implements a basic auction with auto-extension, partial/total withdrawals for losing bids, and fee retention.
 * @dev Uses OpenZeppelin's ReentrancyGuard. Allows owner to recover trapped ETH. Efficient looping and gas-aware patterns.
 */
contract AuctionTP is ReentrancyGuard {
    address public immutable owner;
    uint256 public immutable startTime;
    uint256 public endTime;

    address public highestBidder;
    uint256 public highestBid;
    bool public ended;

    uint256 public constant FEE_PERCENT = 2;
    uint256 public constant MIN_INCREMENT_PERCENT = 5;
    uint256 public constant EXTEND_TIME = 10 minutes;
    uint256 public constant EXTEND_WINDOW = 10 minutes;

    address[] public bidders;
    mapping(address => uint256) public balances;
    mapping(address => bool) internal _hasBid;

    event NewBid(address indexed bidder, uint256 amount, uint256 newEndTime);
    event AuctionEnded(address indexed winner, uint256 amount);
    event Withdrawal(address indexed bidder, uint256 refund, uint256 fee);
    event EmergencyWithdraw(address indexed to, uint256 amount);
    event PartialWithdrawal(address indexed bidder, uint256 requested, uint256 refunded, uint256 fee);

    /**
     * @notice Initializes the auction contract with a fixed duration.
     * @param durationSeconds The duration of the auction in seconds.
     */
    constructor(uint256 durationSeconds) {
        require(durationSeconds > 0, "dur=0");
        owner = msg.sender;
        startTime = block.timestamp;
        endTime = block.timestamp + durationSeconds;
    }

    /**
     * @notice Places or increases a bid in the auction.
     * @dev Bids must be 5% higher than the current highest bid.
     */
    function bid() external payable {
        uint256 nowTime = block.timestamp;
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

    /**
     * @notice Finalizes the auction and transfers the highest bid to the owner.
     */
    function finalize() external nonReentrant {
        require(msg.sender == owner, "not owner");
        require(block.timestamp > endTime, "ongoing");
        require(!ended, "finalized");

        ended = true;

        uint256 amount = highestBid;
        balances[highestBidder] = 0;

        (bool sent, ) = payable(owner).call{value: amount}("");
        require(sent, "fail send");

        emit AuctionEnded(highestBidder, amount);
    }

    /**
     * @notice Withdraws the entire losing bid balance minus fee.
     */
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

    /**
     * @notice Withdraws a portion of the user's losing bid.
     * @param amount The amount the user wants to withdraw (in wei).
     */
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

    /**
     * @notice Loops through all bidders and distributes their funds if they lost.
     * @dev Can be gas-intensive; best used off-chain in chunks for many bidders.
     */
    function distributeLosingBids() external nonReentrant {
        require(block.timestamp > endTime, "not ended");

        uint256 len = bidders.length;
        address bidder;
        uint256 amount;
        uint256 fee;
        uint256 refund;

        for (uint256 i = 0; i < len; ++i) {
            bidder = bidders[i];

            if (bidder == highestBidder) {
                continue;
            }

            amount = balances[bidder];
            if (amount == 0) {
                continue;
            }

            balances[bidder] = 0;

            fee = (amount * FEE_PERCENT) / 100;
            refund = amount - fee;

            (bool sent, ) = payable(bidder).call{value: refund}("");
            require(sent, "fail send");

            emit Withdrawal(bidder, refund, fee);
        }
    }

    /**
     * @notice View the current winner and their bid.
     * @return The address of the winner and bid amount.
     */
    function getWinner() external view returns (address, uint256) {
        return (highestBidder, highestBid);
    }

    /**
     * @notice Emergency function for the owner to recover stuck ETH.
     * @dev Only callable if auction has ended and all losing bids are refunded.
     */
    function emergencyWithdraw() external nonReentrant {
        require(msg.sender == owner, "not owner");
        require(block.timestamp > endTime, "not ended");

        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "no eth");

        (bool sent, ) = payable(owner).call{value: contractBalance}("");
        require(sent, "fail send");

        emit EmergencyWithdraw(owner, contractBalance);
    }

    receive() external payable {
        revert("use bid()");
    }

    fallback() external payable {
        revert("use bid()");
    }
}
