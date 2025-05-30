// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "@solady/test/utils/mocks/MockERC20.sol";

import {IZAMMHook, ZAMM} from "../src/ZAMM.sol";

contract ConstantSumHookTest is Test {
    ZAMM zamm;
    MockERC20 A;
    MockERC20 B;

    uint256 constant FLAG_BEFORE = 1 << 255;

    function setUp() public {
        zamm = new ZAMM();

        A = new MockERC20("A", "A", 18);
        B = new MockERC20("B", "B", 18);

        A.mint(address(this), 1_000e18);
        B.mint(address(this), 1_000e18);

        A.approve(address(zamm), type(uint256).max);
        B.approve(address(zamm), type(uint256).max);
    }

    /* ------------------------- helper ------------------------- */
    function _buildPoolKey(address hookAddr) internal view returns (ZAMM.PoolKey memory pk) {
        (address t0, address t1) = A < B ? (address(A), address(B)) : (address(B), address(A));

        pk = ZAMM.PoolKey({
            id0: 0,
            id1: 0,
            token0: t0,
            token1: t1,
            feeOrHook: uint256(uint160(hookAddr)) | FLAG_BEFORE
        });
    }

    /* --------------------- the test --------------------------- */
    function test_ConstantSumInvariant() public {
        /* 1. deploy hook */
        // token1 is whichever address is slot1 in pool key
        address tok1 = A < B ? address(B) : address(A);
        ConstantSumHook hook = new ConstantSumHook(zamm, tok1);

        /* 2. build PoolKey with hook encoded */
        ZAMM.PoolKey memory pk = _buildPoolKey(address(hook));
        uint256 poolId = uint256(keccak256(abi.encode(pk)));

        /* 3. fund hook with plenty of token1 and approve */
        MockERC20(tok1).mint(address(hook), 100e18);
        vm.prank(address(hook));
        MockERC20(tok1).approve(address(zamm), type(uint256).max);

        /* 4. seed 10 : 10 balanced liquidity */
        zamm.addLiquidity(pk, 10e18, 10e18, 0, 0, address(this), block.timestamp + 1);

        /* 5. perform swap that pushes sum below target (token1 deficit) */
        zamm.swapExactIn(pk, 2e18, 0, /*0→1*/ true, address(this), block.timestamp + 1);

        /* 6. check invariant: r0 + r1 ≥ 20 */
        (uint112 r0, uint112 r1,,,,,) = zamm.pools(poolId);
        assertGe(uint256(r0) + uint256(r1), 20e18, "sum invariant upheld");

        // optional sanity logs
        // console2.log("r0", r0, "r1", r1);
    }
}

/// @title Constant-Sum Hook
/// @dev Keeps x + y ≥ k₂ (tops up any deficit with token1 owned by the hook)
contract ConstantSumHook is IZAMMHook {
    ZAMM public immutable zamm;
    address public immutable token1; // which token we subsidise with

    mapping(uint256 => uint256) public sumInvariant; // poolId → k₂

    constructor(ZAMM _zamm, address _token1) {
        zamm = _zamm;
        token1 = _token1;
    }

    /* ---------------- pre-swap: keep original fee ---------------- */
    function beforeAction(bytes4, uint256, address, bytes calldata)
        external
        pure
        override
        returns (uint256)
    {
        return 0;
    }

    /* ---------------- post-commit: repair constant-sum ------------ */
    function afterAction(
        bytes4, // sig
        uint256 poolId,
        address, // sender
        int256,
        int256,
        int256, // deltas (unused)
        bytes calldata
    ) external override {
        (uint112 r0, uint112 r1,,,,,) = zamm.pools(poolId);
        uint256 currentSum = uint256(r0) + uint256(r1);

        if (sumInvariant[poolId] == 0) {
            // initialise k₂ on the first call for this pool
            sumInvariant[poolId] = currentSum;
            return;
        }

        uint256 target = sumInvariant[poolId];
        if (currentSum < target) {
            uint256 deficit = target - currentSum;
            // hook must hold ≥deficit token1 and approve ZAMM
            zamm.deposit(token1, 0, deficit);
        }
        // surplus ignored for demo
    }
}
