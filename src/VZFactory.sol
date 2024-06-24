// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import "@solady/src/tokens/ERC20.sol";
import "@solady/src/utils/SafeTransferLib.sol";
import "@soledge/src/utils/ReentrancyGuard.sol";
import "@solady/src/utils/FixedPointMathLib.sol";

/// @notice Contemporary Uniswap V2 LP Token (VZ).
/// @author z0r0z.eth
contract VZERC20 is ERC20 {
    function name() public view virtual override returns (string memory) {
        return "VZ LP";
    }

    function symbol() public view virtual override returns (string memory) {
        return "VZLP";
    }
}

/// @notice Contemporary Uniswap V2 Pair (VZ).
/// @author z0r0z.eth
contract VZPair is VZERC20, ReentrancyGuard {
    using UQ112x112 for uint224;

    uint256 internal constant MINIMUM_LIQUIDITY = 1000;

    address internal immutable factory;
    address public immutable token0;
    address public immutable token1;

    uint112 internal reserve0;
    uint112 internal reserve1;
    uint32 internal blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast; // `reserve0` * `reserve1`, as of immediately after the most recent liquidity event.

    function getReserves()
        public
        view
        returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast)
    {
        (_reserve0, _reserve1, _blockTimestampLast) = (reserve0, reserve1, blockTimestampLast);
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
        factory = msg.sender;
        token0 = _token0;
        token1 = _token1;
    }

    error OVERFLOW();

    /// @dev Update reserves and, on the first call per block, price accumulators.
    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1)
        internal
    {
        unchecked {
            if (balance0 > type(uint112).max || balance1 > type(uint112).max) revert OVERFLOW();
            uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
            uint32 timeElapsed = blockTimestamp - blockTimestampLast; // Overflow is desired.
            if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
                // * never overflows, and + overflow is desired.
                price0CumulativeLast +=
                    uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
                price1CumulativeLast +=
                    uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
            }
            (reserve0, reserve1, blockTimestampLast) =
                (uint112(balance0), uint112(balance1), blockTimestamp);
            emit Sync(reserve0, reserve1);
        }
    }

    /// @dev If fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k).
    function _mintFee(uint112 _reserve0, uint112 _reserve1) internal returns (bool feeOn) {
        address feeTo = IVZFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast; // Gas savings.
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = FixedPointMathLib.sqrt(uint256(_reserve0) * _reserve1);
                uint256 rootKLast = FixedPointMathLib.sqrt(_kLast);
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

    error INSUFFICIENT_LIQUIDITY_MINTED();

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function mint(address to) public nonReentrant returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // Gas savings.
        uint256 balance0 = token0 == address(0)
            ? address(this).balance
            : SafeTransferLib.balanceOf(token0, address(this));
        uint256 balance1 = SafeTransferLib.balanceOf(token1, address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        bool feeOn = _mintFee(_reserve0, _reserve1);
        // Gas savings, must be defined here since `totalSupply` can update in `_mintFee()`.
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            liquidity = FixedPointMathLib.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // Permanently lock the first `MINIMUM_LIQUIDITY` tokens.
        } else {
            liquidity = FixedPointMathLib.min(
                FixedPointMathLib.mulDiv(amount0, _totalSupply, _reserve0),
                FixedPointMathLib.mulDiv(amount1, _totalSupply, _reserve1)
            );
        }
        if (liquidity == 0) revert INSUFFICIENT_LIQUIDITY_MINTED();
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * reserve1; // `reserve0` and `reserve1` are up-to-date.
        emit Mint(msg.sender, amount0, amount1);
    }

    error INSUFFICIENT_LIQUIDITY_BURNED();

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function burn(address to) public nonReentrant returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        (address _token0, address _token1) = (token0, token1);
        bool ethBase = token0 == address(0);
        uint256 balance0 =
            ethBase ? address(this).balance : SafeTransferLib.balanceOf(token0, address(this));
        uint256 balance1 = SafeTransferLib.balanceOf(_token1, address(this));
        uint256 liquidity = balanceOf(address(this));

        bool feeOn = _mintFee(_reserve0, _reserve1);
        // Gas savings, must be defined here since `totalSupply` can update in `_mintFee()`.
        uint256 _totalSupply = totalSupply();
        amount0 = FixedPointMathLib.mulDiv(liquidity, balance0, _totalSupply); // Using balances ensures pro-rata distribution.
        amount1 = FixedPointMathLib.mulDiv(liquidity, balance1, _totalSupply); // Using balances ensures pro-rata distribution.
        if (amount0 == 0 || amount1 == 0) revert INSUFFICIENT_LIQUIDITY_BURNED();
        _burn(address(this), liquidity);
        ethBase
            ? SafeTransferLib.safeTransferETH(to, amount0)
            : SafeTransferLib.safeTransfer(_token0, to, amount0);
        SafeTransferLib.safeTransfer(_token1, to, amount1);
        balance0 =
            ethBase ? address(this).balance : SafeTransferLib.balanceOf(token0, address(this));
        balance1 = SafeTransferLib.balanceOf(_token1, address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * reserve1; // `reserve0` and `reserve1` are up-to-date.
        emit Burn(msg.sender, amount0, amount1, to);
    }

    error INSUFFICIENT_OUTPUT_AMOUNT();
    error INSUFFICIENT_INPUT_AMOUNT();
    error INSUFFICIENT_LIQUIDITY();
    error INVALID_TO();
    error K();

    /// @dev This low-level function should be called from a contract which performs important safety checks.
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data)
        public
        nonReentrant
    {
        if (amount0Out == 0 && amount1Out == 0) revert INSUFFICIENT_OUTPUT_AMOUNT();
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // Gas savings.
        if (amount0Out >= _reserve0 || amount1Out >= _reserve1) revert INSUFFICIENT_LIQUIDITY();

        uint256 balance0;
        uint256 balance1;
        bool ethBase = token0 == address(0);
        {
            // Scope for _token{0,1}, avoids stack too deep errors.
            address _token0 = token0;
            address _token1 = token1;
            if (to == _token0 || to == _token1) revert INVALID_TO();
            if (amount0Out != 0) {
                ethBase
                    ? SafeTransferLib.safeTransferETH(to, amount0Out)
                    : SafeTransferLib.safeTransfer(_token0, to, amount0Out);
            } // Optimistically transfer tokens.
            if (amount1Out != 0) SafeTransferLib.safeTransfer(_token1, to, amount1Out); // Optimistically transfer tokens.
            if (data.length != 0) {
                IVZCallee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
            }
            balance0 =
                ethBase ? address(this).balance : SafeTransferLib.balanceOf(token0, address(this));
            balance1 = SafeTransferLib.balanceOf(_token1, address(this));
        }
        uint256 amount0In;
        uint256 amount1In;
        unchecked {
            amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
            amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        }
        if (amount0In == 0 && amount1In == 0) revert INSUFFICIENT_INPUT_AMOUNT();
        {
            // Scope for reserve{0,1}Adjusted, avoids stack too deep errors.
            uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
            uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);
            if (
                (balance0Adjusted * balance1Adjusted)
                    < (uint256(_reserve0) * _reserve1) * (1000 ** 2)
            ) revert K();
        }
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /// @dev Force balances to match reserves.
    function skim(address to) public nonReentrant {
        address _token0 = token0; // Gas savings.
        address _token1 = token1; // Gas savings.
        _token0 == address(0)
            ? SafeTransferLib.safeTransferETH(to, address(this).balance - reserve0)
            : SafeTransferLib.safeTransfer(
                _token0, to, (SafeTransferLib.balanceOf(_token0, address(this))) - reserve0
            );
        SafeTransferLib.safeTransfer(
            _token1, to, (SafeTransferLib.balanceOf(_token1, address(this))) - reserve1
        );
    }

    /// @dev Force reserves to match balances.
    function sync() public nonReentrant {
        bool ethBase = token0 == address(0);
        _update(
            ethBase ? address(this).balance : SafeTransferLib.balanceOf(token0, address(this)),
            SafeTransferLib.balanceOf(token1, address(this)),
            reserve0,
            reserve1
        );
    }
}

/// @notice Contemporary Uniswap V2 Factory (VZ).
/// @author z0r0z.eth
contract VZFactory {
    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    constructor(address _feeToSetter) payable {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() public view returns (uint256) {
        return allPairs.length;
    }

    error IDENTICAL_ADDRESSES();
    error PAIR_EXISTS();

    function createPair(address tokenA, address tokenB) public returns (address pair) {
        if (tokenA == tokenB) revert IDENTICAL_ADDRESSES();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (getPair[token0][token1] != address(0)) revert PAIR_EXISTS();
        pair =
            address(new VZPair{salt: keccak256(abi.encodePacked(token0, token1))}(token0, token1));
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // Populate mapping in the reverse direction.
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    error FORBIDDEN();

    function setFeeTo(address _feeTo) public payable {
        if (msg.sender != feeToSetter) revert FORBIDDEN();
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) public payable {
        if (msg.sender != feeToSetter) revert FORBIDDEN();
        feeToSetter = _feeToSetter;
    }
}

/// @dev Minimal VZ factory interface.
interface IVZFactory {
    function feeTo() external view returns (address);
}

/// @dev Minimal VZ swap call interface.
interface IVZCallee {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data)
        external;
}

/// @dev A library for handling binary fixed point numbers (https://en.wikipedia.org/wiki/Q_(number_format)).
// range: [0, 2**112 - 1]
// resolution: 1 / 2**112
library UQ112x112 {
    uint224 internal constant Q112 = 2 ** 112;

    /// @dev Encode a uint112 as a UQ112x112.
    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) * Q112; // never overflows
    }

    /// @dev Divide a UQ112x112 by a uint112, returning a UQ112x112.
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}
