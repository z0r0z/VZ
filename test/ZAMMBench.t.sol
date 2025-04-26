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

    function multicall(bytes[] calldata data) external returns (bytes[] memory);
}

type BalanceDelta is int256;

struct UniPoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

struct PathKey {
    address intermediateCurrency;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
    bytes hookData;
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

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address startCurrency,
        PathKey[] calldata path,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta);
}

interface IUSDTApprove {
    function approve(address, uint256) external;
}

contract ZAMMBenchTest is Test {
    IV2 constant v2 = IV2(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IV3SwapRouter constant v3Router = IV3SwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    INonfungiblePositionManager constant positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IV4router constant v4router = IV4router(0x00000000000044a361Ae3cAc094c9D1b14Eece97);
    IZAMM constant zamm = IZAMM(0x0000000000009994A7A9A6Ec18E09EbA245E8410);

    address constant usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address constant vitalik = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
    address constant usdcWhale = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    MockERC20 erc20;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("main")); // Ethereum mainnet fork.
        erc20 = new MockERC20("TEST", "TEST", 18);
        erc20.mint(vitalik, 1_000_000 ether);
        erc20.mint(usdcWhale, 1_000_000 ether);

        // Approvals
        vm.startPrank(vitalik);
        erc20.approve(address(zamm), type(uint256).max);
        erc20.approve(address(v2), type(uint256).max);
        erc20.approve(address(v3Router), type(uint256).max);
        MockERC20(usdc).approve(address(v3Router), type(uint256).max);
        MockERC20(usdc).approve(address(positionManager), type(uint256).max);
        erc20.approve(address(positionManager), type(uint256).max);
        vm.stopPrank();

        // Setup ZAMM pool (eth <> mock20)
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

        // Setup ZAMM usdc pools
        vm.startPrank(usdcWhale);
        MockERC20(erc20).approve(address(zamm), type(uint256).max);
        MockERC20(erc20).approve(address(v2), type(uint256).max);
        MockERC20(usdc).approve(address(zamm), type(uint256).max);
        MockERC20(usdc).approve(address(v2), type(uint256).max);
        IUSDTApprove(usdt).approve(address(v4router), type(uint256).max);
        MockERC20(usdc).approve(address(v4router), type(uint256).max);
        zamm.addLiquidity{value: 10 ether}(
            PoolKey(0, 0, address(0), usdc, 1),
            10 ether,
            10_000 * 1e6,
            0,
            0,
            usdcWhale,
            block.timestamp
        ); // warm up pool
        zamm.swapExactIn{value: 0.01 ether}(
            PoolKey(0, 0, address(0), usdc, 1), 0.01 ether, 0, true, usdcWhale, block.timestamp
        );

        (address token0, address token1) =
            usdc < address(erc20) ? (usdc, address(erc20)) : (address(erc20), usdc);

        zamm.addLiquidity(
            PoolKey(0, 0, token0, token1, 100),
            10 ether,
            10_000 * 1e6,
            0,
            0,
            usdcWhale,
            block.timestamp
        );
        vm.stopPrank();

        // Setup V2 pools
        vm.prank(usdcWhale);
        v2.addLiquidity(token0, token1, 10 ether, 10_000 * 1e6, 0, 0, usdcWhale, block.timestamp);

        vm.prank(vitalik);
        v2.addLiquidityETH{value: 10 ether}(
            address(erc20), 10_000 ether, 0, 0, vitalik, block.timestamp
        );

        vm.startPrank(usdcWhale);
        MockERC20(usdc).approve(address(v3Router), type(uint256).max);
        MockERC20(erc20).approve(address(v3Router), type(uint256).max);
        MockERC20(usdc).approve(address(positionManager), type(uint256).max);
        MockERC20(erc20).approve(address(positionManager), type(uint256).max);
        vm.stopPrank();

        // Setup V3 pool - first we need to initialize the pool
        uint24 fee = 3000; // 0.3% fee tier

        // We need to sort the tokens by address to match Uniswap's convention
        token0 = address(erc20) < weth ? address(erc20) : weth;
        token1 = address(erc20) < weth ? weth : address(erc20);

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

        // Now set up the USDC <> ERC20 pool for V3
        token0 = address(erc20) < usdc ? address(erc20) : usdc;
        token1 = address(erc20) < usdc ? usdc : address(erc20);

        // Initial price - assuming 1 ERC20 = 1 USDC (for simplicity)
        sqrtPriceX96 = address(erc20) < usdc
            ? 79228162514264337593543950336 // price = 1
            : 79228162514264337593543950336; // price = 1

        vm.prank(usdcWhale);
        try positionManager.createAndInitializePoolIfNecessary(token0, token1, fee, sqrtPriceX96) {
            // Pool created successfully
        } catch {
            // Pool might already exist, which is fine
        }

        // Add liquidity to USDC <> ERC20 V3 pool
        vm.prank(usdcWhale);
        try positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: address(erc20) < usdc ? 10_000 ether : 10_000 * 1e6,
                amount1Desired: address(erc20) < usdc ? 10_000 * 1e6 : 10_000 ether,
                amount0Min: 0,
                amount1Min: 0,
                recipient: usdcWhale,
                deadline: block.timestamp
            })
        ) {
            // Liquidity added successfully
        } catch {
            // In case of failure, we'll continue with the test
        }
    }

    function testV2SingleExactInEthForToken() public {
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = address(erc20);

        vm.prank(vitalik);
        v2.swapExactETHForTokens{value: 0.1 ether}(0, path, vitalik, block.timestamp);
    }

    function testV2MultihopExactInEthForToken() public {
        address[] memory path = new address[](3);
        path[0] = weth;
        path[1] = address(erc20);
        path[2] = usdc;

        vm.prank(usdcWhale);
        v2.swapExactETHForTokens{value: 0.1 ether}(0, path, vitalik, block.timestamp);
    }

    function testV3SingleExactInEthForToken() public {
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

    function testV3MultihopExactInEthForToken() public {
        vm.prank(vitalik);

        // For V3 multihop, we need to encode the path: ETH -> ERC20 -> USDC
        // The format is (token0, fee, token1, fee, token2)
        bytes memory path = abi.encodePacked(
            weth, // First token in the path (WETH)
            uint24(3000), // Fee for first pair (WETH-ERC20)
            address(erc20), // Second token in the path (ERC20)
            uint24(3000), // Fee for second pair (ERC20-USDC)
            usdc // Final token in the path (USDC)
        );

        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
            path: path,
            recipient: vitalik,
            deadline: block.timestamp,
            amountIn: 0.1 ether,
            amountOutMinimum: 0
        });

        v3Router.exactInput{value: 0.1 ether}(params);
    }

    function testZammSingleExactInEthForToken() public {
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

    function testZammSingleExactInEthToUSDC() public {
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

    function testZammMultihopExactInEthToToken() public {
        vm.startPrank(usdcWhale);

        // First swap: ETH → ERC20
        uint256 erc20Amount = zamm.swapExactIn{value: 0.1 ether}(
            PoolKey(0, 0, address(0), address(erc20), 30),
            0.1 ether,
            0,
            true,
            address(zamm),
            block.timestamp
        );

        // Second swap: ERC20 → USDC
        zamm.swapExactIn(
            PoolKey(0, 0, address(erc20), usdc, 100),
            erc20Amount, // Use the actual output from first swap
            0,
            true,
            usdcWhale,
            block.timestamp
        );

        vm.stopPrank();
    }

    function testZammMulticallMultihopExactInTokenToEth() public {
        vm.startPrank(usdcWhale);

        // Amount of USDC to swap
        uint256 usdcAmount = 1000 * 1e6; // 1000 USDC

        // Calculate expected output for first swap (USDC → ERC20)
        // Using V2-style constant product formula: amountOut = (amountIn * reserveOut) / (reserveIn + amountIn)
        // For USDC → ERC20 pool with 10,000 USDC and 10 ETH of ERC20
        uint256 reserveIn = 10_000 * 1e6; // 10,000 USDC
        uint256 reserveOut = 10 ether; // 10 ERC20
        uint256 expectedErc20Amount =
            (usdcAmount * reserveOut * 997) / ((reserveIn * 1000) + (usdcAmount * 997));

        // Calculate expected output for second swap (ERC20 → ETH)
        // For ERC20 → ETH pool with 10,000 ERC20 and 10 ETH
        uint256 reserveIn2 = 10_000 ether; // 10,000 ERC20
        uint256 reserveOut2 = 10 ether; // 10 ETH
        uint256 expectedEthAmount = (expectedErc20Amount * reserveOut2 * 997)
            / ((reserveIn2 * 1000) + (expectedErc20Amount * 997));

        // Set minimum expected outputs (with 2% slippage tolerance)
        uint256 minErc20Amount = expectedErc20Amount * 98 / 100;
        uint256 minEthAmount = expectedEthAmount * 98 / 100;

        // Create call data for both swaps
        bytes[] memory calls = new bytes[](2);

        // First hop: USDC → ERC20
        // Since ETH is not involved here, we need to sort tokens
        bool zeroForOne1 = usdc < address(erc20);
        address token0_1 = zeroForOne1 ? usdc : address(erc20);
        address token1_1 = zeroForOne1 ? address(erc20) : usdc;

        calls[0] = abi.encodeWithSelector(
            IZAMM.swapExactIn.selector,
            PoolKey(0, 0, token0_1, token1_1, 100),
            usdcAmount,
            minErc20Amount,
            zeroForOne1,
            address(zamm), // Send output to ZAMM contract for next swap
            block.timestamp
        );

        // Second hop: ERC20 → ETH (address(0))
        // ETH is always token0 in pair pools
        calls[1] = abi.encodeWithSelector(
            IZAMM.swapExactIn.selector,
            PoolKey(0, 0, address(0), address(erc20), 30),
            expectedErc20Amount,
            minEthAmount,
            false, // ETH is token0, ERC20 is token1, so it's not zeroForOne
            usdcWhale, // Send final output to the user
            block.timestamp
        );

        // Execute both swaps atomically
        zamm.multicall(calls);

        vm.stopPrank();
    }

    function testV4SingleExactInEthToUSDC() public {
        vm.prank(usdcWhale);
        UniPoolKey memory poolKey = UniPoolKey(address(0), usdc, 500, 10, address(0));
        v4router.swapExactTokensForTokens{value: 0.1 ether}(
            0.1 ether, 0, true, poolKey, "", usdcWhale, block.timestamp
        );
    }

    function testV4MultihopExactInEthToToken() public {
        vm.prank(usdcWhale);

        // Create a path for the multi-hop swap (ETH → USDC → USDT)
        PathKey[] memory path = new PathKey[](2);

        // First hop: ETH → USDC
        path[0] = PathKey({
            intermediateCurrency: usdc, // First target is USDC
            fee: 500, // Fee for ETH-USDC pool
            tickSpacing: 10, // TickSpacing for ETH-USDC pool
            hooks: address(0),
            hookData: ""
        });

        // Second hop: USDC → USDT
        path[1] = PathKey({
            intermediateCurrency: usdt, // Final target is USDT
            fee: 100, // Fee for USDC-USDT pool
            tickSpacing: 1, // TickSpacing for USDC-USDT pool
            hooks: address(0),
            hookData: ""
        });

        // Execute the swap
        v4router.swapExactTokensForTokens{value: 0.1 ether}(
            0.1 ether, // amountIn
            0, // amountOutMin (no minimum)
            address(0), // startCurrency (ETH)
            path, // path through USDC to USDT
            usdcWhale, // receiver
            block.timestamp // deadline
        );
    }
    /*
    function testV4MultihopExactInTokenToEth() public {
        vm.prank(usdcWhale);

        // Create a path for the multi-hop swap (USDT → USDC → ETH)
        PathKey[] memory path = new PathKey[](2);

        // First hop: USDT → USDC
        path[0] = PathKey({
            intermediateCurrency: usdc,
            fee: 100,
            tickSpacing: 1,
            hooks: address(0),
            hookData: ""
        });

        // Second hop: ETH → USDC
        path[1] = PathKey({
            intermediateCurrency: address(0),
            fee: 500,
            tickSpacing: 10,
            hooks: address(0),
            hookData: ""
        });

        // Execute the swap
        v4router.swapExactTokensForTokens(
            1000 * 1e6 ether, 0, usdt, path, usdcWhale, block.timestamp
        );
    }*/
}
