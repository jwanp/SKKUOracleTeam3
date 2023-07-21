
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol"; 

contract Token is ERC20, Ownable { 
    uint256 public s_maxSupply = 100;
    constructor() ERC20("SKKUOracleTeam3test2", "SOTt2") {
        _mint(msg.sender, s_maxSupply * 10 ** uint(decimals()));
    }

    function decimals() public view virtual override(ERC20) returns (uint8) {
        return 0;
    }
    function _mint(address to, uint256 amount)
        internal
        override(ERC20)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20)
    {
        super._burn(account, amount);
    }

    // Mint function - 컨트랙트 소유자만 호출 가능
    function mint(address to, uint256 amount) external onlyOwner { // onlyOwner 제한
        _mint(to, amount  * 10 ** uint(decimals()));
    }

    // Burn function - 컨트랙트 소유자만 호출 가능
    function burn(uint256 amount) external onlyOwner { // onlyOwner 제한
        _burn(msg.sender, amount  * 10 ** uint(decimals()));
    }

}
