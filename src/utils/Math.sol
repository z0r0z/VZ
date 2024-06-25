// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

// Modified from Solady (https://github.com/Vectorized/solady/blob/main/src/utils/FixedPointMathLib.sol)

/// @dev Returns the minimum of `x` and `y`.
function min(uint256 x, uint256 y) pure returns (uint256 z) {
    /// @solidity memory-safe-assembly
    assembly {
        z := xor(x, mul(xor(x, y), lt(y, x)))
    }
}

/// @dev The operation failed, either due to a multiplication overflow, or a division by a zero.
error MulDivFailed();

/// @dev Returns `floor(x * y / d)`.
/// Reverts if `x * y` overflows, or `d` is zero.
function mulDiv(uint256 x, uint256 y, uint256 d) pure returns (uint256 z) {
    /// @solidity memory-safe-assembly
    assembly {
        z := mul(x, y)
        // Equivalent to `require(d != 0 && (y == 0 || x <= type(uint256).max / y))`.
        if iszero(mul(or(iszero(x), eq(div(z, x), y)), d)) {
            mstore(0x00, 0xad251c27) // `MulDivFailed()`.
            revert(0x1c, 0x04)
        }
        z := div(z, d)
    }
}

/// @dev Returns the square root of `x`, rounded down.
function sqrt(uint256 x) pure returns (uint256 z) {
    assembly ("memory-safe") {
        // `floor(sqrt(2**15)) = 181`. `sqrt(2**15) - 181 = 2.84`.
        z := 181 // The "correct" value is 1, but this saves a multiplication later.

        // This segment is to get a reasonable initial estimate for the Babylonian method. With a bad
        // start, the correct # of bits increases ~linearly each iteration instead of ~quadratically.

        // Let `y = x / 2**r`. We check `y >= 2**(k + 8)`
        // but shift right by `k` bits to ensure that if `x >= 256`, then `y >= 256`.
        let r := shl(7, lt(0xffffffffffffffffffffffffffffffffff, x))
        r := or(r, shl(6, lt(0xffffffffffffffffff, shr(r, x))))
        r := or(r, shl(5, lt(0xffffffffff, shr(r, x))))
        r := or(r, shl(4, lt(0xffffff, shr(r, x))))
        z := shl(shr(1, r), z)

        // Goal was to get `z*z*y` within a small factor of `x`. More iterations could
        // get y in a tighter range. Currently, we will have y in `[256, 256*(2**16))`.
        // We ensured `y >= 256` so that the relative difference between `y` and `y+1` is small.
        // That's not possible if `x < 256` but we can just verify those cases exhaustively.

        // Now, `z*z*y <= x < z*z*(y+1)`, and `y <= 2**(16+8)`, and either `y >= 256`, or `x < 256`.
        // Correctness can be checked exhaustively for `x < 256`, so we assume `y >= 256`.
        // Then `z*sqrt(y)` is within `sqrt(257)/sqrt(256)` of `sqrt(x)`, or about 20bps.

        // For `s` in the range `[1/256, 256]`, the estimate `f(s) = (181/1024) * (s+1)`
        // is in the range `(1/2.84 * sqrt(s), 2.84 * sqrt(s))`,
        // with largest error when `s = 1` and when `s = 256` or `1/256`.

        // Since `y` is in `[256, 256*(2**16))`, let `a = y/65536`, so that `a` is in `[1/256, 256)`.
        // Then we can estimate `sqrt(y)` using
        // `sqrt(65536) * 181/1024 * (a + 1) = 181/4 * (y + 65536)/65536 = 181 * (y + 65536)/2**18`.

        // There is no overflow risk here since `y < 2**136` after the first branch above.
        z := shr(18, mul(z, add(shr(r, x), 65536))) // A `mul()` is saved from starting `z` at 181.

        // Given the worst case multiplicative error of 2.84 above, 7 iterations should be enough.
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))

        // If `x+1` is a perfect square, the Babylonian method cycles between
        // `floor(sqrt(x))` and `ceil(sqrt(x))`. This statement ensures we return floor.
        // See: https://en.wikipedia.org/wiki/Integer_square_root#Using_only_integer_division
        z := sub(z, lt(div(x, z), z))
    }
}

// Modified from Uniswap V2 (https://github.com/Uniswap/v2-core/blob/master/contracts/libraries/UQ112x112.sol)

/// @dev Encode a uint112 as a UQ112x112.
function encode(uint112 y) pure returns (uint224 z) {
    unchecked {
        z = uint224(y) * 2 ** 112; // Never overflows.
    }
}

/// @dev Divide a UQ112x112 by a uint112, returning a UQ112x112.
function uqdiv(uint224 x, uint112 y) pure returns (uint224 z) {
    z = x / uint224(y);
}
