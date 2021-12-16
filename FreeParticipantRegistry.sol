// SPDX-License-Identifier: U-U-U-UPPPPP!!!
pragma solidity ^0.7.4;

import './Ownable.sol';

contract FreeParticipantRegistry is Ownable {
    address transferGate;
    mapping (address => bool) public freeParticipantControllers;
    mapping (address => bool) public freeParticipant;


    function setFreeParticipantController(address freeParticipantController, bool allow) public onlyOwner
    {
        freeParticipantControllers[freeParticipantController] = allow;
    }

    function setFreeParticipant(address participant, bool free) public onlyOwner
    {
        freeParticipant[participant] = free;
    }
}