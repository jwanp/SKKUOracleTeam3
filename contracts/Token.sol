// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol"; 

contract Token is ERC20, ERC20Permit, ERC20Votes, Ownable { 

    uint256 public s_maxSupply = 1000000000000000000000000;
    constructor() ERC20("Team3OracleToken", "T3OT") ERC20Permit("Token") {
        _mint(msg.sender, s_maxSupply);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }

    // Mint function - 컨트랙트 소유자만 호출 가능
    function mint(address to, uint256 amount) external onlyOwner { // onlyOwner 제한
        _mint(to, amount);
    }

    // Burn function - 컨트랙트 소유자만 호출 가능
    function burn(uint256 amount) external onlyOwner { // onlyOwner 제한
        _burn(msg.sender, amount);
    }
}
