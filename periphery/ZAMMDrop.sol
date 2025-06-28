// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice ERC6909 batch transfer utility for airdrops and multisend.
contract ZAMMDrop {
    error InvalidArray();

    function drop(
        IZAMM token,
        uint256 id,
        uint256 totalAmount,
        address[] calldata tos,
        uint256[] calldata amounts
    ) public {
        require(tos.length == amounts.length, InvalidArray());
        token.transferFrom(msg.sender, address(this), id, totalAmount);
        for (uint256 i; i != tos.length; ++i) token.transfer(tos[i], id, amounts[i]);
    }

    function lockup(
        address token,
        uint256 id,
        uint256 totalAmount,
        uint256 unlockTime,
        address[] calldata tos,
        uint256[] calldata amounts
    ) public {
        require(tos.length == amounts.length, InvalidArray());
        IZAMM(token).transferFrom(msg.sender, address(this), id, totalAmount);
        for (uint256 i; i != tos.length; ++i) Z.lockup(token, tos[i], id, amounts[i], unlockTime);
    }

    /// @dev Allows lockups within ZAMM.
    function approve(IZAMM token) public {
        token.setOperator(address(Z), true);
    }
}

IZAMM constant Z = IZAMM(0x000000000000040470635EB91b7CE4D132D616eD);

interface IZAMM {
    function transfer(address to, uint256 id, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 id, uint256 amount)
        external
        returns (bool);
    function setOperator(address operator, bool approved) external returns (bool);
    function lockup(address token, address to, uint256 id, uint256 amount, uint256 unlockTime)
        external
        payable
        returns (bytes32 lockHash);
}
