// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface ITokenTaxesReceiver {
    function taxesArrived(uint256 amount, uint256 updatedBalance) external;
}