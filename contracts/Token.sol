// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IWETH.sol";
import "./ITokenTaxesReceiver.sol";
import "./IUniswapV2.sol";
import "./IVestingContract.sol";

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }
}

contract Ownable is Context {
    address public owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address _owner) {
        emit OwnershipTransferred(address(0), owner = _owner);
    }

    modifier onlyOwner() {
        require(owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() external virtual onlyOwner {
        emit OwnershipTransferred(owner = address(0), address(0));
    }
}

contract Token is Context, IERC20, Ownable {
    using SafeMath for uint256;

    string public override constant name = unicode"The KryptoNite Show";
    string public override constant symbol = unicode"KRYPTO";
    uint8 public override constant decimals = 18;

    mapping (address => uint256) public override balanceOf;
    mapping (address => mapping (address => uint256)) public override allowance;
    mapping (address => bool) private _isExcludedFromFee;
    uint256 private enabled = 0;
    address public immutable taxWallet;
    uint256 public _buyTax = 0;
    uint256 public _sellTax = 0;
    
    uint256 public override totalSupply;
    
    address public immutable uniswapV2RouterAddress;
    address public immutable uniswapV2PairAddress;
    bool private tradingOpen = false;

    bool private _taxesArrivedIsCallable;

    constructor(address _owner, address _vestingContractAddress, address _uniswapV2RouterAddress, address _taxWallet, uint256 buyTax, uint256 sellTax, address[] memory accounts, uint256[] memory amounts, address[] memory excluded) payable Ownable(_owner) {
        IUniswapV2Router02 uniswapV2Router = IUniswapV2Router02(uniswapV2RouterAddress = _uniswapV2RouterAddress);
        address _wethAddress = uniswapV2Router.WETH();
        address _uniswapV2PairAddress = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), _wethAddress);
        _isExcludedFromFee[_uniswapV2RouterAddress];
        _isExcludedFromFee[uniswapV2PairAddress = _uniswapV2PairAddress] = true;
        _isExcludedFromFee[_owner] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[taxWallet = _taxWallet] = true;

        for(uint256 i = 0; i < excluded.length; i++) {
            _isExcludedFromFee[excluded[i]] = true;
        }

        _buyTax = buyTax;
        _sellTax = sellTax;

        uint256 _totalSupply = 0;
        for(uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            account = account != address(0) ? account : address(this);
            uint256 amount = amounts[i];
            balanceOf[account] = balanceOf[account].add(amount);
            _totalSupply = _totalSupply.add(amount);
            emit Transfer(address(0), account, amount);
        }
        totalSupply = _totalSupply;

        tradingOpen = true;

        uint256 taxWalletLength;
        assembly {
            taxWalletLength := extcodesize(_taxWallet)
        }
        _taxesArrivedIsCallable = true;
        _taxesArrivedIsCallable = taxWalletLength != 0 && _tryCallTaxArrived(_taxWallet, address(0), address(0), 0);

        try IVestingContract(_vestingContractAddress).completeInitialization() {} catch {}
    }

    function initLiquidityPool() external {
        require(IERC20(uniswapV2PairAddress).totalSupply() == 0);
        uint256 balanceETH = address(this).balance;
        uint256 balanceTokens = balanceOf[address(this)];
        if(balanceETH != 0 || balanceTokens != 0) {
            address _uniswapV2RouterAddress = uniswapV2RouterAddress;
            _approve(address(this), _uniswapV2RouterAddress, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
            IUniswapV2Router02(_uniswapV2RouterAddress).addLiquidityETH{value : balanceETH}(address(this), balanceTokens, 0, 0, owner, block.timestamp + 1000);
        }
    }

    function excludeFromFees(address[] memory wallets_) external onlyOwner {
        for (uint i = 0; i < wallets_.length; i++) {
            _isExcludedFromFee[wallets_[i]] = true;
        }
    }

    function enableTrading() external onlyOwner {
        require(!tradingOpen,"ERROR: Trading already open");
        tradingOpen = true;
    }

    function setTaxes(uint256 _newBuyTax, uint256 _newSellTax) external onlyOwner {
        _buyTax = _newBuyTax;
        _sellTax = _newSellTax;
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), allowance[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function burn(uint256 amount) external override {
        totalSupply = totalSupply.sub(amount, "ERC20: burn amount exceeds totalSupply");
        balanceOf[_msgSender()] = balanceOf[_msgSender()].sub(amount, "ERC20: burn amount exceeds balance");
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxAmount = 0;
        if (!_isExcludedFromFee[from] || !_isExcludedFromFee[to]) {
            if (from == uniswapV2PairAddress && to != uniswapV2RouterAddress && !_isExcludedFromFee[to]) {
                require(tradingOpen, "Trading not open");
                taxAmount = amount.mul(_buyTax).div(100);
            }

            if(to == uniswapV2PairAddress && !_isExcludedFromFee[from]) {
                taxAmount = amount.mul(_sellTax).div(100);
            }
        }

        if(taxAmount > 0) {
            address _taxWallet = taxWallet;
            balanceOf[_taxWallet] = balanceOf[_taxWallet].add(taxAmount);
            emit Transfer(from, _taxWallet, taxAmount);
            _tryCallTaxArrived(taxWallet, from, to, taxAmount);
        }

        uint256 amoutOut = amount.sub(taxAmount);

        balanceOf[from] = balanceOf[from].sub(amount);
        balanceOf[to] = balanceOf[to].add(amoutOut);
        emit Transfer(from, to, amoutOut);
    }

    function _tryCallTaxArrived(address _taxWallet, address from, address to, uint256 taxAmount) private returns (bool result) {
        if(_taxesArrivedIsCallable) {
            (result, ) = _taxWallet.call(abi.encodeWithSelector(ITokenTaxesReceiver(address(0)).taxesArrived.selector, from, to, taxAmount, balanceOf[_taxWallet]));
        }
    }
}