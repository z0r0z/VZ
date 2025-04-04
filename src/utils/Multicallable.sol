// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

// Modified from Solady (https://github.com/Vectorized/solady/blob/main/src/utils/Multicallable.sol)

abstract contract Multicallable {
    function multicall(bytes[] calldata data) public payable returns (bytes[] memory) {
        // Revert if `msg.value` is non-zero by default to guard against double-spending.
        // (See: https://www.paradigm.xyz/2021/08/two-rights-might-make-a-wrong)
        //
        // If you really need to pass in a `msg.value`, then you will have to
        // override this function and add in any relevant before and after checks.
        if (msg.value != 0) revert();
        // `_multicallDirectReturn` returns the results directly and terminates the call context.
        _multicallDirectReturn(_multicall(data));
    }

    /// @dev The inner logic of `multicall`.
    /// This function is included so that you can override `multicall`
    /// to add before and after actions, and use the `_multicallDirectReturn` function.
    function _multicall(bytes[] calldata data) internal returns (bytes32 results) {
        /// @solidity memory-safe-assembly
        assembly {
            results := mload(0x40)
            mstore(results, 0x20)
            mstore(add(0x20, results), data.length)
            let c := add(0x40, results)
            let s := c
            let end := shl(5, data.length)
            calldatacopy(c, data.offset, end)
            end := add(c, end)
            let m := end
            if data.length {
                for {} 1 {} {
                    let o := add(data.offset, mload(c))
                    calldatacopy(m, add(o, 0x20), calldataload(o))
                    // forgefmt: disable-next-item
                    if iszero(delegatecall(gas(), address(), m, calldataload(o), codesize(), 0x00)) {
                        // Bubble up the revert if the delegatecall reverts.
                        returndatacopy(results, 0x00, returndatasize())
                        revert(results, returndatasize())
                    }
                    mstore(c, sub(m, s))
                    c := add(0x20, c)
                    // Append the `returndatasize()`, and the return data.
                    mstore(m, returndatasize())
                    let b := add(m, 0x20)
                    returndatacopy(b, 0x00, returndatasize())
                    // Advance `m` by `returndatasize() + 0x20`,
                    // rounded up to the next multiple of 32.
                    m := and(add(add(b, returndatasize()), 0x1f), 0xffffffffffffffe0)
                    mstore(add(b, returndatasize()), 0) // Zeroize the slot after the returndata.
                    if iszero(lt(c, end)) { break }
                }
            }
            mstore(0x40, m) // Allocate memory.
            results := or(shl(64, sub(m, results)), results) // Pack the bytes length into `results`.
        }
    }

    /// @dev Directly returns the `results` and terminates the current call context.
    /// `results` must be from `_multicall`, else behavior is undefined.
    function _multicallDirectReturn(bytes32 results) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            return(and(0xffffffffffffffff, results), shr(64, results))
        }
    }
}
