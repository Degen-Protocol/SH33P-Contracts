// SPDX-License-Identifier: U-U-U-UPPPPP!!!
pragma solidity ^0.7.4;

import "./IMarketDistribution.sol";
import "./IMarketGeneration.sol";
import "./RootedToken.sol";
import "./RootedTransferGate.sol";
import "./TokensRecoverable.sol";
import "./SafeMath.sol";
import "./IERC31337.sol";
import "./IERC20.sol";
import "./IPancakeRouter02.sol";
import "./IPancakeFactory.sol";
import "./IPancakePair.sol";
import "./SafeERC20.sol";

contract MarketDistribution is TokensRecoverable, IMarketDistribution {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IMarketGeneration public marketGeneration;
    IPancakeRouter02 pancakeRouter;
    IPancakeFactory pancakeFactory;
    RootedToken public rootedToken;
    IERC31337 public eliteToken;
    IERC20 public baseToken;

    IPancakePair public rootedEliteLP;
    IPancakePair public rootedBaseLP;

    address public burnPit;
    address public oneshotController;
    address public liquidityController;
    address public multisplitterAddress;

    bool public override distributionComplete;

    uint256 public immutable totalRooted = 1e24; // 1 Million, or dynamically set

    uint256 public totalBaseTokenCollected;
    uint256 public totalBoughtForContributors;

    uint256 public remainingMintableSupply;

    mapping (address => uint256) public claimTime;
    mapping (address => uint256) public totalClaim;
    mapping (address => uint256) public remainingClaim;
    
    uint256 public recoveryDate = block.timestamp + 2592000; // 1 Month
    
    uint16 public projectSetupPercent;
    uint16 public preBuyForContributorsPercent;
    uint16 public preBuyForMarketStabilizationPercent;

    uint256 public override vestingPeriodStartTime;
    uint256 public override vestingPeriodEndTime; 
    
    uint256 public vestingDuration;
    uint256 public rootedBottom;

    constructor(address _oneshotController, address _multisplitterAddress) {
        oneshotController = _oneshotController;
        multisplitterAddress = _multisplitterAddress;
    }

    function init(
        RootedToken _rootedToken, 
        IERC31337 _eliteToken, 
        address _burnPit, 
        address _liquidityController, 
        IPancakeRouter02 _pancakeRouter, 
        IMarketGeneration _marketGeneration, 
        uint256 _vestingDuration, 
        uint16 _projectSetupPercent, 
        uint16 _preBuyForContributorsPercent, 
        uint16 _preBuyForMarketStabilizationPercent) public ownerOnly() 
    {
        rootedToken = _rootedToken;
        eliteToken = _eliteToken;
        burnPit = _burnPit;
        baseToken = _eliteToken.wrappedToken();
        liquidityController = _liquidityController;
        pancakeRouter = _pancakeRouter;
        pancakeFactory = IPancakeFactory(_pancakeRouter.factory());
        marketGeneration = _marketGeneration;
        vestingDuration = (_vestingDuration * 1 days);
        projectSetupPercent = _projectSetupPercent;
        preBuyForContributorsPercent = _preBuyForContributorsPercent;
        preBuyForMarketStabilizationPercent = _preBuyForMarketStabilizationPercent;
    }

    function setupEliteRooted() public {
        rootedEliteLP = IPancakePair(pancakeFactory.getPair(address(eliteToken), address(rootedToken)));
        if (address(rootedEliteLP) == address(0)) {
            rootedEliteLP = IPancakePair(pancakeFactory.createPair(address(eliteToken), address(rootedToken)));
            require (address(rootedEliteLP) != address(0));
        }
    }

    function setupBaseRooted() public {
        rootedBaseLP = IPancakePair(pancakeFactory.getPair(address(baseToken), address(rootedToken)));
        if (address(rootedBaseLP) == address(0)) {
            rootedBaseLP = IPancakePair(pancakeFactory.createPair(address(baseToken), address(rootedToken)));
            require (address(rootedBaseLP) != address(0));
        }
    }

    function completeSetup() public ownerOnly() {
        require (address(rootedEliteLP) != address(0), "Rooted Elite pool is not created");
        require (address(rootedBaseLP) != address(0), "Rooted Base pool is not created");   

        eliteToken.approve(address(pancakeRouter), uint256(-1));
        rootedToken.approve(address(pancakeRouter), uint256(-1));
        baseToken.safeApprove(address(pancakeRouter), uint256(-1));
        baseToken.safeApprove(address(eliteToken), uint256(-1));
        rootedBaseLP.approve(address(pancakeRouter), uint256(-1));
        rootedEliteLP.approve(address(pancakeRouter), uint256(-1));
    }

    // baseToken = WBNB
    function distribute() public override {
        require (msg.sender == address(marketGeneration), "Unauthorized");
        require (!distributionComplete, "Distribution complete");
   
        vestingPeriodStartTime = block.timestamp;
        vestingPeriodEndTime = block.timestamp + vestingDuration;
        distributionComplete = true;

        totalBaseTokenCollected = baseToken.balanceOf(address(marketGeneration));
        baseToken.safeTransferFrom(msg.sender, address(this), totalBaseTokenCollected);  

        RootedTransferGate gate = RootedTransferGate(address(rootedToken.transferGate()));

        gate.setUnrestricted(true);
        rootedToken.mint(totalRooted);

        uint256 staffTokens = (250000000000000000000000);
        rootedToken.transfer(multisplitterAddress, staffTokens);

        createRootedEliteLiquidity();

        eliteToken.sweepFloor(address(this));
        eliteToken.depositTokens(baseToken.balanceOf(address(this)));
                
        buyTheBottom();
        preBuyForContributors();
        sellTheTop();

        // WBNB
        uint256 totalBase = totalBaseTokenCollected * projectSetupPercent / 10000;

        baseToken.transfer(oneshotController, totalBase);
        baseToken.transfer(liquidityController, baseToken.balanceOf(address(this)));

        createRootedBaseLiquidity();

        gate.setUnrestricted(false);
    }

    function createRootedEliteLiquidity() private {
        eliteToken.depositTokens(baseToken.balanceOf(address(this)));
        pancakeRouter.addLiquidity(address(eliteToken), address(rootedToken), eliteToken.balanceOf(address(this)), rootedToken.balanceOf(address(this)), 0, 0, address(this), block.timestamp);
    }

    function buyTheBottom() private {
        uint256 amount = totalBaseTokenCollected * preBuyForMarketStabilizationPercent / 10000;  
        uint256[] memory amounts = pancakeRouter.swapExactTokensForTokens(amount, 0, eliteRootedPath(), address(this), block.timestamp);        
        rootedBottom = amounts[1];
    }

    function sellTheTop() private {
        uint256[] memory amounts = pancakeRouter.swapExactTokensForTokens(rootedBottom, 0, rootedElitePath(), address(this), block.timestamp);
        uint256 eliteAmount = amounts[1];
        eliteToken.withdrawTokens(eliteAmount);
    }

    function preBuyForContributors() private {
        uint256 preBuyAmount = totalBaseTokenCollected * preBuyForContributorsPercent / 10000;
        uint256 eliteBalance = eliteToken.balanceOf(address(this));
        uint256 amount = preBuyAmount > eliteBalance ? eliteBalance : preBuyAmount;
        uint256[] memory amounts = pancakeRouter.swapExactTokensForTokens(amount, 0, eliteRootedPath(), address(this), block.timestamp);
        totalBoughtForContributors = amounts[1];
    }

    function createRootedBaseLiquidity() private {
        uint256 elitePerLpToken = eliteToken.balanceOf(address(rootedEliteLP)).mul(1e18).div(rootedEliteLP.totalSupply());
        uint256 lpAmountToRemove = baseToken.balanceOf(address(eliteToken)).mul(1e18).div(elitePerLpToken);
        
        (uint256 eliteAmount, uint256 rootedAmount) = pancakeRouter.removeLiquidity(address(eliteToken), address(rootedToken), lpAmountToRemove, 0, 0, address(this), block.timestamp);
        
        uint256 baseInElite = baseToken.balanceOf(address(eliteToken));
        uint256 baseAmount = eliteAmount > baseInElite ? baseInElite : eliteAmount;       
        
        eliteToken.withdrawTokens(baseAmount);
        pancakeRouter.addLiquidity(address(baseToken), address(rootedToken), baseAmount, rootedAmount, 0, 0, liquidityController, block.timestamp);
        rootedEliteLP.transfer(liquidityController, rootedEliteLP.balanceOf(address(this)));
        eliteToken.transfer(liquidityController, eliteToken.balanceOf(address(this)));
    }

    function eliteRootedPath() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = address(eliteToken);
        path[1] = address(rootedToken);
        return path;
    }

    function rootedElitePath() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = address(rootedToken);
        path[1] = address(eliteToken);
        return path;
    }
    
    function getTotalClaim(address account) public view returns (uint256) {
        uint256 contribution = marketGeneration.contribution(account);
        return contribution == 0 ? 0 : contribution.mul(totalBoughtForContributors).div(marketGeneration.totalContribution());
    }

    function claim(address account) public override {
        require (distributionComplete, "Distribution is not completed");
        require (msg.sender == address(marketGeneration), "Unauthorized");

        if (totalClaim[account] == 0){
            totalClaim[account] = remainingClaim[account] = getTotalClaim(account);
        }

        uint256 share = totalClaim[account];
        uint256 endTime = vestingPeriodEndTime > block.timestamp ? block.timestamp : vestingPeriodEndTime;

        require (claimTime[account] < endTime, "Already claimed");

        uint256 claimStartTime = claimTime[account] == 0 ? vestingPeriodStartTime : claimTime[account];
        share = (endTime.sub(claimStartTime)).mul(share).div(vestingDuration);
        claimTime[account] = block.timestamp;
        remainingClaim[account] -= share;
        rootedToken.transfer(account, share);
    }

    function canRecoverTokens(IERC20 token) internal override view returns (bool) {
        return block.timestamp > recoveryDate || token != rootedToken;
    }
}