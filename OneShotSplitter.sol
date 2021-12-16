// SPDX-License-Identifier: U-U-U-UPPPPP!!!
pragma solidity 0.7.4;

import './SafeMath.sol';
import './IERC20.sol';

import './Whitelist.sol';

contract OneShotSplitter is Whitelist {
    using SafeMath for uint256;

    IERC20 public baseToken;

    address public devAddress; // The Don
    address public teamAddress; // Team Splitter Contract
    address public promoAddress; // Promo/Marketing Splitter Contract

    IERC20 public token;

    constructor (address _devAddress, address _teamAddress, address _promoAddress) Ownable() {
        devAddress = _devAddress;
        teamAddress = _teamAddress;
        promoAddress = _promoAddress;

        addAddressToWhitelist(msg.sender);
        addAddressToWhitelist(devAddress);
        addAddressToWhitelist(teamAddress);
        addAddressToWhitelist(promoAddress);
    }

    function transferTokens(address _recipient, address _token, uint256 _amount) onlyWhitelisted() public returns (bool _success) {
        token = IERC20(_token);

        require(token.balanceOf(address(this)) > 0, "NO_BALANCE");

        token.transfer(_recipient, _amount);

        return true;
    }

    // If tokens need to be broken per-proportion
    function splitPayment(address _token) onlyWhitelisted() public returns (bool _success) {
        baseToken = IERC20(_token);

        uint256 totalBase = baseToken.balanceOf(address(this));
        require(totalBase > 0, "NOTHING_TO_DISTRIBUTE");

        uint256 onePiece = (totalBase.div(15));

        uint256 _forTheDon  = (2  * onePiece);
        uint256 _forTheTeam = (10 * onePiece);
        uint256 _promoFunds = (3  * onePiece);

        baseToken.transfer(devAddress, _forTheDon);
        baseToken.transfer(teamAddress, _forTheTeam);
        baseToken.transfer(promoAddress, _promoFunds);

        return true;
    }
}