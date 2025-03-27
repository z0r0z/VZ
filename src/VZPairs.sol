// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "./VZERC6909.sol";
import "./utils/Math.sol";
import "./utils/TransferHelper.sol";

contract VZPairs is VZERC6909 {
    uint256 constant MINIMUM_LIQUIDITY = 1000;
    uint256 constant MAX_FEE = 10000; // 100%.

    mapping(uint256 poolId => Pool) public pools;

    struct Pool {
        uint256 id0;
        uint256 id1;
        address token0;
        address token1;
        uint96 swapFee;
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

    /// @dev Helper function to transfer tokens considering ERC6909 and ETH cases.
    function _safeTransfer(address token, address to, uint256 id, uint256 amount) internal {
        if (token == address(0)) {
            safeTransferETH(to, amount);
        } else if (id == 0) {
            safeTransfer(token, to, amount);
        } else {
            VZERC6909(token).transfer(to, id, amount);
        }
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

    error InvalidPoolTokens();
    error InvalidSwapFee();
    error PoolExists();

    /// @dev Create a new pair pool and mint initial liquidity tokens for `to`.
    function initialize(
        address to,
        address token0,
        uint256 id0,
        address token1,
        uint256 id1,
        uint256 swapFee
    ) public returns (uint256 liquidity) {
        require(token0 < token1, InvalidPoolTokens()); // Ensure ascending order.
        require(swapFee <= MAX_FEE, InvalidSwapFee()); // Ensure swap fee limit.

        uint256 poolId = uint256(keccak256(abi.encode(token0, id0, token1, id1, swapFee)));

        Pool storage pool = pools[poolId];
        require(pool.supply == 0, PoolExists());
        (pool.token0, pool.id0, pool.token1, pool.id1, pool.swapFee) =
            (token0, id0, token1, id1, uint96(swapFee));

        uint256 balance0;
        if (pool.token0 == address(0)) {
            balance0 = address(this).balance;
        } else if (pool.id0 == 0) {
            balance0 = getBalanceOf(pool.token0);
        } else {
            balance0 = VZERC6909(pool.token0).balanceOf(address(this), pool.id0);
        }

        uint256 balance1;
        if (pool.id1 == 0) {
            balance1 = getBalanceOf(pool.token1);
        } else {
            balance1 = VZERC6909(pool.token1).balanceOf(address(this), pool.id1);
        }

        liquidity = sqrt(balance0 * balance1) - MINIMUM_LIQUIDITY;

        // Lock minimum liquidity to `address(0)` forever.
        _mint(address(0), poolId, MINIMUM_LIQUIDITY);
        // Mint the remaining liquidity to the recipient.
        _mint(to, poolId, liquidity);

        unchecked {
            pool.supply = liquidity + MINIMUM_LIQUIDITY;
        }

        _update(poolId, balance0, balance1, 0, 0);

        bool feeOn = _mintFee(poolId, uint112(balance0), uint112(balance1));
        if (feeOn) pool.kLast = uint256(pool.reserve0) * pool.reserve1;

        emit Mint(poolId, msg.sender, balance0, balance1);
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
            require(balance0 <= type(uint112).max, Overflow());
            require(balance1 <= type(uint112).max, Overflow());
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
                    uint256 denominator = rootK * 5 + rootKLast;
                    unchecked {
                        uint256 liquidity = numerator / denominator;
                        if (liquidity > 0) {
                            _mint(feeTo, poolId, liquidity);
                            pool.supply += liquidity;
                        }
                    }
                }
            }
        } else if (pool.kLast != 0) {
            delete pool.kLast;
        }
    }

    error InsufficientLiquidityMinted();

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function mint(address to, uint256 poolId) public lock returns (uint256 liquidity) {
        Pool storage pool = pools[poolId];
        (uint112 reserve0, uint112 reserve1, uint256 supply) =
            (pool.reserve0, pool.reserve1, pool.supply);

        bool ethPair = pool.token0 == address(0);

        uint256 balance0;
        if (ethPair) {
            balance0 = address(this).balance;
        } else if (pool.id0 == 0) {
            balance0 = getBalanceOf(pool.token0);
        } else {
            balance0 = VZERC6909(pool.token0).balanceOf(address(this), pool.id0);
        }

        uint256 balance1;
        if (pool.id1 == 0) {
            balance1 = getBalanceOf(pool.token1);
        } else {
            balance1 = VZERC6909(pool.token1).balanceOf(address(this), pool.id1);
        }

        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;

        bool feeOn = _mintFee(poolId, reserve0, reserve1);
        liquidity = min(mulDiv(amount0, supply, reserve0), mulDiv(amount1, supply, reserve1));
        require(liquidity != 0, InsufficientLiquidityMinted());
        _mint(to, poolId, liquidity);
        pool.supply += liquidity; // @todo unchecked?

        _update(poolId, balance0, balance1, reserve0, reserve1);
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
        (address token0, address token1, uint112 reserve0, uint112 reserve1, uint256 supply) =
            (pool.token0, pool.token1, pool.reserve0, pool.reserve1, pool.supply);

        bool ethPair = token0 == address(0);

        uint256 balance0;
        if (ethPair) {
            balance0 = address(this).balance;
        } else if (pool.id0 == 0) {
            balance0 = getBalanceOf(token0);
        } else {
            balance0 = VZERC6909(token0).balanceOf(address(this), pool.id0);
        }

        uint256 balance1;
        if (pool.id1 == 0) {
            balance1 = getBalanceOf(token1);
        } else {
            balance1 = VZERC6909(token1).balanceOf(address(this), pool.id1);
        }

        uint256 liquidity = balanceOf(address(this), poolId);

        bool feeOn = _mintFee(poolId, reserve0, reserve1);
        amount0 = mulDiv(liquidity, balance0, supply); // Using balances ensures pro-rata distribution.
        amount1 = mulDiv(liquidity, balance1, supply); // Using balances ensures pro-rata distribution.
        require(amount0 != 0, InsufficientLiquidityBurned());
        require(amount1 != 0, InsufficientLiquidityBurned());
        _burn(poolId, liquidity);
        pool.supply -= liquidity;

        _safeTransfer(token0, to, pool.id0, amount0);
        _safeTransfer(token1, to, pool.id1, amount1);

        // Re-calculate balances after transfers.
        if (ethPair) {
            balance0 = address(this).balance;
        } else if (pool.id0 == 0) {
            balance0 = getBalanceOf(token0);
        } else {
            balance0 = VZERC6909(token0).balanceOf(address(this), pool.id0);
        }

        if (pool.id1 == 0) {
            balance1 = getBalanceOf(token1);
        } else {
            balance1 = VZERC6909(token1).balanceOf(address(this), pool.id1);
        }

        _update(poolId, balance0, balance1, reserve0, reserve1);
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
        require(amount0Out != 0 || amount1Out != 0, InsufficientOutputAmount());
        Pool storage pool = pools[poolId];
        (address token0, address token1, uint96 swapFee, uint112 reserve0, uint112 reserve1) =
            (pool.token0, pool.token1, pool.swapFee, pool.reserve0, pool.reserve1);

        require(amount0Out < reserve0, InsufficientLiquidity());
        require(amount1Out < reserve1, InsufficientLiquidity());

        bool ethPair = token0 == address(0);
        require(to != token0, InvalidTo());
        require(to != token1, InvalidTo());

        // Optimistically transfer tokens.
        if (amount0Out != 0) _safeTransfer(token0, to, pool.id0, amount0Out);
        if (amount1Out != 0) _safeTransfer(token1, to, pool.id1, amount1Out);
        if (data.length != 0) IVZCallee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);

        uint256 balance0;
        if (ethPair) {
            balance0 = address(this).balance;
        } else if (pool.id0 == 0) {
            balance0 = getBalanceOf(token0);
        } else {
            balance0 = VZERC6909(token0).balanceOf(address(this), pool.id0);
        }

        uint256 balance1;
        if (pool.id1 == 0) {
            balance1 = getBalanceOf(token1);
        } else {
            balance1 = VZERC6909(token1).balanceOf(address(this), pool.id1);
        }

        uint256 amount0In;
        uint256 amount1In;
        unchecked {
            amount0In = balance0 > reserve0 - amount0Out ? balance0 - (reserve0 - amount0Out) : 0;
            amount1In = balance1 > reserve1 - amount1Out ? balance1 - (reserve1 - amount1Out) : 0;
        }
        require(amount0In != 0 || amount1In != 0, InsufficientInputAmount());
        uint256 balance0Adjusted = (balance0 * 10000) - (amount0In * swapFee);
        uint256 balance1Adjusted = (balance1 * 10000) - (amount1In * swapFee);
        require(
            balance0Adjusted * balance1Adjusted >= (uint256(reserve0) * reserve1) * 10000 ** 2, K()
        );

        _update(poolId, balance0, balance1, reserve0, reserve1);
        emit Swap(poolId, msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /// @dev Force balances to match reserves.
    function skim(address to, uint256 poolId) public lock {
        Pool storage pool = pools[poolId];

        uint256 balance0;
        if (pool.token0 == address(0)) {
            balance0 = address(this).balance;
        } else if (pool.id0 == 0) {
            balance0 = getBalanceOf(pool.token0);
        } else {
            balance0 = VZERC6909(pool.token0).balanceOf(address(this), pool.id0);
        }

        uint256 balance1;
        if (pool.id1 == 0) {
            balance1 = getBalanceOf(pool.token1);
        } else {
            balance1 = VZERC6909(pool.token1).balanceOf(address(this), pool.id1);
        }

        _safeTransfer(pool.token0, to, pool.id0, balance0 - pool.reserve0);
        _safeTransfer(pool.token1, to, pool.id1, balance1 - pool.reserve1);
    }

    /// @dev Force reserves to match balances.
    function sync(uint256 poolId) public lock {
        Pool storage pool = pools[poolId];

        uint256 balance0;
        if (pool.token0 == address(0)) {
            balance0 = address(this).balance;
        } else if (pool.id0 == 0) {
            balance0 = getBalanceOf(pool.token0);
        } else {
            balance0 = VZERC6909(pool.token0).balanceOf(address(this), pool.id0);
        }

        uint256 balance1;
        if (pool.id1 == 0) {
            balance1 = getBalanceOf(pool.token1);
        } else {
            balance1 = VZERC6909(pool.token1).balanceOf(address(this), pool.id1);
        }

        _update(poolId, balance0, balance1, pool.reserve0, pool.reserve1);
    }

    /// @dev Native token receiver.
    receive() external payable {}

    /// @dev Fee management fallback.
    fallback() external payable {
        assembly ("memory-safe") {
            if iszero(eq(caller(), sload(0x00))) { revert(codesize(), codesize()) }
            sstore(0x00, calldataload(0x00)) // `feeToSetter`.
            sstore(0x20, calldataload(0x20)) // `feeTo`.
        }
    }
}

/// @dev Minimal VZ swap call interface.
interface IVZCallee {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data)
        external;
}
