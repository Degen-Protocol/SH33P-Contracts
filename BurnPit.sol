// SPDX-License-Identifier: U-U-U-UPPPPP!!!
pragma solidity ^0.7.4;

// The burn pit is a step above a simple burn address 
// It will serve the community by collecting a redistributing fees
// Oscillating between 50-51%

import "./Address.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";

import "./IERC20.sol";

import "./Whitelist.sol";


contract BurnPit is Whitelist {
    using Address for address;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    IERC20 public token;

    uint256 internal _divisor;
    uint256 internal _lastRebalance;
    uint256 internal _lowerboundPercentage;
    uint256 internal _upperboundPercentage;

    event Rebalance(uint256 tokens);

    modifier ifReady() {
        require(isReady(), "NOT_READY_YET");
        _;
    }

    constructor (address _mainUser, address _token, uint _oneHundredPercent) {

        _divisor = _oneHundredPercent;

        //get a handle on the token
        token = IERC20(_token);

        // a rebalance isn't necessary at launch
        _lastRebalance =  block.timestamp;

        addAddressToWhitelist(msg.sender);
        addAddressToWhitelist(_mainUser);
    }

    function isReady() public view returns (bool) {
        (uint256 _upper, ) = percentages();
        uint256 _total = tokenBalance();

        if (_total > _upper){
            return true;
        }

        return false;
    }

    // WRITE FUNCTIONS //

    function percentages() public view returns (uint256, uint256) {
        return (_upperboundPercentage, _lowerboundPercentage);
    }

    function limits() public view returns (uint256, uint256) {
        return (
            (token.totalSupply().mul(_upperboundPercentage).div(_divisor)), 
            (token.totalSupply().mul(_lowerboundPercentage).div(_divisor))
        );
    }

    function tokenBalance() public view returns (uint256) {
        return (token.balanceOf(address(this)));
    }

    function pendingReward() public view returns (uint256) {
        (, uint256 _lower) = percentages();
        uint256 total = tokenBalance();

        return (total.sub(_lower));
    }

    function rebalance() external onlyWhitelisted() ifReady() returns (bool _success){
        uint256 boost = pendingReward();

        token.transfer(address(token), boost);
        _lastRebalance = block.timestamp;

        emit Rebalance(boost);
        return true;
    }
}