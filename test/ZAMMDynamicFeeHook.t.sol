// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "@solady/test/utils/mocks/MockERC20.sol";

import {IZAMMHook, ZAMM} from "../src/ZAMM.sol";

contract ImbalanceFeeHookTest is Test {
    ZAMM zamm;
    ImbalanceFeeHook hook;
    MockERC20 A;
    MockERC20 B;

    uint256 private constant FLAG_BEFORE = 1 << 255;

    /* ------------------------- setup ------------------------- */
    function setUp() public {
        zamm = new ZAMM();
        hook = new ImbalanceFeeHook();

        A = new MockERC20("A", "A", 18);
        B = new MockERC20("B", "B", 18);

        A.mint(address(this), 1_000e18);
        B.mint(address(this), 1_000e18);

        A.approve(address(zamm), type(uint256).max);
        B.approve(address(zamm), type(uint256).max);
    }

    /* --------------------- helper: PoolKey ------------------- */
    function _pk() internal view returns (ZAMM.PoolKey memory) {
        (address t0, address t1) = A < B ? (address(A), address(B)) : (address(B), address(A));

        return ZAMM.PoolKey({
            id0: 0,
            id1: 0,
            token0: t0,
            token1: t1,
            feeOrHook: uint256(uint160(address(hook))) | FLAG_BEFORE
        });
    }

    /* ------------------- test dynamic fee -------------------- */
    function test_ImbalanceFeeIsApplied() public {
        ZAMM.PoolKey memory pk = _pk();

        /* seed a deliberately imbalanced 10 : 40 pool */
        zamm.addLiquidity(pk, 10e18, 40e18, 0, 0, address(this), block.timestamp + 1);

        /* compute fee-bps the hook *should* return:
           diff = 30, sum = 50  →  add = 30/50·70 = 42  →  fee = 72 bps             */
        uint256 feeBps = 72;
        uint256 amountIn = 1e18;

        uint256 expectedOut = _out(10e18, 40e18, amountIn, feeBps);

        uint256 gotOut = zamm.swapExactIn(
            pk,
            amountIn,
            0,
            /* zeroForOne = */
            true,
            address(this),
            block.timestamp + 1
        );

        assertEq(gotOut, expectedOut, "dynamic fee output exact");

        /* reserves updated: r0 = 11e18, r1 = 40e18 - expectedOut */
        (uint112 r0, uint112 r1,,,,,) = zamm.pools(uint256(keccak256(abi.encode(pk))));
        assertEq(uint256(r0), 11e18, "reserve0 correct");
        assertEq(uint256(r1), 40e18 - expectedOut, "reserve1 correct");
    }

    /* --------------- local getAmountOut helper --------------- */
    function _out(uint256 reserveIn, uint256 reserveOut, uint256 amountIn, uint256 feeBps)
        internal
        pure
        returns (uint256)
    {
        uint256 amtInWithFee = amountIn * (10_000 - feeBps);
        return (amtInWithFee * reserveOut) / (reserveIn * 10_000 + amtInWithFee);
    }
}

/// @title Imbalance-based Dynamic Fee
/// @notice fee = 0.30 %  +  (|reserve0-reserve1| / (reserve0+reserve1)) · 0.70 %
///         → perfectly balanced pool pays 0.30 %
///         → fully one-sided pool pays up to 1.00 %
contract ImbalanceFeeHook is IZAMMHook {
    uint256 private constant BASE_BPS = 30; // 0.30 %
    uint256 private constant MAX_ADD = 70; // extra ≤0.70 %

    /* --------------------------------------------------------------------- */
    /*                            IZAMMHook                                  */
    /* --------------------------------------------------------------------- */

    function beforeAction(
        bytes4, // sig
        uint256 poolId,
        address, // sender
        bytes calldata // data
    ) external view override returns (uint256 feeBps) {
        // msg.sender is always the ZAMM kernel
        (uint112 r0, uint112 r1,,,,,) = ZAMM(payable(msg.sender)).pools(poolId);

        if (r0 == 0 && r1 == 0) return BASE_BPS; // safety

        uint256 diff = r0 > r1 ? uint256(r0 - r1) : uint256(r1 - r0);
        uint256 add = diff * MAX_ADD / (uint256(r0) + uint256(r1)); // 0-70 bps
        feeBps = BASE_BPS + add;
    }

    // no post-processing
    function afterAction(bytes4, uint256, address, int256, int256, int256, bytes calldata)
        external
        override
    {}
}
