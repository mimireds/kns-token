// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./ITokenTaxesReceiver.sol";
import "./TransferUtilities.sol";
import "./IUniswapV2.sol";
import "./IWETH.sol";
import "@ethereans-labs/protocol/contracts/model/IPriceOracle.sol";

contract TokenTaxesReceiver is ITokenTaxesReceiver, TransferUtilities {

    uint256 private constant FULL_PRECISION = 1e18;
    address private constant DEAD_ADDRESS = 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD;

    address public immutable owner = msg.sender;

    address public tokenAddress;

    uint256 public reservedBalance;

    uint256[] private _thresholds;
    uint256[] private _amounts;
    address[][] private _receivers;
    mapping(uint256 => bool) private _thresholdCalled;

    uint256 public tolerancePercentage;

    uint256 public nextOperationInterval;
    uint256 public nextOperation;
    uint256 public lastThreshold;

    uint256 public balance;

    address public teamWallet;
    uint256 public teamPercentage;

    address public uniswapV2RouterAddress;
    address public wethAddress;

    uint256 public minAmountForSwap;

    address public priceOracleAddress;

    constructor(uint256[] memory thresholds, uint256[] memory amounts, address[][] memory receivers, address _teamWallet, uint256 _teamPercentage, address _uniswapV2RouterAddress, uint256 _minAmountForSwap) {
        require((_thresholds = thresholds).length == (_amounts = amounts).length && amounts.length == receivers.length);
        for(uint256 i = 0; i < receivers.length; i++) {
            require(i == 0 || thresholds[i] < thresholds[i - 1], "DESC");
            receivers[i][0] = receivers[i][0] == address(0) ? address(this) : receivers[i][0] == DEAD_ADDRESS ? address(0) : receivers[i][0];
        }
        _receivers = receivers;
        teamWallet = _teamWallet;
        teamPercentage = _teamPercentage;
        minAmountForSwap = _minAmountForSwap;
        wethAddress = IUniswapV2Router02(uniswapV2RouterAddress = _uniswapV2RouterAddress).WETH();
    }

    function taxesArrived(uint256 amount, uint256 updatedBalance) external {

        if(_tryInit(updatedBalance)) {
            return;
        }

        uint256 teamTokens = _calculatePercentage(amount, teamPercentage);
        _safeTransfer(tokenAddress, teamWallet, teamTokens);

        balance += (amount - teamTokens);

        _checkMinAmountForSwap();

        _tryNextOperation(_marketCap());
    }

    function setOracle(address _priceOracleAddress) external {
        require(msg.sender == owner);
        priceOracleAddress = _priceOracleAddress;
    }

    function flushWeth() external {
        require(msg.sender == owner);
        IWETH weth = IWETH(wethAddress);
        uint256 balanceOf = weth.balanceOf(address(this));
        if(balanceOf != 0) {
            weth.withdraw(balanceOf);
            owner.call{value : address(this).balance}("");
        }
    }

    receive() external payable {}

    function _tryInit(uint256 updatedBalance) private returns (bool exit) {
        address _tokenAddress = tokenAddress;
        require(msg.sender == _tokenAddress || _tokenAddress == address(0));
        if(exit = _tokenAddress == address(0)) {
            tokenAddress = msg.sender;
            reservedBalance = updatedBalance;
        }
    }

    function _tryNextOperation(uint256 marketCap) private {
        uint256[] memory thresholds = _thresholds;
        for(uint256 i = 0; i < thresholds.length; i++) {
            uint256 threshold = thresholds[i];
            if(threshold <= (marketCap - _calculatePercentage(marketCap, tolerancePercentage)) && !_thresholdCalled[i]) {
                if(i < lastThreshold && nextOperation > block.timestamp) {
                    return;
                }
                lastThreshold = i;
                nextOperation = block.timestamp + nextOperationInterval;
                _thresholdCalled[i] = true;
                _performOperation(_receivers[i], _amounts[i]);
                return;
            }
        }
    }

    function _performOperation(address[] memory receivers, uint256 amount) private {
        if(receivers[0] != address(this)) {
            reservedBalance -= amount;
            uint256 part = amount / receivers.length;
            for(uint256 i = 0; i < receivers.length - 1; i++) {
                _safeTransfer(tokenAddress, receivers[i], part);   
            }
            part *= (receivers.length - 1);
            _safeTransfer(tokenAddress, receivers[receivers.length - 1], amount - part);
            return;
        }
        
        uint256 _balance = balance;
        balance = 0;
        IERC20 weth = IERC20(wethAddress);
        uint256 balanceOf = weth.balanceOf(address(this));
        if(balanceOf != 0) {
            address _uniswapV2RouterAddress = uniswapV2RouterAddress;
            if(balanceOf < weth.allowance(address(this), _uniswapV2RouterAddress)) {
                weth.approve(_uniswapV2RouterAddress, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
            }
            address[] memory path = new address[](2);
            path[0] = wethAddress;
            path[1] = tokenAddress;
            IERC20 token = IERC20(tokenAddress);
            uint256 balanceBefore = token.balanceOf(address(this));
            IUniswapV2Router02(_uniswapV2RouterAddress).swapExactTokensForTokensSupportingFeeOnTransferTokens(balanceOf, 0, path, address(this), block.timestamp + 10000);
            _balance += (token.balanceOf(address(this)) - balanceBefore);
        }
        _safeTransfer(tokenAddress, address(0), _balance);
    }

    function _marketCap() private view returns (uint256) {
        return IERC20(tokenAddress).totalSupply() * IPriceOracle(priceOracleAddress).price();
    }

    function _calculatePercentage(uint256 total, uint256 percentage) internal pure returns (uint256) {
        return (total * ((percentage * 1e18) / FULL_PRECISION)) / 1e18;
    }

    function _checkMinAmountForSwap() private {
        uint256 _balance = balance;
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2RouterAddress);
        address[] memory path = new address[](2);
        path[0] = tokenAddress;
        path[1] = wethAddress;
        if(router.getAmountsOut(_balance, path)[0] < minAmountForSwap) {
            return;
        }
        IERC20 token = IERC20(tokenAddress);
        if(_balance < token.allowance(address(this), address(router))) {
            token.approve(address(router), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        }
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(_balance, 0, path, address(this), block.timestamp + 1000);
        balance = 0;
    }
}