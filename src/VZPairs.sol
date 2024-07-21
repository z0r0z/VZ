// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "./VZERC6909.sol";
import "./utils/Math.sol";
import "./utils/TransferHelper.sol";

contract VZPairs is VZERC6909 {
    uint256 constant MINIMUM_LIQUIDITY = 1000;

    address public feeTo;
    address public feeToSetter;

    mapping(uint256 id => Pool) public pools;

    struct Pool {
        address token0;
        address token1;
        uint112 reserve0;
        uint112 reserve1;
        uint32 blockTimestampLast;
        uint256 price0CumulativeLast;
        uint256 price1CumulativeLast;
        uint256 kLast; // `reserve0` * `reserve1`, as of immediately after the most recent liquidity event.
        uint256 totalSupply;
    }

    function totalSupply(uint256 id) public view returns (uint256) {
        return pools[id].totalSupply;
    }

    // Soledge guard (https://github.com/Vectorized/soledge/blob/main/src/utils/ReentrancyGuard.sol)
    uint256 constant _REENTRANCY_GUARD_SLOT = 0x929eee149b4bd21268;

    modifier lock() {
        assembly ("memory-safe") {
            if tload(_REENTRANCY_GUARD_SLOT) {
                mstore(0x00, 0xab143c06)
                revert(0x1c, 0x04)
            }
            tstore(_REENTRANCY_GUARD_SLOT, address())
        }
        _;
        assembly ("memory-safe") {
            tstore(_REENTRANCY_GUARD_SLOT, 0)
        }
    }

    function getReserves(uint256 id)
        public
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)
    {
        Pool storage pool = pools[id];
        (reserve0, reserve1, blockTimestampLast) =
            (pool.reserve0, pool.reserve1, pool.blockTimestampLast);
    }

    event Mint(uint256 indexed pool, address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        uint256 indexed pool,
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        uint256 indexed pool,
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint256 indexed pool, uint112 reserve0, uint112 reserve1);

    constructor(address _feeToSetter) payable {
        feeToSetter = _feeToSetter;
    }

    error Overflow();

    /// @dev Update reserves and, on the first call per block, price accumulators for the given pool `id`.
    function _update(
        uint256 id,
        uint256 balance0,
        uint256 balance1,
        uint112 reserve0,
        uint112 reserve1
    ) internal {
        unchecked {
            Pool storage pool = pools[id];
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
            emit Sync(id, pool.reserve0 = uint112(balance0), pool.reserve1 = uint112(balance1));
        }
    }

    /// @dev If fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k).
    function _mintFee(uint256 id, uint112 reserve0, uint112 reserve1)
        internal
        returns (bool feeOn)
    {
        Pool storage pool = pools[id];
        address _feeTo = feeTo;
        feeOn = _feeTo != address(0);
        if (feeOn) {
            if (pool.kLast != 0) {
                uint256 rootK = sqrt(uint256(reserve0) * reserve1);
                uint256 rootKLast = sqrt(pool.kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = pool.totalSupply * (rootK - rootKLast);
                    uint256 denominator = (rootK * 5) + rootKLast;
                    unchecked {
                        uint256 liquidity = numerator / denominator;
                        if (liquidity != 0) {
                            _mint(_feeTo, id, liquidity);
                        }
                        pool.totalSupply += liquidity;
                    }
                }
            }
        } else if (pool.kLast != 0) {
            pool.kLast = 0;
        }
    }

    error IdenticalAddresses();
    error PairExists();

    /// @dev Create a new pair pool in the singleton and mint initial liquidity tokens for `to`.
    function initialize(address to, address tokenA, address tokenB)
        public
        returns (uint256 liquidity)
    {
        if (tokenA == tokenB) revert IdenticalAddresses();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        uint256 id = uint256(keccak256(abi.encodePacked(token0, token1)));
        if (pools[id].totalSupply != 0) revert PairExists();
        (pools[id].token0, pools[id].token1) = (token0, token1);
        return mint(to, id);
    }

    error InsufficientLiquidityMinted();

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function mint(address to, uint256 id) public lock returns (uint256 liquidity) {
        Pool storage pool = pools[id];

        uint256 balance0 = pool.token0 == address(0)
            ? address(this).balance
            : getBalanceOf(pool.token0, address(this));
        uint256 balance1 = getBalanceOf(pool.token1, address(this));
        uint256 amount0 = balance0 - pool.reserve0;
        uint256 amount1 = balance1 - pool.reserve1;

        bool feeOn = _mintFee(id, pool.reserve0, pool.reserve1);
        if (pool.totalSupply == 0) {
            liquidity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), id, MINIMUM_LIQUIDITY); // Permanently lock the first `MINIMUM_LIQUIDITY` tokens.
            pool.totalSupply += MINIMUM_LIQUIDITY;
        } else {
            liquidity = min(
                mulDiv(amount0, pool.totalSupply, pool.reserve0),
                mulDiv(amount1, pool.totalSupply, pool.reserve1)
            );
        }
        if (liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(to, id, liquidity);
        pool.totalSupply += liquidity;

        _update(id, balance0, balance1, pool.reserve0, pool.reserve1);
        if (feeOn) pool.kLast = uint256(pool.reserve0) * pool.reserve1; // `reserve0` and `reserve1` are up-to-date.
        emit Mint(id, msg.sender, amount0, amount1);
    }

    error InsufficientLiquidityBurned();

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function burn(address to, uint256 id) public lock returns (uint256 amount0, uint256 amount1) {
        Pool storage pool = pools[id];

        bool ethPair = pool.token0 == address(0);
        uint256 balance0 =
            ethPair ? address(this).balance : getBalanceOf(pool.token0, address(this));
        uint256 balance1 = getBalanceOf(pool.token1, address(this));
        uint256 liquidity = balanceOf(address(this), id);

        bool feeOn = _mintFee(id, pool.reserve0, pool.reserve1);
        amount0 = mulDiv(liquidity, balance0, pool.totalSupply); // Using balances ensures pro-rata distribution.
        amount1 = mulDiv(liquidity, balance1, pool.totalSupply); // Using balances ensures pro-rata distribution.
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurned();
        _burn(address(this), id, liquidity);
        pool.totalSupply -= liquidity;
        ethPair ? safeTransferETH(to, amount0) : safeTransfer(pool.token0, to, amount0);
        safeTransfer(pool.token1, to, amount1);
        balance0 = ethPair ? address(this).balance : getBalanceOf(pool.token0, address(this));
        balance1 = getBalanceOf(pool.token1, address(this));

        _update(id, balance0, balance1, pool.reserve0, pool.reserve1);
        if (feeOn) pool.kLast = uint256(pool.reserve0) * pool.reserve1; // `reserve0` and `reserve1` are up-to-date.
        emit Burn(id, msg.sender, amount0, amount1, to);
    }

    error InsufficientOutputAmount();
    error InsufficientInputAmount();
    error InsufficientLiquidity();
    error InvalidTo();
    error K();

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function swap(
        uint256 id,
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) public lock {
        Pool storage pool = pools[id];

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

        uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
        uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);
        if (
            balance0Adjusted * balance1Adjusted
                < (uint256(pool.reserve0) * pool.reserve1) * 1000 ** 2
        ) {
            revert K();
        }

        _update(id, balance0, balance1, pool.reserve0, pool.reserve1);
        emit Swap(id, msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /// @dev Force balances to match reserves.
    function skim(address to, uint256 id) public lock {
        Pool storage pool = pools[id];
        pool.token0 == address(0)
            ? safeTransferETH(to, address(this).balance - pool.reserve0)
            : safeTransfer(pool.token0, to, (getBalanceOf(pool.token0, address(this))) - pool.reserve0);
        safeTransfer(pool.token1, to, (getBalanceOf(pool.token1, address(this))) - pool.reserve1);
    }

    /// @dev Force reserves to match balances.
    function sync(uint256 id) public lock {
        Pool storage pool = pools[id];
        _update(
            id,
            pool.token0 == address(0)
                ? address(this).balance
                : getBalanceOf(pool.token0, address(this)),
            getBalanceOf(pool.token1, address(this)),
            pool.reserve0,
            pool.reserve1
        );
    }

    /// @dev Receive native tokens.
    receive() external payable {}

    error Forbidden();

    /// @dev Set the recipient of protocol fees.
    function setFeeTo(address _feeTo) public payable {
        if (msg.sender != feeToSetter) revert Forbidden();
        feeTo = _feeTo;
    }

    /// @dev Set the manager of protocol fees.
    function setFeeToSetter(address _feeToSetter) public payable {
        if (msg.sender != feeToSetter) revert Forbidden();
        feeToSetter = _feeToSetter;
    }
}

/// @dev Minimal VZ swap call interface.
interface IVZCallee {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data)
        external;
}
