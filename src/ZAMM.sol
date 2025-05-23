// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "./ZERC6909.sol";
import "./utils/Math.sol";
import "./utils/TransferHelper.sol";

// maximally simple constant product AMM singleton
// minted by z0r0z as concentric liquidity backend
contract ZAMM is ZERC6909 {
    uint256 constant MINIMUM_LIQUIDITY = 1000;
    uint256 constant MAX_FEE = 10000; // 100%

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
        uint256 kLast; // `reserve0` * `reserve1`, as of immediately after the most recent liquidity event
        uint256 supply;
    }

    // Solady (https://github.com/Vectorized/soledge/blob/main/src/utils/ReentrancyGuard.sol)
    error Reentrancy();

    modifier lock() {
        assembly ("memory-safe") {
            if tload(0x929eee149b4bd21268) {
                mstore(0x00, 0xab143c06) // `Reentrancy()`
                revert(0x1c, 0x04)
            }
            tstore(0x929eee149b4bd21268, address())
        }
        _;
        assembly ("memory-safe") {
            tstore(0x929eee149b4bd21268, 0)
        }
    }

    // ** TRANSFER

    function _safeTransfer(address token, address to, uint256 id, uint256 amount) internal {
        if (to == address(this)) {
            assembly ("memory-safe") {
                let m := mload(0x40)
                mstore(0x00, caller())
                mstore(0x20, token)
                mstore(0x40, id)
                let slot := keccak256(0x00, 0x60)
                tstore(slot, add(tload(slot), amount))
                mstore(0x40, m)
            }
        } else if (token == address(this)) {
            _mint(to, id, amount);
        } else if (token == address(0)) {
            safeTransferETH(to, amount);
        } else if (id == 0) {
            safeTransfer(token, to, amount);
        } else {
            ZERC6909(token).transfer(to, id, amount);
        }
    }

    function _safeTransferFrom(address token, uint256 id, uint256 amount) internal {
        if (token == address(this)) {
            _burn(id, amount);
        } else if (id == 0) {
            safeTransferFrom(token, amount);
        } else {
            ZERC6909(token).transferFrom(msg.sender, address(this), id, amount);
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

    constructor() payable {
        assembly ("memory-safe") {
            sstore(0x00, origin())
        }
    }

    // ** INTERNAL

    error Overflow();

    // update reserves and, on the first call per block, price accumulators for the given pool `poolId`
    function _update(
        Pool storage pool,
        uint256 poolId,
        uint256 balance0,
        uint256 balance1,
        uint112 reserve0,
        uint112 reserve1
    ) internal {
        unchecked {
            require(balance0 <= type(uint112).max, Overflow());
            require(balance1 <= type(uint112).max, Overflow());
            uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
            uint32 timeElapsed = blockTimestamp - pool.blockTimestampLast; // overflow is desired
            if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
                // * never overflows, and + overflow is desired
                pool.price0CumulativeLast +=
                    uint256(uqdiv(encode(reserve1), reserve0)) * timeElapsed;
                pool.price1CumulativeLast +=
                    uint256(uqdiv(encode(reserve0), reserve1)) * timeElapsed;
            }
            pool.blockTimestampLast = blockTimestamp;
            emit Sync(poolId, pool.reserve0 = uint112(balance0), pool.reserve1 = uint112(balance1));
        }
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(Pool storage pool, uint256 poolId, uint112 reserve0, uint112 reserve1)
        internal
        returns (bool feeOn)
    {
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
                        pool.supply += liquidity;
                    }
                }
            }
        } else if (pool.kLast != 0) {
            delete pool.kLast;
        }
    }

    // ** SWAPPERS

    error Expired();
    error InvalidMsgVal();
    error InsufficientLiquidity();
    error InsufficientInputAmount();
    error InsufficientOutputAmount();

    function swapExactIn(
        PoolKey calldata poolKey,
        uint256 amountIn,
        uint256 amountOutMin,
        bool zeroForOne,
        address to,
        uint256 deadline
    ) public payable lock returns (uint256 amountOut) {
        require(deadline >= block.timestamp, Expired());
        require(amountIn != 0, InsufficientInputAmount());

        uint256 poolId = _getPoolId(poolKey);
        Pool storage pool = pools[poolId];
        (uint112 reserve0, uint112 reserve1) = (pool.reserve0, pool.reserve1);

        bool credited;
        if (zeroForOne) {
            credited = _useTransientBalance(poolKey.token0, poolKey.id0, amountIn);
            if (credited) require(msg.value == 0, InvalidMsgVal());
        } else {
            credited = _useTransientBalance(poolKey.token1, poolKey.id1, amountIn);
        }

        if (!credited) {
            if (zeroForOne) {
                if (poolKey.token0 == address(0)) {
                    require(msg.value == amountIn, InvalidMsgVal());
                } else {
                    require(msg.value == 0, InvalidMsgVal());
                    _safeTransferFrom(poolKey.token0, poolKey.id0, amountIn);
                }
            } else {
                require(msg.value == 0, InvalidMsgVal());
                _safeTransferFrom(poolKey.token1, poolKey.id1, amountIn);
            }
        }

        if (zeroForOne) {
            amountOut = _getAmountOut(amountIn, reserve0, reserve1, poolKey.swapFee);
            require(amountOut != 0, InsufficientOutputAmount());
            require(amountOut >= amountOutMin, InsufficientOutputAmount());
            require(amountOut < reserve1, InsufficientLiquidity());

            _safeTransfer(poolKey.token1, to, poolKey.id1, amountOut);
            _update(pool, poolId, reserve0 + amountIn, reserve1 - amountOut, reserve0, reserve1);

            emit Swap(poolId, msg.sender, amountIn, 0, 0, amountOut, to);
        } else {
            amountOut = _getAmountOut(amountIn, reserve1, reserve0, poolKey.swapFee);
            require(amountOut != 0, InsufficientOutputAmount());
            require(amountOut >= amountOutMin, InsufficientOutputAmount());
            require(amountOut < reserve0, InsufficientLiquidity());

            _safeTransfer(poolKey.token0, to, poolKey.id0, amountOut);
            _update(pool, poolId, reserve0 - amountOut, reserve1 + amountIn, reserve0, reserve1);

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
        require(deadline >= block.timestamp, Expired());
        require(amountOut != 0, InsufficientOutputAmount());

        uint256 poolId = _getPoolId(poolKey);
        Pool storage pool = pools[poolId];
        (uint112 reserve0, uint112 reserve1) = (pool.reserve0, pool.reserve1);

        bool credited;
        if (zeroForOne) {
            require(amountOut < reserve1, InsufficientLiquidity());
            amountIn = _getAmountIn(amountOut, reserve0, reserve1, poolKey.swapFee);
            require(amountIn <= amountInMax, InsufficientInputAmount());

            credited = _useTransientBalance(poolKey.token0, poolKey.id0, amountIn);
            if (credited) require(msg.value == 0, InvalidMsgVal());

            if (!credited) {
                if (poolKey.token0 == address(0)) {
                    require(msg.value >= amountIn, InvalidMsgVal());
                    if (msg.value > amountIn) {
                        unchecked {
                            safeTransferETH(msg.sender, msg.value - amountIn);
                        }
                    }
                } else {
                    require(msg.value == 0, InvalidMsgVal());
                    _safeTransferFrom(poolKey.token0, poolKey.id0, amountIn);
                }
            }

            _safeTransfer(poolKey.token1, to, poolKey.id1, amountOut);
            _update(pool, poolId, reserve0 + amountIn, reserve1 - amountOut, reserve0, reserve1);

            emit Swap(poolId, msg.sender, amountIn, 0, 0, amountOut, to);
        } else {
            require(amountOut < reserve0, InsufficientLiquidity());
            amountIn = _getAmountIn(amountOut, reserve1, reserve0, poolKey.swapFee);
            require(amountIn <= amountInMax, InsufficientInputAmount());

            credited = _useTransientBalance(poolKey.token1, poolKey.id1, amountIn);

            if (!credited) {
                require(msg.value == 0, InvalidMsgVal());
                _safeTransferFrom(poolKey.token1, poolKey.id1, amountIn);
            }

            _safeTransfer(poolKey.token0, to, poolKey.id0, amountOut);
            _update(pool, poolId, reserve0 - amountOut, reserve1 + amountIn, reserve0, reserve1);

            emit Swap(poolId, msg.sender, 0, amountIn, amountOut, 0, to);
        }
    }

    error K();

    // this low-level function should be called from a contract which performs important safety checks
    function swap(
        PoolKey calldata poolKey,
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) public lock {
        require(amount0Out > 0 || amount1Out > 0, InsufficientOutputAmount());
        uint256 poolId = _getPoolId(poolKey);
        Pool storage pool = pools[poolId];
        (uint112 reserve0, uint112 reserve1) = (pool.reserve0, pool.reserve1);

        require(amount0Out < reserve0, InsufficientLiquidity());
        require(amount1Out < reserve1, InsufficientLiquidity());

        // optimistically transfer tokens - if `to` is `this`, tstore for multihop
        if (amount0Out > 0) _safeTransfer(poolKey.token0, to, poolKey.id0, amount0Out);
        if (amount1Out > 0) _safeTransfer(poolKey.token1, to, poolKey.id1, amount1Out);
        if (data.length > 0) {
            IZAMMCallee(to).zammCall(poolId, msg.sender, amount0Out, amount1Out, data);
        }

        uint256 balance0 = reserve0 + _getTransientBalance(poolKey.token0, poolKey.id0) - amount0Out;
        uint256 balance1 = reserve1 + _getTransientBalance(poolKey.token1, poolKey.id1) - amount1Out;

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

        _update(pool, poolId, balance0, balance1, reserve0, reserve1);

        emit Swap(poolId, msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // ** LIQ MGMT

    error InvalidSwapFee();
    error InvalidPoolTokens();
    error InsufficientLiquidityMinted();

    function addLiquidity(
        PoolKey calldata poolKey,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) public payable lock returns (uint256 amount0, uint256 amount1, uint256 liquidity) {
        require(deadline >= block.timestamp, Expired());

        uint256 poolId = _getPoolId(poolKey);
        Pool storage pool = pools[poolId];

        (uint112 reserve0, uint112 reserve1, uint256 supply) =
            (pool.reserve0, pool.reserve1, pool.supply);

        bool feeOn;
        if (supply != 0) {
            feeOn = _mintFee(pool, poolId, reserve0, reserve1);
            supply = pool.supply;
        } else {
            assembly ("memory-safe") {
                feeOn := iszero(iszero(sload(0x20)))
            }
        }

        if (supply == 0) {
            (amount0, amount1) = (amount0Desired, amount1Desired);
        } else {
            uint256 amount1Optimal = mulDiv(amount0Desired, reserve1, reserve0);
            if (amount1Optimal <= amount1Desired) {
                require(amount1Optimal >= amount1Min, InsufficientOutputAmount());
                (amount0, amount1) = (amount0Desired, amount1Optimal);
            } else {
                uint256 amount0Optimal = mulDiv(amount1Desired, reserve0, reserve1);
                assert(amount0Optimal <= amount0Desired);
                require(amount0Optimal >= amount0Min, InsufficientOutputAmount());
                (amount0, amount1) = (amount0Optimal, amount1Desired);
            }
        }

        bool credited = _useTransientBalance(poolKey.token0, poolKey.id0, amount0);
        if (credited) require(msg.value == 0, InvalidMsgVal());

        if (!credited) {
            if (poolKey.token0 == address(0)) {
                require(msg.value == amount0, InvalidMsgVal());
            } else {
                require(msg.value == 0, InvalidMsgVal());
                _safeTransferFrom(poolKey.token0, poolKey.id0, amount0);
            }
        }

        credited = _useTransientBalance(poolKey.token1, poolKey.id1, amount1);

        if (!credited) _safeTransferFrom(poolKey.token1, poolKey.id1, amount1);

        if (supply == 0) {
            // enforce a single, canonical poolId for any unordered pair:
            if (poolKey.token0 == address(0)) require(poolKey.id0 == 0, InvalidPoolTokens());
            require(
                // 1) two different token contracts/ETH: order by address
                poolKey.token0 < poolKey.token1
                // 2) same ERC6909 contract: two distinct, non‑zero IDs in ascending order
                || (
                    poolKey.token0 == poolKey.token1 && poolKey.id0 != 0 && poolKey.id1 != 0
                        && poolKey.id0 < poolKey.id1
                ),
                InvalidPoolTokens()
            );

            require(poolKey.swapFee <= MAX_FEE, InvalidSwapFee());
            liquidity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            require(liquidity != 0, InsufficientLiquidityMinted());
            _initMint(to, poolId, liquidity);
            unchecked {
                pool.supply = liquidity + MINIMUM_LIQUIDITY;
            }
        } else {
            liquidity = min(mulDiv(amount0, supply, reserve0), mulDiv(amount1, supply, reserve1));
            require(liquidity != 0, InsufficientLiquidityMinted());
            _mint(to, poolId, liquidity);
            pool.supply += liquidity;
        }

        _update(pool, poolId, amount0 + reserve0, amount1 + reserve1, reserve0, reserve1);
        if (feeOn) pool.kLast = uint256(pool.reserve0) * pool.reserve1;
        emit Mint(poolId, msg.sender, amount0, amount1);
    }

    function removeLiquidity(
        PoolKey calldata poolKey,
        uint256 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) public lock returns (uint256 amount0, uint256 amount1) {
        require(deadline >= block.timestamp, Expired());
        uint256 poolId = _getPoolId(poolKey);
        Pool storage pool = pools[poolId];
        (uint112 reserve0, uint112 reserve1) = (pool.reserve0, pool.reserve1);

        bool feeOn = _mintFee(pool, poolId, reserve0, reserve1);
        amount0 = mulDiv(liquidity, reserve0, pool.supply);
        amount1 = mulDiv(liquidity, reserve1, pool.supply);
        require(amount0 >= amount0Min, InsufficientOutputAmount());
        require(amount1 >= amount1Min, InsufficientOutputAmount());
        _burn(poolId, liquidity);
        unchecked {
            pool.supply -= liquidity;
        }

        _safeTransfer(poolKey.token0, to, poolKey.id0, amount0);
        _safeTransfer(poolKey.token1, to, poolKey.id1, amount1);

        unchecked {
            _update(pool, poolId, reserve0 - amount0, reserve1 - amount1, reserve0, reserve1);
        }
        if (feeOn) pool.kLast = uint256(pool.reserve0) * pool.reserve1; // `reserve0` and `reserve1` are up-to-date
        emit Burn(poolId, msg.sender, amount0, amount1, to);
    }

    // ** FACTORY

    event URI(string uri, uint256 indexed coinId);

    function make(address maker, uint256 supply, string calldata uri)
        public
        returns (uint256 coinId)
    {
        coinId =
            uint256(keccak256(abi.encodePacked(this.make.selector, msg.sender, block.timestamp)));
        _initMint(maker, coinId, supply);
        emit URI(uri, coinId);
    }

    function makeLiquid(
        address maker,
        address liqTo,
        uint256 mkrAmt,
        uint256 liqAmt,
        uint256 swapFee,
        string calldata uri
    ) public payable returns (uint256 coinId, uint256 poolId, uint256 liquidity) {
        require(swapFee <= MAX_FEE, InvalidSwapFee());
        require(liqAmt <= type(uint256).max - mkrAmt, Overflow());

        coinId = uint256(
            keccak256(abi.encodePacked(this.makeLiquid.selector, msg.sender, block.timestamp))
        );
        if (mkrAmt != 0) _initMint(maker, coinId, mkrAmt);
        emit URI(uri, coinId);

        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(m, 0)
            mstore(add(m, 0x20), coinId)
            mstore(add(m, 0x40), 0)
            mstore(add(m, 0x60), address())
            mstore(add(m, 0x80), swapFee)
            poolId := keccak256(m, 0xa0)
        }

        Pool storage pool = pools[poolId];

        bool feeOn;
        assembly ("memory-safe") {
            feeOn := iszero(iszero(sload(0x20)))
        }

        liquidity = sqrt(msg.value * liqAmt) - MINIMUM_LIQUIDITY;
        require(liquidity != 0, InsufficientLiquidityMinted());
        _initMint(liqTo, poolId, liquidity);
        unchecked {
            pool.supply = liquidity + MINIMUM_LIQUIDITY;
        }

        _update(pool, poolId, msg.value, liqAmt, 0, 0);
        if (feeOn) pool.kLast = msg.value * liqAmt;
        emit Mint(poolId, msg.sender, msg.value, liqAmt);
    }

    // ** TRANSIENT

    receive() external payable {
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(0x00, caller())
            mstore(0x20, 0)
            mstore(0x40, 0)
            let slot := keccak256(0x00, 0x60)
            tstore(slot, add(tload(slot), callvalue()))
            mstore(0x40, m)
        }
    }

    function deposit(address token, uint256 id, uint256 amount) public payable {
        require(msg.value == (token == address(0) ? amount : 0), InvalidMsgVal());
        if (token != address(0)) _safeTransferFrom(token, id, amount);
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(0x00, caller())
            mstore(0x20, token)
            mstore(0x40, id)
            let slot := keccak256(0x00, 0x60)
            tstore(slot, add(tload(slot), amount))
            mstore(0x40, m)
        }
    }

    function _getTransientBalance(address token, uint256 id) internal returns (uint256 bal) {
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(0x00, caller())
            mstore(0x20, token)
            mstore(0x40, id)
            let slot := keccak256(0x00, 0x60)
            bal := tload(slot)
            if bal { tstore(slot, 0) }
            mstore(0x40, m)
        }
    }

    function _useTransientBalance(address token, uint256 id, uint256 amount)
        internal
        returns (bool credited)
    {
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(0x00, caller())
            mstore(0x20, token)
            mstore(0x40, id)
            let slot := keccak256(0x00, 0x60)
            let bal := tload(slot)
            if iszero(lt(bal, amount)) {
                tstore(slot, sub(bal, amount))
                credited := 1
            }
            mstore(0x40, m)
        }
    }

    function recoverTransientBalance(address token, uint256 id, address to)
        public
        lock
        returns (uint256 amount)
    {
        assembly ("memory-safe") {
            let m := mload(0x40)
            mstore(0x00, caller())
            mstore(0x20, token)
            mstore(0x40, id)
            let slot := keccak256(0x00, 0x60)
            amount := tload(slot)
            if amount { tstore(slot, 0) }
            mstore(0x40, m)
        }
        if (amount != 0) _safeTransfer(token, to, id, amount);
    }

    // ** GETTERS

    function _getPoolId(PoolKey calldata poolKey) internal pure returns (uint256 poolId) {
        assembly ("memory-safe") {
            let m := mload(0x40)
            calldatacopy(m, poolKey, 0xa0)
            poolId := keccak256(m, 0xa0)
        }
    }

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

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint96 swapFee)
        internal
        pure
        returns (uint256 amountIn)
    {
        uint256 numerator = reserveIn * amountOut * 10000;
        uint256 denominator = (reserveOut - amountOut) * (10000 - swapFee);
        return (numerator / denominator) + 1;
    }

    // ** PROTOCOL FEES

    error Unauthorized();

    function setFeeTo(address feeTo) public payable {
        assembly ("memory-safe") {
            if iszero(eq(caller(), sload(0x00))) {
                mstore(0x00, 0x82b42900) // `Unauthorized()`
                revert(0x1c, 0x04)
            }
            sstore(0x20, feeTo)
        }
    }

    function setFeeToSetter(address feeToSetter) public payable {
        assembly ("memory-safe") {
            if iszero(eq(caller(), sload(0x00))) {
                mstore(0x00, 0x82b42900) // `Unauthorized()`
                revert(0x1c, 0x04)
            }
            sstore(0x00, feeToSetter)
        }
    }

    // ** BATCH
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

    // ** COMPRESS
    // Solady (https://github.com/Vectorized/solady/blob/main/src/utils/LibZip)
    fallback() external payable {
        assembly ("memory-safe") {
            if iszero(calldatasize()) { return(calldatasize(), calldatasize()) }
            let o := 0
            let f := not(3)
            for { let i := 0 } lt(i, calldatasize()) {} {
                let c := byte(0, xor(add(i, f), calldataload(i)))
                i := add(i, 1)
                if iszero(c) {
                    let d := byte(0, xor(add(i, f), calldataload(i)))
                    i := add(i, 1)
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
}

// minimal ZAMM call interface
interface IZAMMCallee {
    function zammCall(
        uint256 poolId,
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}
