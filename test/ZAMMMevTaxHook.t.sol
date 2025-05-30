// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "@solady/src/auth/Ownable.sol";
import "@solady/test/utils/mocks/MockERC20.sol";

import {IZAMMHook, ZAMM} from "../src/ZAMM.sol";

contract MEVHookTest is Test {
    uint256 constant FLAG_BEFORE = 1 << 255;

    ZAMM zamm;
    MEVTaxZAMMHook hook;
    MockERC20 A;
    MockERC20 B;

    address user = makeAddr("user");

    /* ------------------------------------------------------------------ */
    /*                               setup                                */
    /* ------------------------------------------------------------------ */

    function setUp() public {
        A = new MockERC20("A", "A", 18);
        B = new MockERC20("B", "B", 18);

        zamm = new ZAMM();
        hook = new MEVTaxZAMMHook(address(this));

        uint256 SUPPLY = 1_000e18;
        A.mint(address(this), SUPPLY);
        B.mint(address(this), SUPPLY);
        A.mint(user, SUPPLY);
        B.mint(user, SUPPLY);

        A.approve(address(zamm), type(uint256).max);
        B.approve(address(zamm), type(uint256).max);
        vm.startPrank(user);
        A.approve(address(zamm), type(uint256).max);
        B.approve(address(zamm), type(uint256).max);
        vm.stopPrank();
    }

    /* ------------------------------------------------------------------ */
    /*                              helpers                               */
    /* ------------------------------------------------------------------ */

    function _poolKey() internal view returns (ZAMM.PoolKey memory key) {
        (address t0, address t1) = A < B ? (address(A), address(B)) : (address(B), address(A));
        uint256 feeOrHook = uint256(uint160(address(hook))) | FLAG_BEFORE;
        key = ZAMM.PoolKey({id0: 0, id1: 0, token0: t0, token1: t1, feeOrHook: feeOrHook});
    }

    /* ------------------------------------------------------------------ */
    /*                               test                                 */
    /* ------------------------------------------------------------------ */

    function test_DynamicFeeBoundedAndUsed() public {
        ZAMM.PoolKey memory key = _poolKey();

        // seed 100 : 100 liquidity
        zamm.addLiquidity(key, 100e18, 100e18, 0, 0, address(this), block.timestamp);

        /* ---- block 1, low tip ------------------------------------------------ */
        vm.fee(1 gwei); // base fee
        vm.txGasPrice(2 gwei); // gas price ⇒ tip = 1 gwei

        uint256 outCheap = zamm.swapExactIn(key, 1e18, 0, true, address(this), block.timestamp);
        assertGt(outCheap, 0, "has output");

        /* ---- block 2, higher tip --------------------------------------------- */
        vm.roll(block.number + 1);
        vm.txGasPrice(6 gwei); // base fee still 1 gwei ⇒ tip = 5 gwei

        uint256 outRich = zamm.swapExactIn(key, 1e18, 0, true, address(this), block.timestamp);

        // higher tip ⇒ higher/equal fee ⇒ strictly smaller output
        assertLt(outRich + 1, outCheap, "dynamic fee reduces outAmt");

        // fee bounds invariant
        (,, uint64 maxFee) = hook.poolData(uint256(keccak256(abi.encode(key))));
        assertLe(maxFee, 10_000, "fee <= 1%");
    }
}

/* -------------------------------------------------------------------------- */
/*               MEV-aware dynamic-fee hook (patched version)                 */
/* -------------------------------------------------------------------------- */
contract MEVTaxZAMMHook is IZAMMHook, Ownable {
    struct Data {
        uint128 lastBlockSeen;
        uint64 minFee;
        uint64 maxFee;
    }

    mapping(uint256 => Data) public poolData;
    mapping(uint256 => mapping(uint128 => uint256)) public topPriorityFee;

    constructor(address owner_) {
        _initializeOwner(owner_);
    }

    /* ---------- admin ------------------------------------------------------ */

    function setDefaultFee(uint256 poolId, uint64 minFee, uint64 maxFee) external onlyOwner {
        require(maxFee <= 10_000, "maxFee > 1%");
        require(minFee < maxFee, "min >= max");
        Data storage d = poolData[poolId];
        d.minFee = minFee;
        d.maxFee = maxFee;
    }

    /* ---------- IZAMMHook --------------------------------------------------- */

    function beforeAction(bytes4 sig, uint256 poolId, address, bytes calldata)
        external
        override
        returns (uint256 feeBps)
    {
        if (
            sig != ZAMM.swapExactIn.selector && sig != ZAMM.swapExactOut.selector
                && sig != ZAMM.swap.selector
        ) return 0;

        Data storage d = poolData[poolId];

        if (d.maxFee == 0) {
            // first touch → set defaults
            d.minFee = 495; // 4.95 bps
            d.maxFee = 6_900; // 69.00 bps
        }

        uint128 last = d.lastBlockSeen;
        uint64 minFee = d.minFee;
        uint64 maxFee = d.maxFee;

        uint256 topFee = topPriorityFee[poolId][last];

        /* --- saturating subtraction, avoids panic when tx pays no tip --- */
        uint256 thisFee;
        unchecked {
            thisFee = tx.gasprice > block.basefee ? tx.gasprice - block.basefee : 0;
        }

        uint256 dynFee = topFee != 0 ? (maxFee * thisFee) / topFee : maxFee;
        if (dynFee < minFee) dynFee = minFee;
        if (dynFee > maxFee) dynFee = maxFee;

        feeBps = dynFee;

        /* --- state update for next swaps ----------------------------------- */
        if (last != uint128(block.number)) {
            d.lastBlockSeen = uint128(block.number);
            topPriorityFee[poolId][uint128(block.number)] = thisFee;
        } else if (thisFee > topFee) {
            topPriorityFee[poolId][last] = thisFee;
        }
    }

    function afterAction(bytes4, uint256, address, int256, int256, int256, bytes calldata)
        external
        override
    {}
}
