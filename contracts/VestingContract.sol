// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IVestingContract.sol";

contract VestingContract is IVestingContract {

    struct VestingInfo {
        uint256 startingFrom;
        uint256 interval;
        uint256 tranches;
    }

    struct VestingInput {
        VestingInfo info;
        address[] owners;
        uint256[] amounts;
    }

    struct Vesting {
        uint256 infoIndex;
        uint256[] timestamps;
        uint256[] amounts;
    }

    uint256 private constant ONE_HUNDRED = 1e18;

    address public rewardToken;

    mapping(address => Vesting) private vestingOf;

    VestingInfo[] public infos;

    constructor(address _rewardToken, VestingInput[] memory inputs) {
        _setRewardToken(_rewardToken);
        for(uint256 i = 0; i < inputs.length; i++) {
            VestingInput memory input = inputs[i];
            uint256 infoIndex = infos.length;
            infos.push(input.info);
            for(uint256 z = 0; z < input.owners.length; z++) {
                Vesting storage vesting = vestingOf[input.owners[z]];
                vesting.infoIndex = infoIndex;
                vesting.amounts.push(input.amounts[z]);
            }
        }
    }

    function completeInitialization() external override {
        _setRewardToken(msg.sender);
    }

    function claim(address owner) external returns (uint256 amount) {
        return _claim(rewardToken, owner, block.timestamp);
    }

    function claimBatch(address[] calldata owners) external returns (uint256[] memory amounts) {
        amounts = new uint256[](owners.length);
        address token = rewardToken;
        uint256 blockTimestamp = block.timestamp;
        for(uint256 i = 0; i < owners.length; i++) {
            amounts[i] = _claim(token, owners[i], blockTimestamp);
        }
    }

    function _claim(address token, address owner, uint256 blockTimestamp) private returns(uint256 amount) {
        if(token == address(0)) {
            return 0;
        }
        Vesting storage vesting = _prepareVesting(owner);
        if(vesting.amounts.length == 0) {
            return 0;
        }
        uint256[] memory timestamps = vesting.timestamps;
        for(uint256 i = 0; i < timestamps.length; i++) {
            if(timestamps[i] == 0) {
                continue;
            }
            if(blockTimestamp < timestamps[i]) {
                break;
            }
            vesting.timestamps[i] = 0;
            amount += vesting.amounts[i];
        }
        if(amount != 0) {
            _safeTransfer(token, owner, amount);
        }
    }

    function _prepareVesting(address owner) private returns(Vesting storage vesting) {
        vesting = vestingOf[owner];
        if(vesting.amounts.length > 0 && vesting.timestamps.length == 0) {
            uint256 amount = vesting.amounts[0];
            vesting.amounts.pop();
            VestingInfo memory info = infos[vesting.infoIndex];
            uint256 splittedAmount = amount / info.tranches;
            uint256 startingFrom = info.startingFrom;
            startingFrom = startingFrom == 0 ? block.timestamp : startingFrom;
            for(uint256 i = 0; i < info.tranches; i++) {
                vesting.timestamps.push(startingFrom + (info.interval * i));
                vesting.amounts.push(splittedAmount);
            }
            vesting.amounts[vesting.amounts.length - 1] = (amount - (splittedAmount * (info.tranches - 1)));
        }
    }

    function _setRewardToken(address token) private {
        require(rewardToken == address(0));
        rewardToken = token;
    }

    function _safeTransfer(address erc20TokenAddress, address to, uint256 value) private {
        bytes memory returnData = _call(erc20TokenAddress, abi.encodeWithSelector(IERC20(erc20TokenAddress).transfer.selector, to, value));
        require(returnData.length == 0 || abi.decode(returnData, (bool)), 'TRANSFER_FAILED');
    }

    function _call(address location, bytes memory payload) private returns(bytes memory returnData) {
        assembly {
            let result := call(gas(), location, 0, add(payload, 0x20), mload(payload), 0, 0)
            let size := returndatasize()
            returnData := mload(0x40)
            mstore(returnData, size)
            let returnDataPayloadStart := add(returnData, 0x20)
            returndatacopy(returnDataPayloadStart, 0, size)
            mstore(0x40, add(returnDataPayloadStart, size))
            switch result case 0 {revert(returnDataPayloadStart, size)}
        }
    }
}