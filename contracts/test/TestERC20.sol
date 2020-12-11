pragma solidity ^0.6.12;

import "@openzeppelinV3/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 _decimals) public ERC20(name, symbol) {
        _setupDecimals(_decimals);
    }

    function mint(uint256 amount) public {
        _mint(_msgSender(), amount);
    }

}