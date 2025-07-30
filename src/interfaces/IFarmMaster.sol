// SPDX-License-Identifier: GPL-3.0
// Authored by Plastic Digits
pragma solidity ^0.8.23;

import {IERC20MintableBurnable} from "./IERC20MintableBurnable.sol";

interface IFarmMaster {
    //Address of the yield token YTKN (eg: CAKE)
    function ytkn() external returns (IERC20MintableBurnable ytkn);
    //Current emission rate of YTKN, may update
    function ytknPerSecond() external returns (uint256 ytknPerSecond);
    // Total allocation points. Sum of all allocation points in all pools.
    function totalAllocPoint() external returns (uint32 totalAllocPoint);
    // The timestamp number when YTKN mining starts.
    function startTimestamp() external returns (uint256 startTimestamp);
    // The number of pools in the FarmMaster.
    function poolLength() external returns (uint256 poolLength);
    //Get multiplier from start to end timestamp
    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) external returns (uint256 multiplier);
    //Pending tokens to claim for user
    function pendingYtkn(
        uint256 _pid,
        address _user
    ) external view returns (uint256);

    //Deposit asset for pid to earn YTKN yield.
    function deposit(uint256 _pid, uint256 _amount) external;
    //Withdraw asset from pid to stop earning YTKN yield.
    function withdraw(uint256 _pid, uint256 _amount) external;
    //Claim pending YTKN.
    function claim(uint256 _pid) external;
}
