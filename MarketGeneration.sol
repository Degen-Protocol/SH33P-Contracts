// SPDX-License-Identifier: U-U-U-UPPPPP!!!
pragma solidity ^0.7.4;

import "./IMarketDistribution.sol";
import "./IMarketGeneration.sol";
import "./TokensRecoverable.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./IWBNB.sol";

contract MarketGeneration is TokensRecoverable, IMarketGeneration {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public baseToken;
    IMarketDistribution public marketDistribution;

    bool public isActive;

    uint256 public override totalContribution;

    uint256 public hardCap;
    uint256 public startTime;
    uint256 public finishTime;
    uint256 public maxContribution;
    uint256 public refundsAllowedUntil;

    mapping (address => uint256) public override contribution;

    modifier active() {
        require (isActive, "Distribution not active");
        _;
    }

    modifier checkUserContribution(uint256 _value) {
        uint256 _newContributionTotal = (contribution[msg.sender] + msg.value);
        require(_newContributionTotal < maxContribution, "RESULTS_OVER_MAX");
        _;
    }

    modifier checkHardCap(uint256 _amount) {
        uint256 _remaining = tokensToHardCap();
        require(_amount < _remaining, "TARGET_REACHED");
        _;
    }

    event onContribute(address indexed _caller, uint256 _value, uint256 _timestamp);

    constructor() {
        maxContribution = 10000000000000000000000;
        hardCap = (800000000000000000000000);
    }

    function contributionAllowed(address _user) public view returns (uint256) {
        return (maxContribution.sub(contribution[_user]));
    }

    function tokensToHardCap() public view returns (uint256) {
        uint256 _collected = address(this).balance;

        if (hardCap > _collected) {
            return ((hardCap).sub(_collected));
        }

        return 0;
    }

    function init(IERC20 _baseToken) public ownerOnly() {
        require (!isActive && block.timestamp >= refundsAllowedUntil, "Already activated");
        baseToken = _baseToken;
    }

    function activate(IMarketDistribution _marketDistribution) public ownerOnly() {
        require (!isActive && block.timestamp >= refundsAllowedUntil, "Already activated");        
        require (address(_marketDistribution) != address(0));
        marketDistribution = _marketDistribution;
        isActive = true;

        startTime = (block.timestamp * 1000);
        finishTime = ((block.timestamp + 7 days) * 1000);
    }

    function setMarketDistribution(IMarketDistribution _marketDistribution) public ownerOnly() active() {
        require (address(_marketDistribution) != address(0), "Invalid market distribution");
        if (_marketDistribution == marketDistribution) { return; }
        marketDistribution = _marketDistribution;

        // Give everyone 1 day to claim refunds if they don't approve of the new distributor
        refundsAllowedUntil = block.timestamp + 86400;
    }

    function complete() public ownerOnly() active() {
        require (block.timestamp >= refundsAllowedUntil, "Refund period is still active");

        isActive = false;
        if (address(this).balance == 0) { return; }
        
        IWBNB(address(baseToken)).deposit{ value: address(this).balance }();
        baseToken.safeApprove(address(marketDistribution), uint256(-1));

        marketDistribution.distribute();
    }

    function allowRefunds() public ownerOnly() active() {
        isActive = false;
        refundsAllowedUntil = uint256(-1);
    }

    function refund(uint256 amount) private {
        (bool success,) = msg.sender.call{ value: amount }("");
        require (success, "Refund transfer failed");  
          
        totalContribution -= amount;
        contribution[msg.sender] = 0;
    }

    function claim() public {
        uint256 amount = contribution[msg.sender];
        require (amount > 0, "Nothing to claim");
        
        if (refundsAllowedUntil > block.timestamp) {
            refund(amount);
        } else {
            marketDistribution.claim(msg.sender);
        }
    }

    function contribute() public payable checkUserContribution(msg.value) checkHardCap(msg.value) active() {
        contribution[msg.sender] += msg.value;
        totalContribution += msg.value;

        emit onContribute(msg.sender, msg.value, block.timestamp);
    }

    receive() external payable active() {
        contribute();
    }
}