// SPDX-License-Identifier: U-U-U-UPPPPP!!!
pragma solidity 0.7.4;

import "./Address.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";
import "./Whitelist.sol";

interface IVault {
    function donate(uint _amount) external returns (uint256);
}

interface IEliteToken {
    function stake(uint256 amount) external;
}

contract VaultBooster is Whitelist {
    using Address for address;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /////////////////////////
    // CONTRACT INTERFACES //
    /////////////////////////

    // Basic token handling for both SH33P and xSH33P
    IERC20 public  SH33P;
    IERC20 public xSH33P;
    
    // Vault Interface, to boost that APY
    IVault public  vault;

    // Elite Token interface, to stake SH33P into xSH33P
    IEliteToken public SH33PToken;

    /////////////////////////////////
    // CONFIGURABLES AND VARIABLES //
    /////////////////////////////////

    // Technically Infinity
    uint256 internal MAX_UINT = 2**256 - 1;

    uint256 public totalTokensStaked;
    uint256 public totalRewardsDistributed;
    
    /////////////////////
    // CONTRACT EVENTS //
    /////////////////////

    event onStakeRootToken(address indexed _caller, address indexed _token, uint256 _amount, uint256 _timestamp);
    event onDepositToDripPool(uint256 _amount, uint256 _timestamp);

    //////////////////////////////
    // CONSTRUCTOR AND FALLBACK //
    //////////////////////////////

    constructor(address _token, address _xToken, address _vault, address _mainUser) {
        SH33P = IERC20(_token);
        xSH33P = IERC20(_xToken);
        SH33PToken = IEliteToken(_token);
        vault = IVault(_vault);

        addAddressToWhitelist(msg.sender);
        addAddressToWhitelist(_mainUser);
    }

    receive() external payable {

    }

    ////////////////////
    // VIEW FUNCTIONS //
    ////////////////////

    // Base Balance
    function baseBalance() public view returns (uint256 _balance) {
        return (address(this).balance);
    }

    // Token Balance
    function tokenBalance(address _token) public view returns (uint256 _balance) {
        return IERC20(_token).balanceOf(address(this));
    }

    /////////////////////
    // WRITE FUNCTIONS //
    /////////////////////

    // Step 1: Stake root into staked root
    function prepare() onlyWhitelisted() public returns (bool _success) {
        address _xSH33P = address(xSH33P);
        uint256 _amount = tokenBalance(address(SH33P));

        totalTokensStaked += _amount;

        SH33P.approve(_xSH33P, MAX_UINT);
        SH33PToken.stake(_amount);
        
        emit onStakeRootToken(msg.sender, _xSH33P, _amount, block.timestamp);
        return true;
    }

    // Step 2: Add staked root to drip pool of vault
    function boost() onlyWhitelisted() public returns (bool _success) {
        address _vault = address(vault);
        uint256 _amount = tokenBalance(address(xSH33P));

        totalRewardsDistributed += _amount;
        
        xSH33P.approve(_vault, MAX_UINT);
        vault.donate(_amount);
        
        emit onDepositToDripPool(_amount, block.timestamp);
        return true;
    }
}