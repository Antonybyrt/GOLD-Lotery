// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {ERC20} from "lib/chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/ERC20.sol";

contract SGoldToken is ERC20 {
    address public minter;
    address public immutable owner;
    bool public minterTransferred;

    constructor(address _minter) ERC20("Sgold", "SGOLD") {
        minter = _minter;
        owner = msg.sender;
        minterTransferred = false;
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "Not authorized");
        _;
    }

    modifier onlyOwnerOrMinterIfNotTransferred() {
        if (!minterTransferred) {
            require(msg.sender == owner || msg.sender == minter, "Not authorized");
        } else {
            require(msg.sender == minter, "Not authorized");
        }
        _;
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyMinter {
        _burn(from, amount);
    }

    function updateMinter(address newMinter) external onlyOwnerOrMinterIfNotTransferred {
        minter = newMinter;
        minterTransferred = true;
    }
}

