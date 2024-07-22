// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./VZERC6909.sol";
import "./utils/Math.sol";
import "./utils/TransferHelper.sol";

contract VZPairs is VZERC6909 {
    uint256 constant MINIMUM_LIQUIDITY = 10 ** 3;

    mapping(uint256 poolId => Pool) public pools;

    struct Pool {
        address token0;
        address token1;
        uint16 swapFee;
        uint112 reserve0;
        uint112 reserve1;
        uint32 blockTimestampLast;
        uint256 price0CumulativeLast;
        uint256 price1CumulativeLast;
        uint256 kLast; // `reserve0` * `reserve1`, as of immediately after the most recent liquidity event.
        uint256 supply;
    }

    /// @dev Reentrancy guard (https://github.com/Vectorized/soledge/blob/main/src/utils/ReentrancyGuard.sol).
    modifier lock() {
        assembly ("memory-safe") {
            if tload(0x929eee149b4bd21268) {
                mstore(0x00, 0xab143c06)
                revert(0x1c, 0x04)
            }
            tstore(0x929eee149b4bd21268, address())
        }
        _;
        assembly ("memory-safe") {
            tstore(0x929eee149b4bd21268, 0)
        }
    }

    /// @dev Reserves for a given liquidity token `poolId`.
    function getReserves(uint256 poolId)
        public
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)
    {
        Pool storage pool = pools[poolId];
        (reserve0, reserve1, blockTimestampLast) =
            (pool.reserve0, pool.reserve1, pool.blockTimestampLast);
    }

    event Mint(uint256 indexed poolId, address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        uint256 indexed poolId,
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        uint256 indexed poolId,
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint256 indexed poolId, uint112 reserve0, uint112 reserve1);

    constructor(address feeToSetter) payable {
        assembly ("memory-safe") {
            sstore(0x00, feeToSetter)
        }
    }

    error Overflow();

    /// @dev Update reserves and, on the first call per block, price accumulators for the given pool `poolId`.
    function _update(
        uint256 poolId,
        uint256 balance0,
        uint256 balance1,
        uint112 reserve0,
        uint112 reserve1
    ) internal {
        unchecked {
            Pool storage pool = pools[poolId];
            if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert Overflow();
            uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
            uint32 timeElapsed = blockTimestamp - pool.blockTimestampLast; // Overflow is desired.
            if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
                // * never overflows, and + overflow is desired.
                pool.price0CumulativeLast +=
                    uint256(uqdiv(encode(reserve1), reserve0)) * timeElapsed;
                pool.price1CumulativeLast +=
                    uint256(uqdiv(encode(reserve0), reserve1)) * timeElapsed;
            }
            pool.blockTimestampLast = blockTimestamp;
            emit Sync(poolId, pool.reserve0 = uint112(balance0), pool.reserve1 = uint112(balance1));
        }
    }

    /// @dev If fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k).
    function _mintFee(uint256 poolId, uint112 reserve0, uint112 reserve1)
        internal
        returns (bool feeOn)
    {
        Pool storage pool = pools[poolId];
        address feeTo;
        assembly ("memory-safe") {
            feeTo := sload(0x20)
            feeOn := iszero(iszero(feeTo))
        }
        if (feeOn) {
            if (pool.kLast != 0) {
                uint256 rootK = sqrt(uint256(reserve0) * reserve1);
                uint256 rootKLast = sqrt(pool.kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = pool.supply * (rootK - rootKLast);
                    uint256 denominator = (rootK * (10000 / (pool.swapFee / 2))) + rootKLast;
                    unchecked {
                        uint256 liquidity = numerator / denominator;
                        if (liquidity != 0) {
                            _mint(feeTo, poolId, liquidity);
                        }
                        pool.supply += liquidity;
                    }
                }
            }
        } else if (pool.kLast != 0) {
            pool.kLast = 0;
        }
    }

    error InsufficientLiquidityMinted();
    error InvalidPoolTokens();
    error PairExists();

    /// @dev Create a new pair pool and mint initial liquidity tokens for `to`.
    function initialize(address to, address token0, address token1, uint16 fee)
        public
        returns (uint256 liquidity)
    {
        if (token0 >= token1) revert InvalidPoolTokens();

        uint256 poolId;
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(m, token0)
            mstore(add(m, 0x20), token1)
            mstore(add(m, 0x40), fee)
            poolId := keccak256(m, 0x60)
        }

        Pool storage pool = pools[poolId];
        if (pool.supply != 0) revert PairExists();
        (pool.token0, pool.token1, pool.swapFee) = (token0, token1, fee);

        uint256 balance0 = pool.token0 == address(0)
            ? address(this).balance
            : getBalanceOf(pool.token0, address(this));
        uint256 balance1 = getBalanceOf(pool.token1, address(this));

        bool feeOn = _mintFee(poolId, 0, 0);
        liquidity = sqrt(balance0 * balance1) - MINIMUM_LIQUIDITY;
        _mint(address(0), poolId, MINIMUM_LIQUIDITY); // Permanently lock the first `MINIMUM_LIQUIDITY` tokens.
        pool.supply += MINIMUM_LIQUIDITY;

        if (liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(to, poolId, liquidity);
        pool.supply += liquidity;

        _update(poolId, balance0, balance1, pool.reserve0, pool.reserve1);
        if (feeOn) pool.kLast = uint256(pool.reserve0) * pool.reserve1; // `reserve0` and `reserve1` are up-to-date.
        emit Mint(poolId, msg.sender, balance0, balance1);
    }

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function mint(address to, uint256 poolId) public lock returns (uint256 liquidity) {
        Pool storage pool = pools[poolId];

        uint256 balance0 = pool.token0 == address(0)
            ? address(this).balance
            : getBalanceOf(pool.token0, address(this));
        uint256 balance1 = getBalanceOf(pool.token1, address(this));
        uint256 amount0 = balance0 - pool.reserve0;
        uint256 amount1 = balance1 - pool.reserve1;

        bool feeOn = _mintFee(poolId, pool.reserve0, pool.reserve1);
        liquidity = min(
            mulDiv(amount0, pool.supply, pool.reserve0), mulDiv(amount1, pool.supply, pool.reserve1)
        );
        if (liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(to, poolId, liquidity);
        pool.supply += liquidity;

        _update(poolId, balance0, balance1, pool.reserve0, pool.reserve1);
        if (feeOn) pool.kLast = uint256(pool.reserve0) * pool.reserve1; // `reserve0` and `reserve1` are up-to-date.
        emit Mint(poolId, msg.sender, amount0, amount1);
    }

    error InsufficientLiquidityBurned();

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function burn(address to, uint256 poolId)
        public
        lock
        returns (uint256 amount0, uint256 amount1)
    {
        Pool storage pool = pools[poolId];

        bool ethPair = pool.token0 == address(0);
        uint256 balance0 =
            ethPair ? address(this).balance : getBalanceOf(pool.token0, address(this));
        uint256 balance1 = getBalanceOf(pool.token1, address(this));
        uint256 liquidity = balanceOf(address(this), poolId);

        bool feeOn = _mintFee(poolId, pool.reserve0, pool.reserve1);
        amount0 = mulDiv(liquidity, balance0, pool.supply); // Using balances ensures pro-rata distribution.
        amount1 = mulDiv(liquidity, balance1, pool.supply); // Using balances ensures pro-rata distribution.
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurned();
        _burn(poolId, liquidity);
        pool.supply -= liquidity;
        ethPair ? safeTransferETH(to, amount0) : safeTransfer(pool.token0, to, amount0);
        safeTransfer(pool.token1, to, amount1);
        balance0 = ethPair ? address(this).balance : getBalanceOf(pool.token0, address(this));
        balance1 = getBalanceOf(pool.token1, address(this));

        _update(poolId, balance0, balance1, pool.reserve0, pool.reserve1);
        if (feeOn) pool.kLast = uint256(pool.reserve0) * pool.reserve1; // `reserve0` and `reserve1` are up-to-date.
        emit Burn(poolId, msg.sender, amount0, amount1, to);
    }

    error InsufficientOutputAmount();
    error InsufficientInputAmount();
    error InsufficientLiquidity();
    error InvalidTo();
    error K();

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function swap(
        uint256 poolId,
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) public lock {
        Pool storage pool = pools[poolId];

        if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutputAmount();
        if (amount0Out >= pool.reserve0 || amount1Out >= pool.reserve1) {
            revert InsufficientLiquidity();
        }

        bool ethPair = pool.token0 == address(0);
        if (to == pool.token0 || to == pool.token1) revert InvalidTo();
        // Optimistically transfer tokens.
        if (amount0Out != 0) {
            ethPair ? safeTransferETH(to, amount0Out) : safeTransfer(pool.token0, to, amount0Out);
        }
        if (amount1Out != 0) safeTransfer(pool.token1, to, amount1Out);
        if (data.length != 0) {
            IVZCallee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
        }
        uint256 balance0 =
            ethPair ? address(this).balance : getBalanceOf(pool.token0, address(this));
        uint256 balance1 = getBalanceOf(pool.token1, address(this));

        uint256 amount0In;
        uint256 amount1In;
        unchecked {
            amount0In =
                balance0 > pool.reserve0 - amount0Out ? balance0 - (pool.reserve0 - amount0Out) : 0;
            amount1In =
                balance1 > pool.reserve1 - amount1Out ? balance1 - (pool.reserve1 - amount1Out) : 0;
        }
        if (amount0In == 0 && amount1In == 0) revert InsufficientInputAmount();

        uint256 balance0Adjusted = (balance0 * 10000) - (amount0In * pool.swapFee);
        uint256 balance1Adjusted = (balance1 * 10000) - (amount1In * pool.swapFee);
        if (
            balance0Adjusted * balance1Adjusted
                < (uint256(pool.reserve0) * pool.reserve1) * 10000 ** 2
        ) {
            revert K();
        }

        _update(poolId, balance0, balance1, pool.reserve0, pool.reserve1);
        emit Swap(poolId, msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /// @dev Force balances to match reserves.
    function skim(address to, uint256 poolId) public lock {
        Pool storage pool = pools[poolId];
        pool.token0 == address(0)
            ? safeTransferETH(to, address(this).balance - pool.reserve0)
            : safeTransfer(pool.token0, to, (getBalanceOf(pool.token0, address(this))) - pool.reserve0);
        safeTransfer(pool.token1, to, (getBalanceOf(pool.token1, address(this))) - pool.reserve1);
    }

    /// @dev Force reserves to match balances.
    function sync(uint256 poolId) public lock {
        Pool storage pool = pools[poolId];
        _update(
            poolId,
            pool.token0 == address(0)
                ? address(this).balance
                : getBalanceOf(pool.token0, address(this)),
            getBalanceOf(pool.token1, address(this)),
            pool.reserve0,
            pool.reserve1
        );
    }

    /// @dev Native token receiver.
    receive() external payable {}

    /// @dev Fee management fallback.
    fallback() external payable {
        assembly ("memory-safe") {
            if iszero(eq(caller(), sload(0x00))) { revert(codesize(), codesize()) }
            sstore(0x00, calldataload(0x00))
            sstore(0x20, calldataload(0x20))
        }
    }
}

/// @dev Minimal VZ swap call interface.
interface IVZCallee {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data)
        external;
}
