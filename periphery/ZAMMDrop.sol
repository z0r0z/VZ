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
            if iszero(eq(tos.length, amounts.length)) {
                revert(0, 0)
            }

            // transferFrom(address from, address to, uint256 id, uint256 amount)
            mstore(0x00, hex"fe99049a")
            // from address
            mstore(0x04, caller())
            // to address (this contract)
            mstore(0x24, address())
            // token id
            mstore(0x44, id)
            // total amount
            mstore(0x64, totalAmount)

            // transfer total amount to this contract
            if iszero(call(gas(), token, 0, 0x00, 0x84, 0, 0)){
                revert(0, 0)
            }

            // transfer(address to, uint256 value)
            mstore(0x00, hex"095bcdb6")

            // end of array
            let end := add(tos.offset, shl(5, tos.length))
            // diff = tos.offset - amounts.offset
            let diff := sub(tos.offset, amounts.offset)

            // Loop through the addresses
            for { let addressOffset := tos.offset } 1 {} {
                // to address
                mstore(0x04, calldataload(addressOffset))
                // token id
                mstore(0x24, id)
                // amount
                mstore(0x44, calldataload(sub(addressOffset, diff)))
                // transfer the tokens
                if iszero(call(gas(), token, 0, 0x00, 0x84, 0, 0)){
                    revert(0, 0)
                }
                // increment the address offset
                addressOffset := add(addressOffset, 0x20)
                // if addressOffset >= end, break
                if iszero(lt(addressOffset, end)) { break }
            }
        }
    }
}
