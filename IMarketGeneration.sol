// SPDX-License-Identifier: U-U-U-UPPPPP!!!
pragma solidity ^0.7.4;

interface IMarketGeneration {
    function contribution(address) external view returns (uint256);
    function totalContribution() external view returns (uint256);
}