// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Volta Coin (VOLT) — player reward token for Volta Gent.
///
/// A plain, fixed-supply ERC-20:
/// - Name "Volta Coin", symbol "VOLT", 18 decimals.
/// - Total supply 100,000,000 VOLT, minted entirely to the deployer in the
///   constructor. There is NO mint or burn function — the supply can never
///   change after deployment.
/// - The owner funds the VoltaMining contract out of this initial supply;
///   mining claims then pay VOLT (instead of BNB from the arena pool).
///
/// The contract is unaudited.
contract VoltaToken {
    string public constant name = "Volta Coin";
    string public constant symbol = "VOLT";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 100_000_000 ether; // 100,000,000 VOLT (1e18 base units each)

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        require(spender != address(0), "spender is zero");
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "allowance too low");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0), "to is zero");
        require(balanceOf[from] >= value, "balance too low");
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }
}
