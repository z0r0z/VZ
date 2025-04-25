// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";
import "@solady/test/utils/mocks/MockERC20.sol";
import "@solady/test/utils/mocks/MockERC6909.sol";

import {ZAMM} from "../src/ZAMM.sol";
import {encode} from "../src/utils/Math.sol";

interface IV2 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH);
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        external
        pure
        returns (uint256 amountB);
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256 amountOut);
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        external
        pure
        returns (uint256 amountIn);
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

interface IV3SwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut);

    function WETH9() external view returns (address);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);
}

struct PoolKey {
    uint256 id0;
    uint256 id1;
    address token0;
    address token1;
    uint96 swapFee;
}

interface IZAMM {
    function swapExactIn(
        PoolKey calldata poolKey,
        uint256 amountIn,
        uint256 amountOutMin,
        bool zeroForOne,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountOut);

    function addLiquidity(
        PoolKey calldata poolKey,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amount0, uint256 amount1, uint256 liquidity);
}

type BalanceDelta is int256;

/// @notice Returns the key for identifying a pool
struct UniPoolKey {
    /// @notice The lower currency of the pool, sorted numerically
    address currency0;
    /// @notice The higher currency of the pool, sorted numerically
    address currency1;
    /// @notice The pool LP fee, capped at 1_000_000. If the highest bit is 1, the pool has a dynamic fee and must be exactly equal to 0x800000
    uint24 fee;
    /// @notice Ticks that involve positions must be a multiple of tick spacing
    int24 tickSpacing;
    /// @notice The hooks of the pool
    address hooks;
}

interface IV4router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        bool zeroForOne,
        UniPoolKey calldata poolKey,
        bytes calldata hookData,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta);
}

contract ZAMMBenchTest is Test {
    IV2 constant v2 = IV2(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IZAMM constant zamm = IZAMM(0x0000000000009994A7A9A6Ec18E09EbA245E8410);

    IV4router v4router = IV4router(0x00000000000044a361Ae3cAc094c9D1b14Eece97);

    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    IV3SwapRouter constant v3Router = IV3SwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    INonfungiblePositionManager constant positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    address constant vitalik = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
    address constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address constant usdcWhale = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    MockERC20 erc20;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("main")); // Ethereum mainnet fork.
        erc20 = new MockERC20("TEST", "TEST", 18);
        erc20.mint(vitalik, 1_000_000 ether);

        // Approvals
        vm.startPrank(vitalik);
        erc20.approve(address(zamm), type(uint256).max);
        erc20.approve(address(v2), type(uint256).max);
        erc20.approve(address(v3Router), type(uint256).max);
        erc20.approve(address(positionManager), type(uint256).max);
        vm.stopPrank();

        // Setup ZAMM pool
        vm.prank(vitalik);
        zamm.addLiquidity{value: 10 ether}(
            PoolKey(0, 0, address(0), address(erc20), 30),
            10 ether,
            10_000 ether,
            0,
            0,
            vitalik,
            block.timestamp
        );
        vm.stopPrank();

        // Setup ZAMM usdc pool
        vm.startPrank(usdcWhale);
        MockERC20(usdc).approve(address(zamm), type(uint256).max);
        MockERC20(usdc).approve(address(v4router), type(uint256).max);
        zamm.addLiquidity{value: 10 ether}(
            PoolKey(0, 0, address(0), address(usdc), 1),
            10 ether,
            10_000 * 1e6,
            0,
            0,
            usdcWhale,
            block.timestamp
        );
        vm.stopPrank();

        // Setup V2 pool
        vm.prank(vitalik);
        v2.addLiquidityETH{value: 10 ether}(
            address(erc20), 10_000 ether, 0, 0, vitalik, block.timestamp
        );

        // Setup V3 pool - first we need to initialize the pool
        uint24 fee = 3000; // 0.3% fee tier

        // We need to sort the tokens by address to match Uniswap's convention
        address token0 = address(erc20) < weth ? address(erc20) : weth;
        address token1 = address(erc20) < weth ? weth : address(erc20);

        // Initial price - assuming 1 ETH = 1000 TEST tokens
        // Calculating sqrt price (P)
        // sqrtPriceX96 = sqrt(P) * 2^96
        uint160 sqrtPriceX96 = address(erc20) < weth
            ? 79228162514264337593543950336 // If TEST is token0, price = 1/1000
            : 2505414483750479311864138677; // If WETH is token0, price = 1000

        vm.prank(vitalik);
        try positionManager.createAndInitializePoolIfNecessary(token0, token1, fee, sqrtPriceX96) {
            // Pool created successfully
        } catch {
            // Pool might already exist, which is fine
        }

        // Define a wide price range for liquidity
        int24 tickLower = -887220; // Min tick for full range
        int24 tickUpper = 887220; // Max tick for full range

        // Add liquidity to V3 pool
        vm.prank(vitalik);
        try positionManager.mint{value: 10 ether}(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: address(erc20) < weth ? 10_000 ether : 10 ether,
                amount1Desired: address(erc20) < weth ? 10 ether : 10_000 ether,
                amount0Min: 0,
                amount1Min: 0,
                recipient: vitalik,
                deadline: block.timestamp
            })
        ) {
            // Liquidity added successfully
        } catch {
            // In case of failure, we'll continue with the test
            // The test may use existing liquidity or fail later if there's no liquidity
        }
    }

    function testV2swapExactIn() public {
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = address(erc20);

        vm.prank(vitalik);
        v2.swapExactETHForTokens{value: 0.1 ether}(0, path, vitalik, block.timestamp);
    }

    function testV3SwapExactIn() public {
        vm.prank(vitalik);

        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: weth,
            tokenOut: address(erc20),
            fee: 3000, // 0.3% fee tier
            recipient: vitalik,
            deadline: block.timestamp,
            amountIn: 0.1 ether,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        v3Router.exactInputSingle{value: 0.1 ether}(params);
    }

    function testZammSwapExactIn() public {
        vm.prank(vitalik);
        zamm.swapExactIn{value: 0.1 ether}(
            PoolKey(0, 0, address(0), address(erc20), 30),
            0.1 ether,
            0,
            true,
            vitalik,
            block.timestamp
        );
    }

    function testZammSwapExactInForUSDC() public {
        vm.prank(usdcWhale);
        zamm.swapExactIn{value: 0.1 ether}(
            PoolKey(0, 0, address(0), address(usdc), 1),
            0.1 ether,
            0,
            true,
            usdcWhale,
            block.timestamp
        );
    }

    function testV4SwapExactInForUSDC() public {
        vm.prank(usdcWhale);
        UniPoolKey memory poolKey = UniPoolKey(address(0), usdc, 500, 10, address(0));
        v4router.swapExactTokensForTokens{value: 0.1 ether}(
            0.1 ether, 0, true, poolKey, "", usdcWhale, block.timestamp
        );
    }
}
