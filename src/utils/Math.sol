// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Modified from Solady (https://github.com/Vectorized/solady/blob/main/src/utils/FixedPointMathLib.sol)

/// @dev Returns the minimum of `x` and `y`.
function min(uint256 x, uint256 y) pure returns (uint256 z) {
    assembly ("memory-safe") {
        z := xor(x, mul(xor(x, y), lt(y, x)))
    }
}

/// @dev Returns `floor(x * y / d)`.
/// Reverts if `x * y` overflows, or `d` is zero.
function mulDiv(uint256 x, uint256 y, uint256 d) pure returns (uint256 z) {
    assembly ("memory-safe") {
        z := mul(x, y)
        if iszero(mul(or(iszero(x), eq(div(z, x), y)), d)) {
            mstore(0x00, 0xad251c27)
            revert(0x1c, 0x04)
        }
        z := div(z, d)
    }
}

/// @dev Returns the square root of `x`, rounded down.
function sqrt(uint256 x) pure returns (uint256 z) {
    assembly ("memory-safe") {
        z := 181
        let r := shl(7, lt(0xffffffffffffffffffffffffffffffffff, x))
        r := or(r, shl(6, lt(0xffffffffffffffffff, shr(r, x))))
        r := or(r, shl(5, lt(0xffffffffff, shr(r, x))))
        r := or(r, shl(4, lt(0xffffff, shr(r, x))))
        z := shl(shr(1, r), z)
        z := shr(18, mul(z, add(shr(r, x), 65536)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := sub(z, lt(div(x, z), z))
    }
}

// Modified from Uniswap V2 (https://github.com/Uniswap/v2-core/blob/master/contracts/libraries/UQ112x112.sol)
// Licensed GPL-3.0

/// @dev Encode a uint112 as a UQ112x112.
function encode(uint112 y) pure returns (uint224 z) {
    unchecked {
        z = uint224(y) * 2 ** 112;
    }
}

/// @dev Divide a UQ112x112 by a uint112, returning a UQ112x112.
function uqdiv(uint224 x, uint112 y) pure returns (uint224 z) {
    unchecked {
        z = x / uint224(y);
    }
}
