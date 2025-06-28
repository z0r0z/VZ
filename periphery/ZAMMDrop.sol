// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IZAMMDrop {
    function transfer(address to, uint256 id, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 id, uint256 amount) external returns (bool);
}

contract ZAMMDrop {
    function drop(address token, uint256 id, address[] calldata tos, uint256[] calldata amounts, uint256 totalAmount) external payable {
        assembly {
            // Check that the number of addresses matches the number of amounts
            if iszero(eq(amounts.length, tos.length)) {
                revert(0, 0)
            }    

            // transferFrom(address from, address to, uint256 id, uint256 amount)
            mstore(0x00, 0xfe99049a)           // selector
            mstore(0x04, caller())             // from
            mstore(0x24, address())            // to
            mstore(0x44, id)                   // token id
            mstore(0x64, totalAmount)          // amount

            let success := call(gas(), token, 0, 0x00, 0x84, 0, 0) // return bool to 0x00
            if iszero(success) {
                revert(0, 0)
            }

            if iszero(mload(0x00)) {
                revert(0, 0)
            }
        }

        // Pull the total amount from the sender to this contract
        // require(IZAMMDrop(token).transferFrom(msg.sender, address(this), id, totalAmount), "TransferFrom failed");

        // Distribute the tokens to each recipient
        for (uint256 i = 0; i < tos.length; i++) {
            require(IZAMMDrop(token).transfer(tos[i], id, amounts[i]), "Transfer failed");
        }
    }
}
