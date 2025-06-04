// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "@solady/test/utils/mocks/MockERC20.sol";

import {IZAMMHook, ZAMM} from "../src/ZAMM.sol";

contract KycHookTest is Test {
    /* ------------------------------------------------------------ */
    /*                      local constants                         */
    /* ------------------------------------------------------------ */

    uint256 constant FLAG_BEFORE = 1 << 255; // copied from ZAMM
    uint256 constant SWAP_FEE = 30; // 0.30 %

    /* ------------------------------------------------------------ */
    /*                        test state                            */
    /* ------------------------------------------------------------ */

    ZAMM zamm;
    MockKycHook hook;
    MockERC20 A;
    MockERC20 B;

    address alice = makeAddr("alice"); // whitelisted
    address bob = makeAddr("bob"); // _not_ whitelisted

    /* ------------------------------------------------------------ */
    /*                           setup                              */
    /* ------------------------------------------------------------ */

    function setUp() public {
        // tokens
        A = new MockERC20("A", "A", 18);
        B = new MockERC20("B", "B", 18);

        // AMM
        zamm = new ZAMM();

        // hook
        hook = new MockKycHook();
        hook.setApproved(address(this), true); // deployer can seed liquidity
        hook.setApproved(alice, true); // alice is KYC-passed

        // mint & approve
        uint256 SUPPLY = 100e18;
        A.mint(address(this), SUPPLY);
        B.mint(address(this), SUPPLY);
        A.mint(alice, SUPPLY);
        B.mint(alice, SUPPLY);
        A.mint(bob, SUPPLY);
        B.mint(bob, SUPPLY);

        A.approve(address(zamm), type(uint256).max);
        B.approve(address(zamm), type(uint256).max);

        vm.startPrank(alice);
        A.approve(address(zamm), type(uint256).max);
        B.approve(address(zamm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        A.approve(address(zamm), type(uint256).max);
        B.approve(address(zamm), type(uint256).max);
        vm.stopPrank();
    }

    /* ------------------------------------------------------------ */
    /*                         helpers                              */
    /* ------------------------------------------------------------ */

    function _poolKeyWithKyc() internal view returns (ZAMM.PoolKey memory key, uint256 poolId) {
        // honour ZAMM’s canonical ordering (lower-address token = slot0)
        (address t0, address t1) = A < B ? (address(A), address(B)) : (address(B), address(A));

        uint256 hookField = uint256(uint160(address(hook))) | FLAG_BEFORE;

        key = ZAMM.PoolKey({
            id0: 0,
            id1: 0,
            token0: t0,
            token1: t1,
            feeOrHook: hookField // before-only KYC hook
        });

        poolId = uint256(keccak256(abi.encode(key)));
    }

    /* ------------------------------------------------------------ */
    /*                         the test                             */
    /* ------------------------------------------------------------ */

    function test_KycHook_AllowsApprovedBlocksOthers() public {
        (ZAMM.PoolKey memory key, uint256 poolId) = _poolKeyWithKyc();

        /* ---------- 0. seed 10 token0 : 40 token1 liquidity ---------- */
        zamm.addLiquidity(
            key,
            10e18, // amount0
            40e18, // amount1
            0,
            0,
            address(this),
            block.timestamp + 1
        );

        /* ---------- 1. bob (NOT KYC) must be blocked ---------- */
        vm.expectRevert(abi.encodeWithSelector(MockKycHook.NotKyc.selector, bob));
        vm.prank(bob);
        zamm.swapExactIn(
            key,
            1e18, // amountIn
            0, // minOut
            true, // zeroForOne  (token0 → token1)
            bob,
            block.timestamp + 1
        );

        /* ---------- 2. alice (KYC-passed) swaps successfully ---------- */
        address inTok = key.token0; // token she sends (slot0)
        address outTok = key.token1; // token she receives (slot1)

        uint256 inBefore = MockERC20(inTok).balanceOf(alice);
        uint256 outBefore = MockERC20(outTok).balanceOf(alice);

        vm.prank(alice);
        uint256 outAmt = zamm.swapExactIn(
            key,
            1e18, // she pays 1 token0
            0,
            true, // token0 → token1
            alice,
            block.timestamp + 1
        );

        assertGt(outAmt, 0, "received some outTok");
        assertEq(MockERC20(inTok).balanceOf(alice), inBefore - 1e18, "token0 debited");
        assertEq(MockERC20(outTok).balanceOf(alice), outBefore + outAmt, "token1 credited");

        /* ---------- 3. pool reserves updated as expected ---------- */
        (uint112 r0, uint112 r1,,,,,) = zamm.pools(poolId);

        // after the swap: reserve0 = 10e18 + 1e18, reserve1 = 40e18 − outAmt
        assertEq(uint256(r0), 11e18, "reserve0 updated");
        assertEq(uint256(r1), 40e18 - outAmt, "reserve1 updated");
    }
}

/// @notice Very small KYC gate.  Anyone can extend the whitelist in tests.
contract MockKycHook is IZAMMHook {
    mapping(address => bool) public approved;

    error NotKyc(address);

    function setApproved(address who, bool ok) external {
        approved[who] = ok;
    }

    /* -------------------------- IZAMMHook -------------------------- */

    /// Block the call _before_ ZAMM moves funds if sender not whitelisted.
    function beforeAction(
        bytes4, // sig
        uint256, // poolId
        address sender,
        bytes calldata /*data*/
    ) external view override returns (uint256) {
        if (!approved[sender]) revert NotKyc(sender);
        return 0; // keep the pool-configured fee
    }

    /// No-op after-action – nothing to clean up.
    function afterAction(bytes4, uint256, address, int256, int256, int256, bytes calldata)
        external
        override
    {}
}
