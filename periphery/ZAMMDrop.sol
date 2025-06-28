// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IZAMMDrop {
    function transfer(address to, uint256 id, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 id, uint256 amount) external returns (bool);
}

contract ZAMMDrop {
    function drop(address token, uint256 id, address[] calldata tos, uint256[] calldata amounts, uint256 totalAmount) public {
        require(tos.length == amounts.length, "Mismatched input lengths");

        // Pull the total amount from the sender to this contract
        require(IZAMMDrop(token).transferFrom(msg.sender, address(this), id, totalAmount), "TransferFrom failed");

        // Distribute the tokens to each recipient
        for (uint256 i = 0; i < tos.length; i++) {
            require(IZAMMDrop(token).transfer(tos[i], id, amounts[i]), "Transfer failed");
        }
    }
}
