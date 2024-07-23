// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

abstract contract TransferUtilities {

    function _safeTransfer(address tokenAddress, address to, uint256 value) internal {
        if(value == 0) {
            return;
        }
        if(to == address(this)) {
            return;
        }
        if(tokenAddress == address(0)) {
            require(_sendETH(to, value), 'FARMING: TRANSFER_FAILED');
            return;
        }
        if(to == address(0)) {
            return _safeBurn(tokenAddress, value);
        }
        (bool success, bytes memory data) = tokenAddress.call(abi.encodeWithSelector(IERC20(address(0)).transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'FARMING: TRANSFER_FAILED');
    }

    function _safeBurn(address erc20TokenAddress, uint256 value) internal {
        (bool result, bytes memory returnData) = erc20TokenAddress.call(abi.encodeWithSelector(0x42966c68, value));//burn(uint256)
        result = result && (returnData.length == 0 || abi.decode(returnData, (bool)));
        if(!result) {
            (result, returnData) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, address(0), value));
            result = result && (returnData.length == 0 || abi.decode(returnData, (bool)));
        }
        if(!result) {
            (result, returnData) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, 0x000000000000000000000000000000000000dEaD, value));
            result = result && (returnData.length == 0 || abi.decode(returnData, (bool)));
        }
        if(!result) {
            (result, returnData) = erc20TokenAddress.call(abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, 0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD, value));
            result = result && (returnData.length == 0 || abi.decode(returnData, (bool)));
        }
    }

    function _sendETH(address to, uint256 value) internal returns(bool) {
        assembly {
            let res := call(gas(), to, value, 0, 0, 0, 0)
        }
        return true;
    }
}