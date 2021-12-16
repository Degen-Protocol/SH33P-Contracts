// SPDX-License-Identifier: U-U-U-UPPPPP!!!
pragma solidity 0.7.4;

import "./Context.sol";
 
contract PresaleWhitelist is Context {
    address private _owner;

    bool active = true;

    mapping(address => bool) public whitelist;

    event WhitelistedAddressAdded(address addr);
    event WhitelistedAddressRemoved(address addr);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function whitelistOperator() public view returns (address) {
        return _owner;
    }

    modifier onlyOperator() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    modifier onlyWhitelisted() {
        if(active){
            require(whitelist[msg.sender], 'not whitelisted');
        }
        _;
    }

    function activateDeactivateWhitelist() public onlyOperator {
        active = !active;
    }

    function addAddressToWhitelist(address addr) public onlyOperator returns(bool success) {
        if (!whitelist[addr]) {
            whitelist[addr] = true;
            emit WhitelistedAddressAdded(addr);
            success = true;
        }
    }

    function addAddressesToWhitelist(address[] calldata addrs) public onlyOperator returns(bool success) {
        for (uint256 i = 0; i < addrs.length; i++) {
            if (addAddressToWhitelist(addrs[i])) {
                success = true;
            }
        }
    }

    function removeAddressFromWhitelist(address addr) onlyOperator public returns(bool success) {
        if (whitelist[addr]) {
            whitelist[addr] = false;
            emit WhitelistedAddressRemoved(addr);
            success = true;
        }
    }

    function removeAddressesFromWhitelist(address[] calldata addrs) onlyOperator public returns(bool success) {
        for (uint256 i = 0; i < addrs.length; i++) {
            if (removeAddressFromWhitelist(addrs[i])) {
                success = true;
            }
        }
    }
}