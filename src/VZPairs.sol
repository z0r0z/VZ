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

    /// @dev Helper function to compute `poolId` from `poolKey`.
    function _computePoolId(PoolKey memory poolKey) internal pure returns (uint256 poolId) {
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(m, mload(add(poolKey, 0x40))) // `token0`.
            mstore(add(m, 0x20), mload(poolKey)) // `id0`.
            mstore(add(m, 0x40), mload(add(poolKey, 0x60))) // `token1`.
            mstore(add(m, 0x60), mload(add(poolKey, 0x20))) // `id1`.
            mstore(add(m, 0x80), mload(add(poolKey, 0x80))) // `swapFee`.
            poolId := keccak256(m, 0xa0)
        }
    }

    /// @dev Helper function to compute deposit key from `token` and `id`.
    function _computeDepositKey(address token, uint256 id)
        internal
        pure
        returns (uint256 depositKey)
    {
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(m, token)
            mstore(add(m, 0x20), id)
            depositKey := keccak256(m, 0x40)
        }
    }

    /// @dev Helper function to fetch transient balances with precomputed key.
    function _getDepositWithKey(uint256 depositKey) internal view returns (uint256 bal) {
        assembly ("memory-safe") {
            bal := tload(depositKey)
        }
    }

    /// @dev Helper function to clear transient balances with precomputed key.
    function _clearWithKey(uint256 depositKey) internal {
        assembly ("memory-safe") {
            tstore(depositKey, 0)
        }
    }

    /// @dev Helper function to transfer tokens considering ERC6909 and ETH cases.
    function _safeTransfer(address token, address to, uint256 id, uint256 amount) internal {
        // If transferring to self, update transient storage instead.
        if (to == address(this)) {
            uint256 depositKey = _computeDepositKey(token, id);
            uint256 currentAmount = _getDepositWithKey(depositKey);
            assembly ("memory-safe") {
                tstore(depositKey, add(currentAmount, amount))
            }
        } else {
            if (token == address(0)) {
                safeTransferETH(to, amount);
            } else if (id == 0) {
                safeTransfer(token, to, amount);
            } else {
                VZERC6909(token).transfer(to, id, amount);
            }
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

    error InvalidMsgVal();

    /// @dev Helper function to pull token balances into transient storage.
    function deposit(address token, uint256 id, uint256 amount) public payable {
        if (token == address(0)) require(msg.value == amount, InvalidMsgVal());
        else _safeTransferFrom(token, msg.sender, id, amount);

        uint256 depositKey = _computeDepositKey(token, id);
        uint256 currentAmount = _getDepositWithKey(depositKey);

        assembly ("memory-safe") {
            tstore(depositKey, add(currentAmount, amount))
        }
    }

    error InsufficientLiquidityMinted();
    error InvalidPoolTokens();
    error InvalidSwapFee();
    error PoolExists();

    /// @dev Create a new pair pool and mint initial liquidity tokens for `to`.
    function initialize(PoolKey calldata poolKey, address to)
        public
        lock
        returns (uint256 poolId, uint256 liquidity)
    {
        require(
            (poolKey.token0 < poolKey.token1)
                || (
                    poolKey.token0 == poolKey.token1 && poolKey.id0 > 0 && poolKey.id1 > 0
                        && poolKey.id0 != poolKey.id1
                ),
            InvalidPoolTokens()
        );
        require(poolKey.swapFee <= MAX_FEE, InvalidSwapFee()); // Ensure swap fee limit.

        poolId = _computePoolId(poolKey);
        Pool storage pool = pools[poolId];
        require(pool.supply == 0, PoolExists());

        // Precompute deposit keys.
        uint256 depositKey0 = _computeDepositKey(poolKey.token0, poolKey.id0);
        uint256 depositKey1 = _computeDepositKey(poolKey.token1, poolKey.id1);

        uint256 balance0 = _getDepositWithKey(depositKey0);
        uint256 balance1 = _getDepositWithKey(depositKey1);
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
        // Always clear tokens that were added to the pool.
        if (balance0 > 0) _clearWithKey(depositKey0);
        if (balance1 > 0) _clearWithKey(depositKey1);
        emit Mint(poolId, msg.sender, balance0, balance1);
    }

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function mint(PoolKey calldata poolKey, address to) public lock returns (uint256 liquidity) {
        uint256 poolId = _computePoolId(poolKey);
        Pool storage pool = pools[poolId];
        (uint112 reserve0, uint112 reserve1, uint256 supply) =
            (pool.reserve0, pool.reserve1, pool.supply);

        // Precompute deposit keys.
        uint256 depositKey0 = _computeDepositKey(poolKey.token0, poolKey.id0);
        uint256 depositKey1 = _computeDepositKey(poolKey.token1, poolKey.id1);

        uint256 deposit0 = _getDepositWithKey(depositKey0);
        uint256 deposit1 = _getDepositWithKey(depositKey1);
        uint256 balance0 = reserve0 + deposit0;
        uint256 balance1 = reserve1 + deposit1;

        bool feeOn = _mintFee(poolId, reserve0, reserve1);
        liquidity = min(mulDiv(deposit0, supply, reserve0), mulDiv(deposit1, supply, reserve1));
        require(liquidity != 0, InsufficientLiquidityMinted());
        _mint(to, poolId, liquidity);
        pool.supply += liquidity;

        _update(poolId, balance0, balance1, reserve0, reserve1);
        if (feeOn) pool.kLast = uint256(pool.reserve0) * pool.reserve1;
        // Always clear tokens that were added to the pool.
        if (deposit0 > 0) _clearWithKey(depositKey0);
        if (deposit1 > 0) _clearWithKey(depositKey1);
        emit Mint(poolId, msg.sender, deposit0, deposit1);
    }

    error InsufficientLiquidityBurned();

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function burn(PoolKey calldata poolKey, address to)
        public
        lock
        returns (uint256 amount0, uint256 amount1)
    {
        uint256 poolId = _computePoolId(poolKey);
        Pool storage pool = pools[poolId];
        (uint112 reserve0, uint112 reserve1, uint256 supply) =
            (pool.reserve0, pool.reserve1, pool.supply);

        // Precompute deposit keys.
        uint256 depositKey0 = _computeDepositKey(poolKey.token0, poolKey.id0);
        uint256 depositKey1 = _computeDepositKey(poolKey.token1, poolKey.id1);

        uint256 deposit0 = _getDepositWithKey(depositKey0);
        uint256 deposit1 = _getDepositWithKey(depositKey1);
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
        // Only clear output tokens if they weren't sent back to this contract.
        if (to != address(this)) {
            if (amount0 > 0) _clearWithKey(depositKey0);
            if (amount1 > 0) _clearWithKey(depositKey1);
        }
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
    ) public lock {
        require(amount0Out > 0 || amount1Out > 0, InsufficientOutputAmount());
        uint256 poolId = _computePoolId(poolKey);
        Pool storage pool = pools[poolId];
        (uint112 reserve0, uint112 reserve1) = (pool.reserve0, pool.reserve1);

        require(amount0Out < reserve0, InsufficientLiquidity());
        require(amount1Out < reserve1, InsufficientLiquidity());

        require(to != poolKey.token0, InvalidTo());
        require(to != poolKey.token1, InvalidTo());

        // Optimistically transfer tokens. If `to` is `this`, tstore for multihop.
        if (amount0Out > 0) _safeTransfer(poolKey.token0, to, poolKey.id0, amount0Out);
        if (amount1Out > 0) _safeTransfer(poolKey.token1, to, poolKey.id1, amount1Out);
        if (data.length > 0) IVZCallee(to).vzCall(poolId, msg.sender, amount0Out, amount1Out, data);

        // Precompute deposit keys.
        uint256 depositKey0 = _computeDepositKey(poolKey.token0, poolKey.id0);
        uint256 depositKey1 = _computeDepositKey(poolKey.token1, poolKey.id1);

        uint256 deposit0 = _getDepositWithKey(depositKey0);
        uint256 deposit1 = _getDepositWithKey(depositKey1);
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
        // Always clear input tokens that were consumed.
        if (amount0In > 0) _clearWithKey(depositKey0);
        if (amount1In > 0) _clearWithKey(depositKey1);

        // Only clear output tokens if they weren't sent back to this contract.
        if (to != address(this)) {
            if (amount0Out > 0) _clearWithKey(depositKey0);
            if (amount1Out > 0) _clearWithKey(depositKey1);
        }
        emit Swap(poolId, msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /// @dev Force reserves to match balances.
    function sync(PoolKey calldata poolKey) public lock {
        uint256 poolId = _computePoolId(poolKey);
        Pool storage pool = pools[poolId];

        // Precompute deposit keys.
        uint256 depositKey0 = _computeDepositKey(poolKey.token0, poolKey.id0);
        uint256 depositKey1 = _computeDepositKey(poolKey.token1, poolKey.id1);

        uint256 deposit0 = _getDepositWithKey(depositKey0);
        uint256 deposit1 = _getDepositWithKey(depositKey1);
        uint256 balance0 = pool.reserve0 + deposit0;
        uint256 balance1 = pool.reserve1 + deposit1;
        _update(poolId, balance0, balance1, pool.reserve0, pool.reserve1);

        // Always clear tokens that were added to the pool.
        if (deposit0 > 0) _clearWithKey(depositKey0);
        if (deposit1 > 0) _clearWithKey(depositKey1);
    }

    error Unauthorized();

    /// @dev Set the protocol fee receiver.
    function setFeeTo(address feeTo) public payable {
        assembly ("memory-safe") {
            if iszero(eq(caller(), sload(0x00))) {
                mstore(0x00, 0x82b42900) // `Unauthorized()`.
                revert(0x1c, 0x04)
            }
            sstore(0x20, feeTo)
        }
    }

    /// @dev Set the protocol `feeToSetter`.
    function setFeeToSetter(address feeToSetter) public payable {
        assembly ("memory-safe") {
            if iszero(eq(caller(), sload(0x00))) {
                mstore(0x00, 0x82b42900) // `Unauthorized()`.
                revert(0x1c, 0x04)
            }
            sstore(0x00, feeToSetter)
        }
    }

    /// @dev Enables calling multiple methods in a single call to the contract.
    function multicall(bytes[] calldata data) public returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i; i != data.length; ++i) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(result, 0x20), mload(result))
                }
            }
            results[i] = result;
        }
    }

    /// @dev Calldata compression (https://github.com/Vectorized/solady/blob/main/src/utils/LibZip).
    fallback() external payable {
        assembly ("memory-safe") {
            if iszero(calldatasize()) { return(calldatasize(), calldatasize()) }
            let o := 0
            let f := not(3) // For negating the first 4 bytes.
            for { let i := 0 } lt(i, calldatasize()) {} {
                let c := byte(0, xor(add(i, f), calldataload(i)))
                i := add(i, 1)
                if iszero(c) {
                    let d := byte(0, xor(add(i, f), calldataload(i)))
                    i := add(i, 1)
                    // Fill with either 0xff or 0x00.
                    mstore(o, not(0))
                    if iszero(gt(d, 0x7f)) { calldatacopy(o, calldatasize(), add(d, 1)) }
                    o := add(o, add(and(d, 0x7f), 1))
                    continue
                }
                mstore8(o, c)
                o := add(o, 1)
            }
            let success := delegatecall(gas(), address(), 0x00, o, codesize(), 0x00)
            returndatacopy(0x00, 0x00, returndatasize())
            if iszero(success) { revert(0x00, returndatasize()) }
            return(0x00, returndatasize())
        }
    }

    // ** ROUTER SWAP

    function swapExactIn(
        PoolKey calldata poolKey,
        uint256 amountIn,
        uint256 amountOutMin,
        bool zeroForOne,
        address to,
        uint256 deadline
    ) public payable lock returns (uint256 amountOut) {
        require(block.timestamp <= deadline, Expired());
        require(amountIn > 0, InsufficientInputAmount());
        require(to != poolKey.token0, InvalidTo());
        require(to != poolKey.token1, InvalidTo());

        uint256 poolId = _computePoolId(poolKey);
        Pool storage pool = pools[poolId];
        (uint112 reserve0, uint112 reserve1) = (pool.reserve0, pool.reserve1);

        if (zeroForOne) {
            if (poolKey.token0 == address(0)) {
                require(msg.value == amountIn, InvalidMsgVal());
            } else {
                require(msg.value == 0, InvalidMsgVal());
                _safeTransferFrom(poolKey.token0, msg.sender, poolKey.id0, amountIn);
            }
        } else {
            if (poolKey.token1 == address(0)) {
                require(msg.value == amountIn, InvalidMsgVal());
            } else {
                require(msg.value == 0, InvalidMsgVal());
                _safeTransferFrom(poolKey.token1, msg.sender, poolKey.id1, amountIn);
            }
        }

        if (zeroForOne) {
            amountOut = _getAmountOut(amountIn, reserve0, reserve1, poolKey.swapFee);
            require(amountOut >= amountOutMin, InsufficientOutputAmount());
            require(amountOut < reserve1, InsufficientLiquidity());

            _safeTransfer(poolKey.token1, to, poolKey.id1, amountOut);

            uint256 balance0 = reserve0 + amountIn;
            uint256 balance1 = reserve1 - amountOut;
            _update(poolId, balance0, balance1, reserve0, reserve1);

            emit Swap(poolId, msg.sender, amountIn, 0, 0, amountOut, to);
        } else {
            amountOut = _getAmountOut(amountIn, reserve1, reserve0, poolKey.swapFee);
            require(amountOut >= amountOutMin, InsufficientOutputAmount());
            require(amountOut < reserve0, InsufficientLiquidity());

            _safeTransfer(poolKey.token0, to, poolKey.id0, amountOut);

            uint256 balance0 = reserve0 - amountOut;
            uint256 balance1 = reserve1 + amountIn;
            _update(poolId, balance0, balance1, reserve0, reserve1);

            emit Swap(poolId, msg.sender, 0, amountIn, amountOut, 0, to);
        }
    }

    function swapExactOut(
        PoolKey calldata poolKey,
        uint256 amountOut,
        uint256 amountInMax,
        bool zeroForOne,
        address to,
        uint256 deadline
    ) public payable lock returns (uint256 amountIn) {
        require(block.timestamp <= deadline, Expired());
        require(amountOut > 0, InsufficientOutputAmount());
        require(to != poolKey.token0, InvalidTo());
        require(to != poolKey.token1, InvalidTo());

        uint256 poolId = _computePoolId(poolKey);
        Pool storage pool = pools[poolId];
        (uint112 reserve0, uint112 reserve1) = (pool.reserve0, pool.reserve1);

        if (zeroForOne) {
            require(amountOut < reserve1, InsufficientLiquidity());
            amountIn = _getAmountIn(amountOut, reserve0, reserve1, poolKey.swapFee);
            require(amountIn <= amountInMax, InsufficientInputAmount());

            if (poolKey.token0 == address(0)) {
                require(msg.value >= amountIn, InvalidMsgVal());
                if (msg.value > amountIn) {
                    safeTransferETH(msg.sender, msg.value - amountIn);
                }
            } else {
                require(msg.value == 0, InvalidMsgVal());
                _safeTransferFrom(poolKey.token0, msg.sender, poolKey.id0, amountIn);
            }

            _safeTransfer(poolKey.token1, to, poolKey.id1, amountOut);

            uint256 balance0 = reserve0 + amountIn;
            uint256 balance1 = reserve1 - amountOut;
            _update(poolId, balance0, balance1, reserve0, reserve1);

            emit Swap(poolId, msg.sender, amountIn, 0, 0, amountOut, to);
        } else {
            require(amountOut < reserve0, InsufficientLiquidity());
            amountIn = _getAmountIn(amountOut, reserve1, reserve0, poolKey.swapFee);
            require(amountIn <= amountInMax, InsufficientInputAmount());

            if (poolKey.token1 == address(0)) {
                require(msg.value >= amountIn, InvalidMsgVal());
                if (msg.value > amountIn) {
                    safeTransferETH(msg.sender, msg.value - amountIn);
                }
            } else {
                require(msg.value == 0, InvalidMsgVal());
                _safeTransferFrom(poolKey.token1, msg.sender, poolKey.id1, amountIn);
            }

            _safeTransfer(poolKey.token0, to, poolKey.id0, amountOut);

            uint256 balance0 = reserve0 - amountOut;
            uint256 balance1 = reserve1 + amountIn;
            _update(poolId, balance0, balance1, reserve0, reserve1);

            emit Swap(poolId, msg.sender, 0, amountIn, amountOut, 0, to);
        }
    }

    // ** ROUTER LIQ

    error Expired();

    function addLiquidity(
        PoolKey calldata poolKey,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) public payable lock returns (uint256 amount0, uint256 amount1, uint256 liquidity) {
        require(block.timestamp <= deadline, Expired());

        uint256 poolId = _computePoolId(poolKey);
        Pool storage pool = pools[poolId];
        bool newPool = pool.supply == 0;

        if (newPool) {
            amount0 = amount0Desired;
            amount1 = amount1Desired;
        } else {
            (uint112 reserve0, uint112 reserve1) = (pool.reserve0, pool.reserve1);
            uint256 amount1Optimal = mulDiv(amount0Desired, reserve1, reserve0);

            if (amount1Optimal <= amount1Desired) {
                require(amount1Optimal >= amount1Min, InsufficientOutputAmount());
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = mulDiv(amount1Desired, reserve0, reserve1);
                require(amount0Optimal >= amount0Min, InsufficientOutputAmount());
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
            }
        }

        uint256 ethValue = msg.value;
        bool isToken0ETH = poolKey.token0 == address(0);
        bool isToken1ETH = poolKey.token1 == address(0);

        if (isToken0ETH) {
            require(ethValue >= amount0, InvalidMsgVal());
            ethValue -= amount0;
        } else {
            _safeTransferFrom(poolKey.token0, msg.sender, poolKey.id0, amount0);
        }

        if (isToken1ETH) {
            require(ethValue >= amount1, InvalidMsgVal());
            ethValue -= amount1;
        } else {
            _safeTransferFrom(poolKey.token1, msg.sender, poolKey.id1, amount1);
        }

        if (ethValue > 0) safeTransferETH(msg.sender, ethValue);

        if (newPool) {
            (, uint256 liq) = initialize(poolKey, to);
            liquidity = liq;
        } else {
            liquidity = mint(poolKey, to);
        }
    }

    function removeLiquidity(
        PoolKey calldata poolKey,
        uint256 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) public lock returns (uint256 amount0, uint256 amount1) {
        require(block.timestamp <= deadline, Expired());
        transferFrom(msg.sender, address(this), _computePoolId(poolKey), liquidity);
        (amount0, amount1) = burn(poolKey, to);
        require(amount0 >= amount0Min, InsufficientOutputAmount());
        require(amount1 >= amount1Min, InsufficientOutputAmount());
    }

    // ** ROUTER MATH

    /// @dev Calculate output amount for a given input amount.
    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, uint96 swapFee)
        internal
        pure
        returns (uint256 amountOut)
    {
        uint256 amountInWithFee = amountIn * (10000 - swapFee);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 10000) + amountInWithFee;
        return numerator / denominator;
    }

    /// @dev Calculate input amount for a desired output amount.
    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint96 swapFee)
        internal
        pure
        returns (uint256 amountIn)
    {
        uint256 numerator = reserveIn * amountOut * 10000;
        uint256 denominator = (reserveOut - amountOut) * (10000 - swapFee);
        return (numerator / denominator) + 1;
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
