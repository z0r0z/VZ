// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "./VZERC6909.sol";
import "./utils/Math.sol";
import "./utils/TransferHelper.sol";

contract VZPairs is VZERC6909 {
    uint256 constant MINIMUM_LIQUIDITY = 1000;
    uint256 constant MAX_FEE = 10000; // 100%.

    mapping(uint256 poolId => Pool) public pools;

    struct PoolKey {
        uint256 id0;
        uint256 id1;
        address token0;
        address token1;
        uint96 swapFee;
    }

    struct Pool {
        uint112 reserve0;
        uint112 reserve1;
        uint32 blockTimestampLast;
        uint256 price0CumulativeLast;
        uint256 price1CumulativeLast;
        uint256 kLast; // `reserve0` * `reserve1`, as of immediately after the most recent liquidity event.
        uint256 supply;
    }

    error Reentrancy();

    /// @dev Reentrancy guard (https://github.com/Vectorized/soledge/blob/main/src/utils/ReentrancyGuard.sol).
    modifier lock() {
        assembly ("memory-safe") {
            if tload(0x929eee149b4bd21268) {
                mstore(0x00, 0xab143c06) // `Reentrancy()`.
                revert(0x1c, 0x04)
            }
            tstore(0x929eee149b4bd21268, address())
        }
        _;
        assembly ("memory-safe") {
            tstore(0x929eee149b4bd21268, 0)
        }
    }

    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            require(success, "Multicall: call failed");
            results[i] = result;
        }
    }

    error InsufficientETH();

    /// @dev Helper function to pull token balances into pool.
    function deposit(PoolKey calldata poolKey, uint256 amount0, uint256 amount1)
        public
        payable
        returns (uint256 poolId)
    {
        // Enforce token ordering when at least one token is ETH/ERC20 (id == 0).
        require(
            poolKey.id0 > 0 && poolKey.id1 > 0 ? true : poolKey.token0 < poolKey.token1,
            InvalidPoolTokens()
        );
        poolId = _computePoolId(poolKey);
        if (poolKey.token0 == address(0)) require(msg.value == amount0, InsufficientETH());
        else _safeTransferFrom(poolKey.token0, msg.sender, poolKey.id0, amount0);
        _safeTransferFrom(poolKey.token1, msg.sender, poolKey.id1, amount1);
        _deposit(poolId, amount0, amount1);
    }

    /// @dev Helper function to compute poolId from PoolKey.
    function _computePoolId(PoolKey memory key) internal pure returns (uint256 poolId) {
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(m, mload(add(key, 0x40))) // `token0`.
            mstore(add(m, 0x20), mload(key)) // `id0`.
            mstore(add(m, 0x40), mload(add(key, 0x60))) // `token1`.
            mstore(add(m, 0x60), mload(add(key, 0x20))) // `id1`.
            mstore(add(m, 0x80), mload(add(key, 0x80))) // `swapFee`.
            poolId := keccak256(m, 0xa0)
        }
    }

    /// @dev Helper function to log transient balances into pool and accumulate.
    function _deposit(uint256 poolId, uint256 amount0, uint256 amount1) internal {
        assembly ("memory-safe") {
            if amount0 { tstore(poolId, add(tload(poolId), amount0)) }
            if amount1 { tstore(add(poolId, 1), add(tload(add(poolId, 1)), amount1)) }
        }
    }

    /// @dev Helper function to clear transient balances from pool after op.
    function _clear(uint256 poolId) internal {
        assembly ("memory-safe") {
            tstore(poolId, 0)
            tstore(add(poolId, 1), 0)
        }
    }

    /// @dev Helper function to fetch transient balances during liquidity event.
    function _getDeposits(uint256 poolId)
        internal
        view
        returns (uint256 deposit0, uint256 deposit1)
    {
        assembly ("memory-safe") {
            deposit0 := tload(poolId)
            deposit1 := tload(add(poolId, 1))
        }
    }

    /// @dev Helper function to transfer tokens considering ERC6909 and ETH cases.
    function _safeTransfer(address token, address to, uint256 id, uint256 amount) internal {
        if (to == address(this)) return;
        if (token == address(0)) {
            safeTransferETH(to, amount);
        } else if (id == 0) {
            safeTransfer(token, to, amount);
        } else {
            VZERC6909(token).transfer(to, id, amount);
        }
    }

    /// @dev Helper function to pull tokens considering ERC6909 and ETH cases.
    function _safeTransferFrom(address token, address from, uint256 id, uint256 amount) internal {
        if (id == 0) {
            safeTransferFrom(token, amount);
        } else {
            VZERC6909(token).transferFrom(from, address(this), id, amount);
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
                    uint256 liquidity;
                    unchecked {
                        liquidity = numerator / denominator;
                        if (liquidity > 0) {
                            _mint(feeTo, poolId, liquidity);
                        }
                    }
                    pool.supply += liquidity;
                }
            }
        } else if (pool.kLast != 0) {
            delete pool.kLast;
        }
    }

    error InsufficientLiquidityMinted();
    error InvalidPoolTokens();
    error InvalidSwapFee();
    error PoolExists();

    /// @dev Create a new pair pool and mint initial liquidity tokens for `to`.
    function initialize(PoolKey calldata poolKey, address to)
        public
        payable
        lock
        returns (uint256 poolId, uint256 liquidity)
    {
        // Enforce token ordering when at least one token is ETH/ERC20 (id == 0).
        require(
            poolKey.id0 > 0 && poolKey.id1 > 0 ? true : poolKey.token0 < poolKey.token1,
            InvalidPoolTokens()
        );
        require(poolKey.swapFee <= MAX_FEE, InvalidSwapFee()); // Ensure swap fee limit.

        poolId = _computePoolId(poolKey);
        Pool storage pool = pools[poolId];
        require(pool.supply == 0, PoolExists());

        (uint256 balance0, uint256 balance1) = _getDeposits(poolId);
        bool feeOn = _mintFee(poolId, 0, 0);

        liquidity = sqrt(balance0 * balance1) - MINIMUM_LIQUIDITY;
        require(liquidity != 0, InsufficientLiquidityMinted());
        _mint(address(0), poolId, MINIMUM_LIQUIDITY);
        _mint(to, poolId, liquidity);
        unchecked {
            pool.supply = liquidity + MINIMUM_LIQUIDITY;
        }

        _update(poolId, balance0, balance1, 0, 0);
        if (feeOn) pool.kLast = uint256(pool.reserve0) * pool.reserve1;
        _clear(poolId);
        emit Mint(poolId, msg.sender, balance0, balance1);
    }

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function mint(PoolKey calldata poolKey, address to)
        public
        payable
        lock
        returns (uint256 liquidity)
    {
        uint256 poolId = _computePoolId(poolKey);
        Pool storage pool = pools[poolId];
        (uint112 reserve0, uint112 reserve1, uint256 supply) =
            (pool.reserve0, pool.reserve1, pool.supply);

        (uint256 deposit0, uint256 deposit1) = _getDeposits(poolId);
        uint256 balance0 = reserve0 + deposit0;
        uint256 balance1 = reserve1 + deposit1;

        bool feeOn = _mintFee(poolId, reserve0, reserve1);
        liquidity = min(mulDiv(deposit0, supply, reserve0), mulDiv(deposit1, supply, reserve1));
        require(liquidity != 0, InsufficientLiquidityMinted());
        _mint(to, poolId, liquidity);
        pool.supply += liquidity;

        _update(poolId, balance0, balance1, reserve0, reserve1);
        if (feeOn) pool.kLast = uint256(pool.reserve0) * pool.reserve1;
        _clear(poolId);
        emit Mint(poolId, msg.sender, deposit0, deposit1);
    }

    error InsufficientLiquidityBurned();

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function burn(PoolKey calldata poolKey, address to)
        public
        payable
        lock
        returns (uint256 amount0, uint256 amount1)
    {
        uint256 poolId = _computePoolId(poolKey);
        Pool storage pool = pools[poolId];
        (uint112 reserve0, uint112 reserve1, uint256 supply) =
            (pool.reserve0, pool.reserve1, pool.supply);

        (uint256 deposit0, uint256 deposit1) = _getDeposits(poolId);
        uint256 balance0 = reserve0 + deposit0;
        uint256 balance1 = reserve1 + deposit1;

        uint256 liquidity = balanceOf(address(this), poolId);

        bool feeOn = _mintFee(poolId, reserve0, reserve1);
        amount0 = mulDiv(liquidity, balance0, supply); // Using balances ensures pro-rata distribution.
        amount1 = mulDiv(liquidity, balance1, supply); // Using balances ensures pro-rata distribution.
        require(amount0 > 0, InsufficientLiquidityBurned());
        require(amount1 > 0, InsufficientLiquidityBurned());
        _burn(poolId, liquidity);
        unchecked {
            pool.supply -= liquidity;
        }

        _safeTransfer(poolKey.token0, to, poolKey.id0, amount0);
        _safeTransfer(poolKey.token1, to, poolKey.id1, amount1);

        balance0 = balance0 - amount0;
        balance1 = balance1 - amount1;

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
        PoolKey calldata poolKey,
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) public payable lock {
        require(amount0Out > 0 || amount1Out > 0, InsufficientOutputAmount());
        uint256 poolId = _computePoolId(poolKey);
        Pool storage pool = pools[poolId];
        (uint112 reserve0, uint112 reserve1) = (pool.reserve0, pool.reserve1);

        require(amount0Out < reserve0, InsufficientLiquidity());
        require(amount1Out < reserve1, InsufficientLiquidity());

        require(to != poolKey.token0, InvalidTo());
        require(to != poolKey.token1, InvalidTo());

        // Optimistically transfer tokens.
        if (amount0Out > 0) _safeTransfer(poolKey.token0, to, poolKey.id0, amount0Out);
        if (amount1Out > 0) _safeTransfer(poolKey.token1, to, poolKey.id1, amount1Out);
        if (data.length > 0) IVZCallee(to).vzCall(poolId, msg.sender, amount0Out, amount1Out, data);

        (uint256 deposit0, uint256 deposit1) = _getDeposits(poolId);
        uint256 balance0 = reserve0 + deposit0 - amount0Out;
        uint256 balance1 = reserve1 + deposit1 - amount1Out;

        uint256 amount0In;
        uint256 amount1In;
        unchecked {
            amount0In = balance0 > reserve0 - amount0Out ? balance0 - (reserve0 - amount0Out) : 0;
            amount1In = balance1 > reserve1 - amount1Out ? balance1 - (reserve1 - amount1Out) : 0;
        }
        require(amount0In > 0 || amount1In > 0, InsufficientInputAmount());
        uint256 balance0Adjusted = (balance0 * 10000) - (amount0In * poolKey.swapFee);
        uint256 balance1Adjusted = (balance1 * 10000) - (amount1In * poolKey.swapFee);
        require(
            balance0Adjusted * balance1Adjusted >= (uint256(reserve0) * reserve1) * 10000 ** 2, K()
        );

        _update(poolId, balance0, balance1, reserve0, reserve1);
        emit Swap(poolId, msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /// @dev Force balances to match reserves.
    function skim(PoolKey calldata poolKey, address to) public payable lock {
        uint256 poolId = _computePoolId(poolKey);
        Pool storage pool = pools[poolId];
        (uint256 balance0, uint256 balance1) = _getDeposits(poolId);
        _safeTransfer(poolKey.token0, to, poolKey.id0, balance0 - pool.reserve0);
        _safeTransfer(poolKey.token1, to, poolKey.id1, balance1 - pool.reserve1);
    }

    /// @dev Force reserves to match balances.
    function sync(PoolKey calldata poolKey) public payable lock {
        uint256 poolId = _computePoolId(poolKey);
        Pool storage pool = pools[poolId];
        (uint256 balance0, uint256 balance1) = _getDeposits(poolId);
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
    function vzCall(
        uint256 poolId,
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}
