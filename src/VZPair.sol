// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import "./VZERC20.sol";
import "./utils/Math.sol";
import "./utils/TransferHelper.sol";

/// @notice Contemporary Uniswap V2 Pair (VZ).
/// @author z0r0z.eth
contract VZPair is VZERC20 {
    uint256 constant MINIMUM_LIQUIDITY = 1000;

    address public immutable token0;
    address public immutable token1;
    address immutable _factory;

    uint112 _reserve0;
    uint112 _reserve1;
    uint32 _blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast; // `reserve0` * `reserve1`, as of immediately after the most recent liquidity event.

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

    function getReserves()
        public
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)
    {
        (reserve0, reserve1, blockTimestampLast) = (_reserve0, _reserve1, _blockTimestampLast);
    }

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor(address _token0, address _token1) payable {
        token0 = _token0;
        token1 = _token1;
        _factory = msg.sender;
    }

    error Overflow();

    /// @dev Update reserves and, on the first call per block, price accumulators.
    function _update(uint256 balance0, uint256 balance1, uint112 reserve0, uint112 reserve1)
        internal
    {
        unchecked {
            if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert Overflow();
            uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
            uint32 timeElapsed = blockTimestamp - _blockTimestampLast; // Overflow is desired.
            if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
                // * never overflows, and + overflow is desired.
                price0CumulativeLast += uint256(uqdiv(encode(reserve1), reserve0)) * timeElapsed;
                price1CumulativeLast += uint256(uqdiv(encode(reserve0), reserve1)) * timeElapsed;
            }
            _blockTimestampLast = blockTimestamp;
            emit Sync(_reserve0 = uint112(balance0), _reserve1 = uint112(balance1));
        }
    }

    /// @dev If fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k).
    function _mintFee(uint112 reserve0, uint112 reserve1) internal returns (bool feeOn) {
        address feeTo;
        address factory = _factory;
        assembly ("memory-safe") {
            mstore(0x00, 0x017e7e58) // `feeTo()`.
            pop(staticcall(gas(), factory, 0x1c, 0x04, 0x20, 0x20))
            feeTo := mload(0x20)
            feeOn := iszero(iszero(feeTo))
        }
        uint256 _kLast = kLast; // Gas savings.
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = sqrt(uint256(reserve0) * reserve1);
                uint256 rootKLast = sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply() * (rootK - rootKLast);
                    uint256 denominator = (rootK * 5) + rootKLast;
                    unchecked {
                        uint256 liquidity = numerator / denominator;
                        if (liquidity != 0) _mint(feeTo, liquidity);
                    }
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    error InsufficientLiquidityMinted();

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function mint(address to) public lock returns (uint256 liquidity) {
        (uint112 reserve0, uint112 reserve1,) = getReserves(); // Gas savings.
        uint256 balance0 =
            token0 == address(0) ? address(this).balance : getBalanceOf(token0, address(this));
        uint256 balance1 = getBalanceOf(token1, address(this));
        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;

        bool feeOn = _mintFee(reserve0, reserve1);
        // Gas savings, must be defined here since `totalSupply` can update in `_mintFee()`.
        uint256 supply = totalSupply();
        if (supply == 0) {
            liquidity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // Permanently lock the first `MINIMUM_LIQUIDITY` tokens.
        } else {
            liquidity = min(mulDiv(amount0, supply, reserve0), mulDiv(amount1, supply, reserve1));
        }
        if (liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(to, liquidity);

        _update(balance0, balance1, reserve0, reserve1);
        if (feeOn) kLast = uint256(_reserve0) * _reserve1; // `_reserve0` and `_reserve1` are up-to-date.
        emit Mint(msg.sender, amount0, amount1);
    }

    error InsufficientLiquidityBurned();

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function burn(address to) public lock returns (uint256 amount0, uint256 amount1) {
        (uint112 reserve0, uint112 reserve1,) = getReserves();
        (address _token0, address _token1) = (token0, token1);
        bool ethBase = token0 == address(0);
        uint256 balance0 = ethBase ? address(this).balance : getBalanceOf(token0, address(this));
        uint256 balance1 = getBalanceOf(_token1, address(this));
        uint256 liquidity = balanceOf(address(this));

        bool feeOn = _mintFee(reserve0, reserve1);
        // Gas savings, must be defined here since `totalSupply` can update in `_mintFee()`.
        uint256 supply = totalSupply();
        amount0 = mulDiv(liquidity, balance0, supply); // Using balances ensures pro-rata distribution.
        amount1 = mulDiv(liquidity, balance1, supply); // Using balances ensures pro-rata distribution.
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurned();
        _burn(address(this), liquidity);
        ethBase ? safeTransferETH(to, amount0) : safeTransfer(_token0, to, amount0);
        safeTransfer(_token1, to, amount1);
        balance0 = ethBase ? address(this).balance : getBalanceOf(token0, address(this));
        balance1 = getBalanceOf(_token1, address(this));

        _update(balance0, balance1, reserve0, reserve1);
        if (feeOn) kLast = uint256(_reserve0) * _reserve1; // `_reserve0` and `_reserve1` are up-to-date.
        emit Burn(msg.sender, amount0, amount1, to);
    }

    error InsufficientOutputAmount();
    error InsufficientInputAmount();
    error InsufficientLiquidity();
    error InvalidTo();
    error K();

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data)
        public
        lock
    {
        if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutputAmount();
        (uint112 reserve0, uint112 reserve1,) = getReserves(); // Gas savings.
        if (amount0Out >= reserve0 || amount1Out >= reserve1) revert InsufficientLiquidity();

        address _token0 = token0;
        address _token1 = token1;
        bool ethBased = _token0 == address(0);
        if (to == _token0 || to == _token1) revert InvalidTo();
        // Optimistically transfer tokens.
        if (amount0Out != 0) {
            ethBased ? safeTransferETH(to, amount0Out) : safeTransfer(_token0, to, amount0Out);
        }
        if (amount1Out != 0) safeTransfer(_token1, to, amount1Out);
        if (data.length != 0) {
            IVZCallee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
        }
        uint256 balance0 = ethBased ? address(this).balance : getBalanceOf(_token0, address(this));
        uint256 balance1 = getBalanceOf(_token1, address(this));

        uint256 amount0In;
        uint256 amount1In;
        unchecked {
            amount0In = balance0 > reserve0 - amount0Out ? balance0 - (reserve0 - amount0Out) : 0;
            amount1In = balance1 > reserve1 - amount1Out ? balance1 - (reserve1 - amount1Out) : 0;
        }
        if (amount0In == 0 && amount1In == 0) revert InsufficientInputAmount();

        uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
        uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);
        if (balance0Adjusted * balance1Adjusted < (uint256(reserve0) * reserve1) * 1000 ** 2) {
            revert K();
        }

        _update(balance0, balance1, reserve0, reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /// @dev Force balances to match reserves.
    function skim(address to) public lock {
        address _token0 = token0; // Gas savings.
        address _token1 = token1; // Gas savings.
        _token0 == address(0)
            ? safeTransferETH(to, address(this).balance - _reserve0)
            : safeTransfer(_token0, to, (getBalanceOf(_token0, address(this))) - _reserve0);
        safeTransfer(_token1, to, (getBalanceOf(_token1, address(this))) - _reserve1);
    }

    /// @dev Force reserves to match balances.
    function sync() public lock {
        _update(
            token0 == address(0) ? address(this).balance : getBalanceOf(token0, address(this)),
            getBalanceOf(token1, address(this)),
            _reserve0,
            _reserve1
        );
    }

    /// @dev Receive native tokens.
    receive() external payable {}
}

/// @dev Minimal VZ swap call interface.
interface IVZCallee {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data)
        external;
}
