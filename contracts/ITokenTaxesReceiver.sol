// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITokenTaxesReceiver {
    function taxesArrived(address from, address to, uint256 amount, uint256 updatedBalance) external;
}