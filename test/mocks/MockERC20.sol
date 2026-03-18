// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory _tokenName, string memory _tokenSymbol) ERC20(_tokenName, _tokenSymbol) {}

    function mint(address who, uint256 amount) public {
        _mint(who, amount);
    }
}
