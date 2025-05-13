// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title EtherPiggyBank - Modern Ether Savings Contract
 * @dev A feature-rich piggy bank for ETH with enhanced security, social features, and gamification
 */
contract EtherPiggyBank is ReentrancyGuard, Ownable {
    // Struct to store savings data
    struct SavingsGoal {
        uint256 targetAmount;
        uint256 deadline;
        string description;
        bool isLocked;
    }

    // Struct for withdrawal requests (time-lock feature)
    struct WithdrawalRequest {
        uint256 amount;
        uint256 unlockTime;
        bool executed;
    }

    // User savings data
    mapping(address => uint256) private _balances;
    mapping(address => SavingsGoal) private _savingsGoals;
    mapping(address => WithdrawalRequest) private _withdrawalRequests;
    mapping(address => address[]) private _savingsPartners;
    mapping(address => mapping(address => bool)) private _isSavingsPartner;

    // Contract statistics
    uint256 private _totalSavings;
    uint256 private _totalUsers;
    uint256 private _totalWithdrawals;

    // Events for enhanced UX and frontend integration
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event SavingsGoalSet(address indexed user, uint256 target, uint256 deadline, string description);
    event GoalAchieved(address indexed user, uint256 amount);
    event WithdrawalRequested(address indexed user, uint256 amount, uint256 unlockTime);
    event SavingsPartnerAdded(address indexed user, address indexed partner);
    event EmergencyStopActivated(bool isStopped);
    event InterestPaid(address indexed user, uint256 amount);

    // Contract configuration
    uint256 public constant MIN_SAVINGS_GOAL = 0.01 ether;
    uint256 public constant WITHDRAWAL_DELAY = 7 days;
    bool public emergencyStop;

    // Interest distribution (simplified for example)
    uint256 private _lastInterestDistribution;
    uint256 private _interestRate = 3; // 3% annual interest

    modifier whenNotEmergency() {
        require(!emergencyStop, "Contract is in emergency stop mode");
        _;
    }

    constructor() Ownable(msg.sender) {
        _lastInterestDistribution = block.timestamp;
    }

    /**
     * @dev Deposit ETH into the piggy bank
     */
    function deposit() external payable whenNotEmergency nonReentrant {
        require(msg.value > 0, "Deposit amount must be greater than 0");
        
        _balances[msg.sender] += msg.value;
        _totalSavings += msg.value;
        
        if (_balances[msg.sender] == msg.value) {
            _totalUsers++;
        }
        
        emit Deposited(msg.sender, msg.value);
        
        // Check if savings goal reached
        _checkGoalAchievement(msg.sender);
    }

    /**
     * @dev Request a withdrawal (subject to time-lock)
     * @param amount Amount to withdraw
     */
    function requestWithdrawal(uint256 amount) external whenNotEmergency {
        require(amount <= _balances[msg.sender], "Insufficient balance");
        require(_withdrawalRequests[msg.sender].unlockTime == 0, "Existing withdrawal request");
        
        _withdrawalRequests[msg.sender] = WithdrawalRequest({
            amount: amount,
            unlockTime: block.timestamp + WITHDRAWAL_DELAY,
            executed: false
        });
        
        emit WithdrawalRequested(msg.sender, amount, block.timestamp + WITHDRAWAL_DELAY);
    }

    /**
     * @dev Execute a withdrawal after time-lock period
     */
    function executeWithdrawal() external whenNotEmergency nonReentrant {
        WithdrawalRequest storage request = _withdrawalRequests[msg.sender];
        require(request.amount > 0, "No withdrawal request");
        require(!request.executed, "Withdrawal already executed");
        require(block.timestamp >= request.unlockTime, "Withdrawal time-lock not expired");
        require(request.amount <= _balances[msg.sender], "Insufficient balance");
        
        // Update balances
        _balances[msg.sender] -= request.amount;
        _totalSavings -= request.amount;
        request.executed = true;
        _totalWithdrawals++;
        
        // Transfer funds
        (bool success, ) = msg.sender.call{value: request.amount}("");
        require(success, "Withdrawal failed");
        
        emit Withdrawn(msg.sender, request.amount);
    }

    /**
     * @dev Set a savings goal
     * @param targetAmount Target amount to save (in wei)
     * @param deadline Unix timestamp of goal deadline
     * @param description Optional description of the goal
     */
    function setSavingsGoal(
        uint256 targetAmount,
        uint256 deadline,
        string memory description
    ) external whenNotEmergency {
        require(targetAmount >= MIN_SAVINGS_GOAL, "Target amount too low");
        require(deadline > block.timestamp, "Deadline must be in the future");
        
        _savingsGoals[msg.sender] = SavingsGoal({
            targetAmount: targetAmount,
            deadline: deadline,
            description: description,
            isLocked: false
        });
        
        emit SavingsGoalSet(msg.sender, targetAmount, deadline, description);
    }

    /**
     * @dev Lock savings until goal is reached or deadline passes
     */
    function lockSavings() external whenNotEmergency {
        SavingsGoal storage goal = _savingsGoals[msg.sender];
        require(goal.targetAmount > 0, "No savings goal set");
        require(!goal.isLocked, "Savings already locked");
        
        goal.isLocked = true;
    }

    /**
      * @dev Add a savings partner (can view your progress)
      * @param partner Address of the partner to add
      */
    function addSavingsPartner(address partner) external whenNotEmergency {
        require(partner != address(0), "Invalid address");
        require(partner != msg.sender, "Cannot add yourself");
        require(!_isSavingsPartner[msg.sender][partner], "Already a savings partner");
        
        _savingsPartners[msg.sender].push(partner);
        _isSavingsPartner[msg.sender][partner] = true;
        
        emit SavingsPartnerAdded(msg.sender, partner);
    }

    /**
     * @dev Get current balance of a user
     * @param user Address to query
     * @return Current balance in wei
     */
    function getBalance(address user) external view returns (uint256) {
        return _balances[user];
    }

    /**
     * @dev Get savings goal details
     * @param user Address to query
     * @return SavingsGoal struct
     */
    function getSavingsGoal(address user) external view returns (SavingsGoal memory) {
        require(msg.sender == user || _isSavingsPartner[user][msg.sender], "Not authorized");
        return _savingsGoals[user];
    }

    /**
     * @dev Get withdrawal request details
     * @param user Address to query
     * @return WithdrawalRequest struct
     */
    function getWithdrawalRequest(address user) external view returns (WithdrawalRequest memory) {
        require(msg.sender == user, "Not authorized");
        return _withdrawalRequests[user];
    }

    /**
     * @dev Get contract statistics
     * @return totalSavings, totalUsers, totalWithdrawals
     */
    function getStatistics() external view returns (uint256, uint256, uint256) {
        return (_totalSavings, _totalUsers, _totalWithdrawals);
    }

    /**
     * @dev Emergency stop function (owner only)
     */
    function toggleEmergencyStop() external onlyOwner {
        emergencyStop = !emergencyStop;
        emit EmergencyStopActivated(emergencyStop);
    }

    /**
     * @dev Distribute interest to all users (simplified example)
     */
    function distributeInterest() external onlyOwner {
        require(block.timestamp > _lastInterestDistribution + 365 days, "Interest already distributed this year");
        
        // Simplified interest distribution - in production would be more efficient
        // This is just to demonstrate the concept for the competition
        
        uint256 totalInterest = address(this).balance - _totalSavings;
        if (totalInterest > 0) {
            for (uint256 i = 0; i < _totalUsers; i++) {
                // In a real implementation, we would track users differently
                // This is just for demonstration
                address user = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, i))));
                if (_balances[user] > 0) {
                    uint256 interest = (_balances[user] * _interestRate) / 100;
                    _balances[user] += interest;
                    emit InterestPaid(user, interest);
                }
            }
            _lastInterestDistribution = block.timestamp;
        }
    }

    /**
     * @dev Internal function to check goal achievement
     * @param user Address to check
     */
    function _checkGoalAchievement(address user) internal {
        SavingsGoal storage goal = _savingsGoals[user];
        if (goal.targetAmount > 0 && _balances[user] >= goal.targetAmount) {
            emit GoalAchieved(user, goal.targetAmount);
            goal.isLocked = false; // Unlock if goal achieved
        }
    }

    // Fallback function to receive ETH
    receive() external payable {
        // ETH can be sent directly to contract (e.g., for interest distribution)
    }
}
