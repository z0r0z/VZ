// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Modified from Solady (https://github.com/Vectorized/solady/blob/main/src/utils/SafeTransferLib.sol)

/// @dev The ETH transfer has failed.
error ETHTransferFailed();

/// @dev Sends `amount` (in wei) ETH to `to`.
function safeTransferETH(address to, uint256 amount) {
    assembly ("memory-safe") {
        if iszero(call(gas(), to, amount, codesize(), 0x00, codesize(), 0x00)) {
            mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`.
            revert(0x1c, 0x04)
        }
    }
}

/// @dev The ERC20 `transfer` has failed.
error TransferFailed();

/// @dev Sends `amount` of ERC20 `token` from the current contract to `to`.
/// Reverts upon failure.
function safeTransfer(address token, address to, uint256 amount) {
    assembly ("memory-safe") {
        mstore(0x14, to) // Store the `to` argument.
        mstore(0x34, amount) // Store the `amount` argument.
        mstore(0x00, 0xa9059cbb000000000000000000000000) // `transfer(address,uint256)`.
        // Perform the transfer, reverting upon failure.
        if iszero(
            and( // The arguments of `and` are evaluated from right to left.
                or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
            )
        ) {
            mstore(0x00, 0x90b8ec18) // `TransferFailed()`.
            revert(0x1c, 0x04)
        }
        mstore(0x34, 0) // Restore the part of the free memory pointer that was overwritten.
    }
}

/// @dev Returns the amount of ERC20 `token` owned by `account`.
/// Returns zero if the `token` does not exist.
function getBalanceOf(address token, address account) view returns (uint256 amount) {
    assembly ("memory-safe") {
        mstore(0x14, account) // Store the `account` argument.
        mstore(0x00, 0x70a08231000000000000000000000000) // `balanceOf(address)`.
        amount :=
            mul( // The arguments of `mul` are evaluated from right to left.
                mload(0x20),
                and( // The arguments of `and` are evaluated from right to left.
                    gt(returndatasize(), 0x1f), // At least 32 bytes returned.
                    staticcall(gas(), token, 0x10, 0x24, 0x20, 0x20)
                )
            )
    }
}
