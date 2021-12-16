// SPDX-License-Identifier: MIT
pragma solidity 0.7.4;

import './Address.sol';
import './SafeMath.sol';
import './SafeERC20.sol';

import './IERC20.sol';
import './IPancakeRouter01.sol';

import './Ownable.sol';

contract Vault is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    // Import the BEP20 token interface
    IERC20 public stakingToken;
    IERC20 public buybackToken; // The token being bought back...
    IERC20 public wbnb;

    IPancakeRouter01 public uniswapV2Router;
    IPancakeRouter01 public tokenUniswapV2Router;
    
    /////////////////////////////////
    // CONFIGURABLES AND VARIABLES //
    /////////////////////////////////
    
    // Store the token address and the reserve address
    address public tokenAddress;
    address payable public bnbReceiver;
    
    // Store the number of unique users and total Tx's 
    uint public users;
    uint public totalTxs;
    
    // Store the starting time & block number and the last payout time
    uint public lastPayout; // What time was the last payout (timestamp)?
    
    // Store the details of total deposits & claims
    uint public totalClaims;
    uint public totalDeposits;

    // Store the total drip pool balance and rate
    uint  public dripPoolBalance;
    uint8 public dripRate;

    // 10% fee on deposit and withdrawal
    uint8 constant internal divsFee = 10;
    uint256 constant internal magnitude = 2 ** 64;
    
    // How many portions of the fees does each receiver get?
    uint public forPool;
    uint public forDivs;

    // Rebase and payout frequency
    uint256 constant public rebaseFrequency = 6 hours;
    uint256 constant public payoutFrequency = 2 seconds;
    
    // Timestamp of last rebase
    uint256 public lastRebaseTime;
    
    // Current total tokens staked, and profit per share
    uint256 private currentTotalStaked;
    uint256 private profitPerShare_;
    
    ////////////////////////////////////
    // MODIFIERS                      //
    ////////////////////////////////////

    // Only holders - Caller must have funds in the vault
    modifier onlyHolders {
        require(myTokens() > 0);
        _;
    }
    
    // Only earners - Caller must have some earnings
    modifier onlyEarners {
        require(myEarnings() > 0);
        _;
    }

    ////////////////////////////////////
    // ACCOUNT STRUCT                 //
    ////////////////////////////////////

    struct Account {
        uint deposited;
        uint withdrawn;
        uint compounded;
        uint rewarded;
        uint contributed;
        uint transferredShares;
        uint receivedShares;
        
        uint xInvested;
        uint xCompounded;
        uint xRewarded;
        uint xContributed;
        uint xWithdrawn;
        uint xTransferredShares;
        uint xReceivedShares;
    }

    ////////////////////////////////////
    // MAPPINGS                       //
    ////////////////////////////////////

    mapping(address =>  int256) payoutsOf_;
    mapping(address => uint256) balanceOf_;
    mapping(address => Account) accountOf_;
    
    ////////////////////////////////////
    // EVENTS                         //
    ////////////////////////////////////
    
    event onDeposit( address indexed _user, uint256 _deposited,  uint256 tokensMinted, uint timestamp);
    event onWithdraw(address indexed _user, uint256 _liquidated, uint256 tokensEarned, uint timestamp);
    event onCompound(address indexed _user, uint256 _compounded, uint256 tokensMinted, uint timestamp);
    event onWithdraw(address indexed _user, uint256 _withdrawn,                        uint timestamp);
    event onTransfer(address indexed from,  address indexed to,  uint256 tokens,       uint timestamp);
    event onUpdate(address indexed _user, uint256 invested, uint256 tokens, uint256 soldTokens, uint timestamp);
    
    event onRebase(uint256 balance, uint256 timestamp);
    
    event onDonate(address indexed from, uint256 amount, uint timestamp);
    event onDonateBNB(address indexed from, uint256 amount, uint timestamp);
    
    event onSetFeeSplit(uint _pool, uint _divs, uint256 timestamp);
    
    ////////////////////////////////////
    // CONSTRUCTOR                    //
    ////////////////////////////////////

    constructor(address _tokenAddress, uint8 _dripRate) Ownable() {
        require(_tokenAddress != address(0) && Address.isContract(_tokenAddress), "INVALID_ADDRESS");
        
        tokenAddress = _tokenAddress;
        stakingToken = IERC20(_tokenAddress);
        
        bnbReceiver = msg.sender;

        // Set Drip Rate and last payout date (first time around)...
        dripRate = _dripRate;
        lastPayout = (block.timestamp);
        
        // Fee portions
        forPool = 8;
        forDivs = 2;
    }
    
    ////////////////////////////////////
    // FALLBACK                       //
    ////////////////////////////////////
    
    receive() payable external {
        Address.sendValue(bnbReceiver, msg.value);
        emit onDonateBNB(msg.sender, msg.value, block.timestamp);
    }
    
    ////////////////////////////////////
    // WRITE FUNCTIONS                //
    ////////////////////////////////////

    // Donate
    function donate(uint _amount) public returns (uint256) {
        
        // Move the tokens from the caller's wallet to this contract.
        require(stakingToken.transferFrom(msg.sender, address(this), _amount));
        
        // Add the tokens to the drip pool balance
        dripPoolBalance += _amount;
        
        // Tell the network, successful function - how much in the pool now?
        emit onDonate(msg.sender, _amount, block.timestamp);
        return dripPoolBalance;
    }

    // Deposit
    function deposit(uint _amount) public returns (uint256)  {
        return depositTo(msg.sender, _amount);
    }

    // DepositTo
    function depositTo(address _user, uint _amount) public returns (uint256)  {
        
        // Move the tokens from the caller's wallet to this contract.
        require(stakingToken.transferFrom(msg.sender, address(this), _amount));
        
        // Add the deposit to the totalDeposits...
        totalDeposits += _amount;
        
        // Then actually call the deposit method...
        uint amount = _depositTokens(_user, _amount);
        
        // Update the leaderboard...
        emit onUpdate(_user, accountOf_[_user].deposited, balanceOf_[_user], accountOf_[_user].withdrawn, block.timestamp);
        
        // Then trigger a distribution for everyone, kind soul!
        distribute();
        
        // Successful function - how many 'shares' (tokens) are the result?
        return amount;
    }

    // Compound
    function compound() onlyEarners public {
         _compoundTokens();
    }
    
    // Harvest
    function harvest() onlyEarners public {
        address _user = msg.sender;
        uint256 _dividends = myEarnings();
        
        // Calculate the payout, add it to the user's total paid out accounting...
        payoutsOf_[_user] += (int256) (_dividends * magnitude);
        
        // Pay the user their tokens to their wallet
        stakingToken.transfer(_user,_dividends);

        // Update accounting for user/total withdrawal stats...
        accountOf_[_user].withdrawn = SafeMath.add(accountOf_[_user].withdrawn, _dividends);
        accountOf_[_user].xWithdrawn += 1;
        
        // Update total Tx's and claims stats
        totalTxs += 1;
        totalClaims += _dividends;

        // Tell the network...
        emit onWithdraw(_user, _dividends, block.timestamp);

        // Trigger a distribution for everyone, kind soul!
        distribute();
    }

    // Withdraw
    function withdraw(uint256 _amount) onlyHolders public {
        address _user = msg.sender;
        require(_amount <= balanceOf_[_user]);
        
        // Calculate dividends and 'shares' (tokens)
        uint256 _undividedDividends = SafeMath.mul(_amount, divsFee) / 100;
        uint256 _taxedTokens = SafeMath.sub(_amount, _undividedDividends);

        // Subtract amounts from user and totals...
        currentTotalStaked = SafeMath.sub(currentTotalStaked, _amount);
        balanceOf_[_user] = SafeMath.sub(balanceOf_[_user], _amount);

        // Update the payment ratios for the user and everyone else...
        int256 _updatedPayouts = (int256) (profitPerShare_ * _amount + (_taxedTokens * magnitude));
        payoutsOf_[_user] -= _updatedPayouts;

        // Serve dividends between the drip and instant divs (4:1)...
        allocateFees(_undividedDividends);
        
        // Tell the network, and trigger a distribution
        emit onWithdraw( _user, _amount, _taxedTokens, block.timestamp);
        
        // Update the leaderboard...
        emit onUpdate(_user, accountOf_[_user].deposited, balanceOf_[_user], accountOf_[_user].withdrawn, block.timestamp);
        
        // Trigger a distribution for everyone, kind soul!
        distribute();
    }

    // Transfer
    function transfer(address _to, uint256 _amount) onlyHolders external returns (bool) {
        return _transferTokens(_to, _amount);
    }
    
    ////////////////////////////////////
    // VIEW FUNCTIONS                 //
    ////////////////////////////////////

    function myTokens() public view returns (uint256) {return balanceOf(msg.sender);}
    function myEarnings() public view returns (uint256) {return dividendsOf(msg.sender);}

    function balanceOf(address _user) public view returns (uint256) {return balanceOf_[_user];}
    function tokenBalance(address _user) public view returns (uint256) {return _user.balance;}
    function totalBalance() public view returns (uint256) {return stakingToken.balanceOf(address(this));}
    function totalSupply() public view returns (uint256) {return currentTotalStaked;}
    
    function dividendsOf(address _user) public view returns (uint256) {
        return (uint256) ((int256) (profitPerShare_ * balanceOf_[_user]) - payoutsOf_[_user]) / magnitude;
    }

    function sellPrice() public pure returns (uint256) {
        uint256 _tokens = 1e18;
        uint256 _dividends = SafeMath.div(SafeMath.mul(_tokens, divsFee), 100);
        uint256 _taxedTokens = SafeMath.sub(_tokens, _dividends);
        return _taxedTokens;
    }

    function buyPrice() public pure returns (uint256) {
        uint256 _tokens = 1e18;
        uint256 _dividends = SafeMath.div(SafeMath.mul(_tokens, divsFee), 100);
        uint256 _taxedTokens = SafeMath.add(_tokens, _dividends);
        return _taxedTokens;
    }

    function calculateSharesReceived(uint256 _amount) public pure returns (uint256) {
        uint256 _divies = SafeMath.div(SafeMath.mul(_amount, divsFee), 100);
        uint256 _remains = SafeMath.sub(_amount, _divies);
        uint256 _result = _remains;
        return  _result;
    }

    function calculateTokensReceived(uint256 _amount) public view returns (uint256) {
        require(_amount <= currentTotalStaked);
        uint256 _tokens  = _amount;
        uint256 _divies  = SafeMath.div(SafeMath.mul(_tokens, divsFee), 100);
        uint256 _remains = SafeMath.sub(_tokens, _divies);
        return _remains;
    }

    function accountOf(address _user) public view returns (uint256[14] memory){
        Account memory a = accountOf_[_user];
        uint256[14] memory accountArray = [
            a.deposited, 
            a.withdrawn, 
            a.rewarded, 
            a.compounded,
            a.contributed, 
            a.transferredShares, 
            a.receivedShares, 
            a.xInvested, 
            a.xRewarded, 
            a.xContributed, 
            a.xWithdrawn, 
            a.xTransferredShares, 
            a.xReceivedShares, 
            a.xCompounded
        ];
        return accountArray;
    }

    function dailyEstimate(address _user) public view returns (uint256) {
        uint256 share = dripPoolBalance.mul(dripRate).div(100);
        return (currentTotalStaked > 0) ? share.mul(balanceOf_[_user]).div(currentTotalStaked) : 0;
    }

    /////////////////////////////////
    // PUBLIC OWNER-ONLY FUNCTIONS //
    /////////////////////////////////
    
    function setFeeSplit(uint256 _pool, uint256 _divs) public onlyOwner returns (bool _success) {
        
        require(_pool.add(_divs) == 10, "TEN_PORTIONS_REQUIRE_DIVISION");
        
        // Set the new values...
        forPool = _pool;
        forDivs = _divs;
        
        // Tell the network, successful function!
        emit onSetFeeSplit(_pool, _divs, block.timestamp);
        return true;
    }

    ////////////////////////////////////
    // PRIVATE / INTERNAL FUNCTIONS   //
    ////////////////////////////////////

    // Allocate fees (private method)
    function allocateFees(uint fee) private {
        uint256 _onePiece = fee.div(10);
        
        uint256 _forPool = (_onePiece.mul(forPool)); // for the Drip Pool
        uint256 _forDivs = (_onePiece.mul(forDivs)); // for Instant Divs
        
        dripPoolBalance = dripPoolBalance.add(_forPool);
        
        // If there's more than 0 tokens staked in the vault...
        if (currentTotalStaked > 0) {
            
            // Distribute those instant divs...
            profitPerShare_ = SafeMath.add(profitPerShare_, (_forDivs * magnitude) / currentTotalStaked);
        } else {
            // Otherwise add the divs portion to the drip pool balance.
            dripPoolBalance += _forDivs;
        }
    }
    
    // Distribute (private method)
    function distribute() private {
        
        uint _currentTimestamp = (block.timestamp);
        
        // Log a rebase, if it's time to do so...
        if (_currentTimestamp.safeSub(lastRebaseTime) > rebaseFrequency) {
            
            // Tell the network...
            emit onRebase(totalBalance(), _currentTimestamp);
            
            // Update the time this was last updated...
            lastRebaseTime = _currentTimestamp;
        }

        // If there's any time difference...
        if (SafeMath.safeSub(_currentTimestamp, lastPayout) > payoutFrequency && currentTotalStaked > 0) {
            
            // Calculate shares and profits...
            uint256 share = dripPoolBalance.mul(dripRate).div(100).div(24 hours);
            uint256 profit = share * _currentTimestamp.safeSub(lastPayout);
            
            // Subtract from drip pool balance and add to all user earnings
            dripPoolBalance = dripPoolBalance.safeSub(profit);
            profitPerShare_ = SafeMath.add(profitPerShare_, (profit * magnitude) / currentTotalStaked);
            
            // Update the last payout timestamp
            lastPayout = _currentTimestamp;
        }
    }
    
    // Deposit Tokens (internal method)
    function _depositTokens(address _recipient, uint256 _amount) internal returns (uint256) {
        
        // If the recipient has zero activity, they're new - COUNT THEM!!!
        if (accountOf_[_recipient].deposited == 0 && accountOf_[_recipient].receivedShares == 0) {
            users += 1;
        }

        // Count this tx...
        totalTxs += 1;

        // Calculate dividends and 'shares' (tokens)
        uint256 _undividedDividends = SafeMath.mul(_amount, divsFee) / 100;
        uint256 _tokens = SafeMath.sub(_amount, _undividedDividends);
        
        // Tell the network...
        emit onDeposit(_recipient, _amount, _tokens, block.timestamp);

        // There needs to be something being added in this call...
        require(_tokens > 0 && SafeMath.add(_tokens, currentTotalStaked) > currentTotalStaked);
        if (currentTotalStaked > 0) {
            currentTotalStaked += _tokens;
        } else {
            currentTotalStaked = _tokens;
        }
        
        // Allocate fees, and balance to the recipient
        allocateFees(_undividedDividends);
        balanceOf_[_recipient] = SafeMath.add(balanceOf_[_recipient], _tokens);
        
        // Updated payouts...
        int256 _updatedPayouts = (int256) (profitPerShare_ * _tokens);
        
        // Update stats...
        payoutsOf_[_recipient] += _updatedPayouts;
        accountOf_[_recipient].deposited += _amount;
        accountOf_[_recipient].xInvested += 1;

        // Successful function - how many "shares" generated?
        return _tokens;
    }
    
    // Compound (internal method)
    function _compoundTokens() internal returns (uint256) {
        address _user = msg.sender;
        
        // Quickly roll the caller's earnings into their payouts
        uint256 _dividends = dividendsOf(_user);
        payoutsOf_[_user] += (int256) (_dividends * magnitude);
        
        // Then actually trigger the deposit method
        // (NOTE: No tokens required here, earnings are tokens already within the contract)
        uint256 _tokens = _depositTokens(msg.sender, _dividends);
        
        // Tell the network...
        emit onCompound(_user, _dividends, _tokens, block.timestamp);

        // Then update the stats...
        accountOf_[_user].compounded = SafeMath.add(accountOf_[_user].compounded, _dividends);
        accountOf_[_user].xCompounded += 1;
        
        // Update the leaderboard...
        emit onUpdate(_user, accountOf_[_user].deposited, balanceOf_[_user], accountOf_[_user].withdrawn, block.timestamp);
        
        // Then trigger a distribution for everyone, you kind soul!
        distribute();
        
        // Successful function!
        return _tokens;
    }
    
    // Transfer Tokens (internal method)
    function _transferTokens(address _recipient, uint256 _amount) internal returns (bool _success) {
        address _sender = msg.sender;
        require(_amount <= balanceOf_[_sender]);
        
        // Harvest any earnings before transferring, to help with cleaner accounting
        if (myEarnings() > 0) {
            harvest();
        }
        
        // "Move" the tokens...
        balanceOf_[_sender] = SafeMath.sub(balanceOf_[_sender], _amount);
        balanceOf_[_recipient] = SafeMath.add(balanceOf_[_recipient], _amount);

        // Adjust payout ratios to match the new balances...
        payoutsOf_[_sender] -= (int256) (profitPerShare_ * _amount);
        payoutsOf_[_recipient] += (int256) (profitPerShare_ * _amount);

        // If the recipient has zero activity, they're new - COUNT THEM!!!
        if (accountOf_[_recipient].deposited == 0 && accountOf_[_recipient].receivedShares == 0) {
            users += 1;
        }
        
        // Update stats...
        accountOf_[_sender].xTransferredShares += 1;
        accountOf_[_sender].transferredShares += _amount;
        accountOf_[_recipient].receivedShares += _amount;
        accountOf_[_recipient].xReceivedShares += 1;
        
        // Add this to the Tx counter...
        totalTxs += 1;

        // Tell the network, successful function!
        emit onTransfer(_sender, _recipient, _amount, block.timestamp);
        
        // Update the leaderboard for sender...
        emit onUpdate(_sender, accountOf_[_sender].deposited, balanceOf_[_sender], accountOf_[_sender].withdrawn, block.timestamp);
        
        // Update the leaderboard for recipient...
        emit onUpdate(_recipient, accountOf_[_recipient].deposited, balanceOf_[_recipient], accountOf_[_recipient].withdrawn, block.timestamp);
        
        return true;
    }
}