// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {ZAMM} from "../src/ZAMM.sol";
import {ZAMMLaunch} from "../periphery/ZAMMLaunch.sol";

contract ZAMMLaunchpadTest is Test {
    /* ── deployed artefacts ───────────────────────────────────────────── */
    ZAMM constant zamm = ZAMM(payable(0x000000000000040470635EB91b7CE4D132D616eD));
    ZAMMLaunch pad;

    /* ── reusable scratch arrays ─────────────────────────────────────── */
    uint96[] coins;
    uint96[] prices;

    /* ── actors ──────────────────────────────────────────────────────── */
    address creator = address(this);
    address buyer1 = address(0xB0B1);
    address buyer2 = address(0xB0B2);

    /* ================================================================== */
    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("main"));
        pad = new ZAMMLaunch();

        vm.deal(creator, 100 ether);
        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);

        coins.push(600);
        prices.push(600);
        coins.push(400);
        prices.push(400);
        coins.push(200);
        prices.push(200);
    }

    /* ── helpers ─────────────────────────────────────────────────────── */
    function _poolId(uint256 coinId) internal pure returns (uint256) {
        return uint256(
            keccak256(abi.encode(uint256(0), coinId, address(0), address(zamm), uint256(100)))
        );
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    /* ==================================================================
    0.  Gas snapshot ───────────────────────────────────────────────── */
    function testThreeTrancheSaleGasCost() public {
        pad.launch(0, 0, "uri", coins, prices);
    }

    /* ==================================================================
    1.  Manual finalize after partial sale ─────────────────────────── */
    function testTwoTrancheManualFinalize() public {
        delete coins;
        delete prices;
        coins.push(600);
        coins.push(400);
        prices.push(uint96(1 ether));
        prices.push(uint96(2 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        vm.prank(buyer1);
        pad.buy{value: 1 ether}(coinId, 0);

        /* duplicates are re-minted during buy → pad balance stays 2 000 */
        assertEq(zamm.balanceOf(address(pad), coinId), 2_000);

        vm.warp(block.timestamp + 8 days);
        vm.prank(buyer2);
        pad.finalize(coinId);

        uint256 expectedLp = _sqrt(1 ether * 600) - 1_000;
        uint256 pid = _poolId(coinId);
        assertEq(zamm.balanceOf(address(pad), pid), expectedLp);

        /* pool seeds 600 tokens → 2 000 − 600 = 1 400 duplicates remain */
        assertEq(zamm.balanceOf(address(pad), coinId), 1_400);

        vm.expectRevert(ZAMMLaunch.Finalized.selector);
        pad.finalize(coinId);
    }

    /* ==================================================================
    2.  Partial fill then “take remainder” ─────────────────────────── */
    function testPartialFillExplicitSize() public {
        delete coins;
        delete prices;
        coins.push(1_000);
        prices.push(uint96(2 ether));

        uint256 id = pad.launch(0, 0, "uri", coins, prices);

        vm.prank(buyer1);
        pad.buy{value: 1 ether}(id, 0);

        (,,, uint128 raisedHalf,) = pad.sales(id);
        assertEq(raisedHalf, 1 ether);

        vm.prank(buyer2);
        pad.buy{value: 1 ether}(id, 0);

        (,,, uint128 raisedFin,) = pad.sales(id);
        assertEq(raisedFin, 0);

        vm.expectRevert(ZAMMLaunch.Finalized.selector);
        pad.finalize(id);
    }

    /* ==================================================================
    3.  Early-finalize guard works ─────────────────────────────────── */
    function testEarlyFinalizeReverts() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 id = pad.launch(0, 0, "u", coins, prices);

        vm.expectRevert(ZAMMLaunch.Pending.selector);
        pad.finalize(id);
    }

    /* ==================================================================
    4.  Idempotent finalize ────────────────────────────────────────── */
    function testFinalizeTwiceNoOp() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 id = pad.launch(0, 0, "u", coins, prices);

        vm.expectRevert(ZAMMLaunch.Pending.selector);
        pad.finalize(id);

        vm.prank(buyer1);
        pad.buy{value: 1 ether}(id, 0);

        vm.expectRevert(ZAMMLaunch.Finalized.selector);
        pad.finalize(id);
    }

    /* ==================================================================
    5.  Fast path (auto-LP, no creator) ────────────────────────────── */
    function testUnlockedLpFlow() public {
        delete coins;
        delete prices;
        coins.push(500);
        prices.push(uint96(1 ether));

        uint256 id = pad.launch(0, 0, "u", coins, prices);

        vm.prank(buyer1);
        pad.buy{value: 1 ether}(id, 0);

        uint256 pid = _poolId(id);
        assertGt(zamm.balanceOf(address(pad), pid), 0);

        vm.expectRevert(ZAMMLaunch.Finalized.selector);
        pad.finalize(id);
    }

    /* ==================================================================
    6.  trancheRemainingWei helper ─────────────────────────────────── */
    function testTrancheRemainingWei() public {
        delete coins;
        delete prices;
        coins.push(1_000);
        prices.push(uint96(2 ether));

        uint256 coinId = pad.launch(0, 0, "u", coins, prices);

        assertEq(uint256(pad.trancheRemainingWei(coinId, 0)), 2 ether);

        vm.prank(buyer1);
        pad.buy{value: 1 ether}(coinId, 0);
        assertEq(uint256(pad.trancheRemainingWei(coinId, 0)), 1 ether);

        vm.prank(buyer2);
        pad.buy{value: 1 ether}(coinId, 0);
        assertEq(uint256(pad.trancheRemainingWei(coinId, 0)), 0);

        assertEq(uint256(pad.trancheRemainingWei(coinId, 1)), 0);
    }

    /* ==================================================================
    7.  Direct ZAMM.fillOrder is blocked ───────────────────────────── */
    function testCannotDirectFillOrder() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        (, uint96 dlRaw,,,) = pad.sales(coinId);
        uint56 dl = uint56(dlRaw);

        vm.prank(buyer1);
        vm.expectRevert();
        zamm.fillOrder{value: 1 ether}(
            address(pad),
            address(zamm),
            coinId,
            coins[0],
            address(0),
            0,
            prices[0],
            dl,
            true,
            uint96(1 ether)
        );
    }

    /* ==================================================================
    8.  buy() after tranche deadline reverts Expired() ─────────────── */
    function testBuyAfterFinalizeReverts() public {
        delete coins;
        delete prices;
        coins.push(50);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "u", coins, prices);

        vm.warp(block.timestamp + 8 days);

        vm.prank(buyer1);
        vm.expectRevert(ZAMM.Expired.selector);
        pad.buy{value: 1 ether}(coinId, 0);
    }

    /* ==================================================================
    9.  coinWithPool must send ETH ─────────────────────────────────── */
    function testCoinWithPoolRevertsOnZeroEth() public {
        vm.expectRevert();
        pad.coinWithPool(100, 0, 0, "uri");
    }

    /* ==================================================================
    10. coinWithPool happy-path ────────────────────────────────────── */
    function testCoinWithPoolSuccessMintsLp() public {
        vm.deal(address(this), 1 ether);

        (uint256 coinId, uint256 lpMinted) = pad.coinWithPool{value: 1 ether}(100, 0, 0, "uri");

        uint256 pid = _poolId(coinId);
        uint256 expectedLp = _sqrt(1 ether * 100) - 1_000;

        assertEq(lpMinted, expectedLp);
        assertEq(zamm.balanceOf(address(this), pid), expectedLp);
        assertEq(zamm.balanceOf(address(pad), coinId), 0);
    }

    /* ==================================================================
    11. Finalize should revert if nothing sold ─────────────────────── */
    function testZeroSaleCannotFinalize() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        vm.warp(block.timestamp + 8 days);
        vm.expectRevert(ZAMMLaunch.NoRaise.selector);
        pad.finalize(coinId);
    }

    /* ==================================================================
    12. Direct ETH transfer blocked by receive() ───────────────────── */
    function testUnauthorizedDirectETHReverts() public {
        vm.deal(buyer1, 1 ether);

        vm.prank(buyer1);
        (bool ok,) = address(pad).call{value: 1 ether}("");
        assertFalse(ok);
    }

    /* ==================================================================
    13. Multi-tranche partial & auto-finalize ──────────────────────── */
    function testMultiTranchePartialAndFinalize() public {
        delete coins;
        delete prices;
        coins.push(200);
        coins.push(300);
        prices.push(uint96(1 ether));
        prices.push(uint96(2 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        vm.prank(buyer1);
        pad.buy{value: 0.5 ether}(coinId, 0);

        /* duplicates unchanged */
        assertEq(zamm.balanceOf(address(pad), coinId), 1_000);
        assertEq(uint256(pad.trancheRemainingWei(coinId, 0)), 0.5 ether);

        vm.prank(buyer2);
        pad.buy{value: 0.5 ether}(coinId, 0);

        assertEq(uint256(pad.trancheRemainingWei(coinId, 0)), 0);

        vm.prank(buyer1);
        pad.buy{value: 2 ether}(coinId, 1);

        uint256 expectedLp = _sqrt(3 ether * 500) - 1_000;
        uint256 pid = _poolId(coinId);
        assertEq(zamm.balanceOf(address(pad), pid), expectedLp);

        /* duplicates left: 1 000 − 500 = 500 */
        assertEq(zamm.balanceOf(address(pad), coinId), 500);

        vm.expectRevert(ZAMMLaunch.Finalized.selector);
        pad.finalize(coinId);
    }

    /* ==================================================================
    14. Mulmod guard – tiny ETH amount reverts ─────────────────────── */
    function testBuyWithTooLittleEthReverts() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        vm.prank(buyer1);
        vm.expectRevert(ZAMMLaunch.InvalidMsgVal.selector);
        pad.buy{value: 0.009 ether}(coinId, 0);
    }

    /* ==================================================================
    15. Finalize before deadline / after auto-finalize ─────────────── */
    function testFinalizeBeforeDeadlineReverts() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        vm.expectRevert(ZAMMLaunch.Pending.selector);
        pad.finalize(coinId);

        vm.prank(buyer1);
        pad.buy{value: 1 ether}(coinId, 0);

        vm.expectRevert(ZAMMLaunch.Finalized.selector);
        pad.finalize(coinId);
    }

    /* 16 ───────────────── Creator immediate allocation ─────────────── */
    function testLaunchWithCreatorImmediateAllocation() public {
        /* ── setup single-tranche sale (100 tokens ↔ 1 ETH) ─────────── */
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        /* launch: creator gets 50 escrowed, no lock-up */
        uint256 coinId = pad.launch(50, 0, "uri", coins, prices);

        /* creator balance is still zero (tokens held in pad) */
        assertEq(zamm.balanceOf(address(this), coinId), 0);

        /* buyer1 buys entire tranche → triggers auto-finalize */
        vm.prank(buyer1);
        pad.buy{value: 1 ether}(coinId, 0);

        /* ── creator claims the escrowed 50 tokens ──────────────────── */
        pad.claim(coinId, 50);
        assertEq(zamm.balanceOf(address(this), coinId), 50);

        /* after pool-seed (100) and creator claim (50) pad holds 100 */
        assertEq(zamm.balanceOf(address(pad), coinId), 100);

        /* ── buyer claims the 100 tokens they purchased ─────────────── */
        vm.prank(buyer1);
        pad.claim(coinId, 100);
        assertEq(zamm.balanceOf(buyer1, coinId), 100);

        /* pad balance is now zero (all duplicates accounted for) */
        assertEq(zamm.balanceOf(address(pad), coinId), 0);
    }

    /* ==================================================================
    17. Creator lock-up then unlock ────────────────────────────────── */
    function testLaunchWithCreatorLockupAndUnlock() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        /* unlock > SALE_DURATION to satisfy InvalidUnlock guard */
        uint256 unlockTime = block.timestamp + 8 days;
        uint256 coinId = pad.launch(50, unlockTime, "uri", coins, prices);

        assertEq(zamm.balanceOf(address(this), coinId), 0);

        vm.warp(unlockTime + 1);
        zamm.unlock(address(zamm), address(this), coinId, 50, unlockTime);

        assertEq(zamm.balanceOf(address(this), coinId), 50);
    }

    /* ==================================================================
    18. Invalid tranche index in buy() ─────────────────────────────── */
    function testBuyInvalidTrancheIndexReverts() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        vm.prank(buyer1);
        vm.expectRevert(ZAMMLaunch.BadIndex.selector);
        pad.buy{value: 1 ether}(coinId, 1);
    }

    /* ==================================================================
    19. trancheRemainingWei invalid cases ──────────────────────────── */
    function testTrancheRemainingWeiInvalidSaleOrIndex() public {
        assertEq(pad.trancheRemainingWei(999, 0), 0);

        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));
        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        assertEq(pad.trancheRemainingWei(coinId, 1), 0);
    }

    /* ==================================================================
    20. finalize after partial sale leaves extra duplicates ────────── */
    function testPartialSaleFinalizeLeavesLockedTokens() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        vm.prank(buyer1);
        pad.buy{value: 0.5 ether}(coinId, 0);

        /* duplicates unchanged: 200 */
        assertEq(zamm.balanceOf(address(pad), coinId), 200);

        vm.warp(block.timestamp + 8 days);
        pad.finalize(coinId);

        /* 200 − 50 = 150 duplicates remain */
        assertEq(zamm.balanceOf(address(pad), coinId), 150);
    }

    /* ==================================================================
    21. coinWithPool + creatorSupply happy-path ────────────────────── */
    function testCoinWithPoolWithCreatorSupply() public {
        vm.deal(address(this), 1 ether);

        (uint256 coinId, uint256 lpMinted) = pad.coinWithPool{value: 1 ether}(100, 50, 0, "uri");

        assertEq(zamm.balanceOf(address(this), coinId), 50);
        assertEq(zamm.balanceOf(address(pad), coinId), 0);

        uint256 pid = _poolId(coinId);
        uint256 expectedLp = _sqrt(1 ether * 100) - 1_000;
        assertEq(lpMinted, expectedLp);
        assertEq(zamm.balanceOf(address(this), pid), expectedLp);
    }

    /* ==================================================================
    22. Zero-ETH buy() reverts via mulmod guard ────────────────────── */
    function testBuyWithZeroEthReverts() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        vm.prank(buyer1);
        vm.expectRevert(ZAMMLaunch.InvalidMsgVal.selector);
        pad.buy{value: 0}(coinId, 0);
    }

    /* ==================================================================
    23. Launch array length mismatch ───────────────────────────────── */
    function testLaunchInvalidArrayLengthsReverts() public {
        delete coins;
        delete prices;
        coins.push(100);
        coins.push(50);
        prices.push(uint96(1 ether));

        vm.expectRevert(ZAMMLaunch.InvalidArray.selector);
        pad.launch(0, 0, "uri", coins, prices);
    }

    /* ==================================================================
    24. Auto-finalize then further buy() must revert Finalized() ───── */
    function testBuyAfterImmediateSelloutButBeforeDeadlineReverts() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        vm.prank(buyer1);
        pad.buy{value: 1 ether}(coinId, 0);

        vm.prank(buyer2);
        vm.expectRevert(ZAMMLaunch.Finalized.selector);
        pad.buy{value: 1 ether}(coinId, 0);
    }

    /* ==================================================================
    25. Non-divisible payment triggers mulmod revert ───────────────── */
    function testMulmodGuardRejectsNonIntegralPurchase() public {
        delete coins;
        delete prices;
        /* 3 tokens ↔ 2 ETH; gcd = 1 → only 2-ETH payments legal */
        coins.push(3);
        prices.push(uint96(2 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        vm.prank(buyer1);
        vm.expectRevert(ZAMMLaunch.InvalidMsgVal.selector);
        pad.buy{value: 1 ether}(coinId, 0);
    }

    /* ==================================================================
    26. coinWithPoolCustom – lpLock success & timed unlock ─────────── */
    function testCoinWithPoolCustomLpLockUnlock() public {
        vm.deal(address(this), 2 ether);

        uint256 swapFee = 75; // ≤ MAX_FEE_BPS
        uint256 poolAmt = 100;
        uint256 unlockAt = block.timestamp + 30 days;

        (uint256 coinId, uint256 lpMinted) =
            pad.coinWithPoolCustom{value: 1 ether}(true, swapFee, poolAmt, 0, unlockAt, "uri");

        /* LP minted to launchpad and immediately locked for this tester */
        uint256 poolId =
            uint256(keccak256(abi.encode(uint256(0), coinId, address(0), address(zamm), swapFee)));

        /* LPs are burned into the timelock – launchpad holds none */
        assertEq(zamm.balanceOf(address(pad), poolId), 0);
        assertEq(zamm.balanceOf(address(zamm), poolId), 0);

        bytes32 lockHash =
            keccak256(abi.encode(address(zamm), address(this), poolId, lpMinted, unlockAt));
        assertEq(zamm.lockups(lockHash), unlockAt);

        /* premature unlock must revert with Pending() */
        vm.expectRevert(ZAMM.Pending.selector);
        zamm.unlock(address(zamm), address(this), poolId, lpMinted, unlockAt);

        /* after time-warp the LP unlocks successfully */
        vm.warp(unlockAt + 1);
        zamm.unlock(address(zamm), address(this), poolId, lpMinted, unlockAt);
        assertEq(zamm.balanceOf(address(this), poolId), lpMinted);
        assertEq(
            zamm.lockups(
                keccak256(abi.encode(address(zamm), address(this), poolId, lpMinted, unlockAt))
            ),
            0
        );
    }

    /* ==================================================================
    27. coinWithPoolCustom – swapFee > 10_000 reverts ──────────────── */
    function testCoinWithPoolCustomInvalidFeeReverts() public {
        vm.deal(address(this), 1 ether);
        uint256 invalidFee = 10_001;

        vm.expectRevert(); // addLiquidity deep revert (hook path) or front-end guard if you added one
        pad.coinWithPoolCustom{value: 1 ether}(false, invalidFee, 100, 0, 0, "uri");
    }

    /* ==================================================================
    28. coinWithPoolCustom – lpLock but past unlock time reverts ───── */
    function testCoinWithPoolCustomPastUnlockReverts() public {
        vm.deal(address(this), 1 ether);
        uint256 swapFee = 50;
        uint256 pastTime = block.timestamp; // not > now

        vm.expectRevert(); // Z.lockup will revert with Expired()
        pad.coinWithPoolCustom{value: 1 ether}(true, swapFee, 100, 0, pastTime, "uri");
    }

    /* ==================================================================
    29.  claim() before finalization must revert Pending() ─────────── */
    function testClaimBeforeFinalizeReverts() public {
        /* set up 100-coin tranche @ 1 ETH */
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        /* buyer purchases half; sale NOT yet finalized */
        vm.prank(buyer1);
        pad.buy{value: 0.5 ether}(coinId, 0);

        /* premature claim should fail */
        vm.prank(buyer1);
        vm.expectRevert(ZAMMLaunch.Pending.selector);
        pad.claim(coinId, 50);

        /* warp beyond sale window & finalize */
        vm.warp(block.timestamp + 8 days);
        pad.finalize(coinId);

        /* now claim succeeds */
        vm.prank(buyer1);
        pad.claim(coinId, 50);
        assertEq(zamm.balanceOf(buyer1, coinId), 50);
    }

    /* ==================================================================
    30.  claim() over-balance reverts via checked-arithmetic underflow */
    function testClaimOverBalanceReverts() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        /* sell out → auto-finalize */
        vm.prank(buyer1);
        pad.buy{value: 1 ether}(coinId, 0);

        /* first claim OK */
        vm.prank(buyer1);
        pad.claim(coinId, 100);

        /* second claim (over-balance) must revert with ArithmeticError */
        vm.prank(buyer1);
        vm.expectRevert(stdError.arithmeticError);
        pad.claim(coinId, 1);
    }

    /* ==================================================================
    31.  Attacker tries Z.swapExactIn(launchCoin→ETH) pre-finalize ──── */
    function testSwapExactInLaunchCoinFails() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));
        uint256 coinId = pad.launch(0, 0, "u", coins, prices);

        /* attacker fakes a poolKey (will fail because pool not created) */
        ZAMM.PoolKey memory key = ZAMM.PoolKey({
            id0: 0,
            id1: coinId,
            token0: address(0),
            token1: address(zamm),
            feeOrHook: 100
        });

        vm.prank(buyer1);
        vm.expectRevert(); // no pool / invalid transferFrom
        zamm.swapExactIn(key, 1, 0, false, buyer1, block.timestamp);
    }

    /* ==================================================================
    32.  Bogus maker order can be created but cannot be filled ───────── */
    function testBogusMakerOrderCannotFill() public {
        /* set up a sale so we have a valid coinId                        */
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));
        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        /* ── attacker (buyer1) posts an order “selling” 10 pad-coins ─── */
        vm.prank(buyer1);
        bytes32 bogusHash = zamm.makeOrder(
            address(zamm), // tokenIn  = pad-coin contract
            coinId, // idIn     = coinId
            10, // amtIn    = 10 coins (maker leg)
            address(0),
            0, // want ETH
            uint96(0.1 ether), // amtOut   = 0.1 ETH
            uint56(block.timestamp + 1 days),
            false
        );

        /* order exists ⇒ deadline non-zero                                */
        (, uint56 deadline,,) = zamm.orders(bogusHash);
        assertGt(deadline, 0);

        /* ── honest taker (buyer2) tries to fill; must revert ─────────── */
        vm.prank(buyer2);
        vm.expectRevert(); // _burn underflow inside _payIn
        zamm.fillOrder{value: 0.1 ether}(
            buyer1, // maker
            address(zamm),
            coinId,
            10,
            address(0),
            0,
            uint96(0.1 ether),
            uint56(block.timestamp + 1 days),
            false,
            0
        );
    }

    /* ==================================================================
    33. buyExactCoins flow: refund, locked balance, finalise, claim ─── */
    function testBuyExactCoinsFlow() public {
        /* ── Sale setup: 4 coins total @ 1 ETH (0.25 ea) ─────────────── */
        delete coins;
        delete prices;
        coins.push(4);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        /* ── Buyer-1 purchases 3 coins, sends 1 ETH (0.25 surplus) ───── */
        vm.deal(buyer1, 1 ether);
        uint256 balBefore = buyer1.balance;

        vm.prank(buyer1);
        pad.buyExactCoins{value: 1 ether}(coinId, 0, 3);

        /* refund check: balance decreased by exactly 0.75 ETH */
        assertApproxEqAbs(buyer1.balance, balBefore - 0.75 ether, 1);

        /* locked balance recorded inside launchpad */
        assertEq(pad.balances(coinId, buyer1), 3);

        /* ── Buyer-2 buys last coin, triggers auto-finalise ──────────────── */
        vm.deal(buyer2, 0.25 ether);
        vm.prank(buyer2);
        pad.buyExactCoins{value: 0.25 ether}(coinId, 0, 1);

        /* launchpad’s Sale struct is now cleared (creator == 0) */
        (address saleCreator,,,,) = pad.sales(coinId);
        assertEq(saleCreator, address(0)); // sale finalised

        /* ── Buyer-1 claims their 3 coins, balance unlocks ───────────── */
        vm.prank(buyer1);
        pad.claim(coinId, 3);

        assertEq(zamm.balanceOf(buyer1, coinId), 3); // ERC-6909 balance
        assertEq(pad.balances(coinId, buyer1), 0); // launchpad slot cleared

        /* Buyer-2 can also claim */
        vm.prank(buyer2);
        pad.claim(coinId, 1);
        assertEq(zamm.balanceOf(buyer2, coinId), 1);
    }

    /* ==================================================================
    34. buyExactCoins – insufficient ETH supplied reverts ───────────── */
    function testBuyExactCoinsInsufficientEthReverts() public {
        delete coins;
        delete prices;
        coins.push(4); // 0.25 ETH / coin
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        vm.deal(buyer1, 0.5 ether); // cost will be 0.75 ETH
        vm.prank(buyer1);
        vm.expectRevert(ZAMMLaunch.InvalidMsgVal.selector);
        pad.buyExactCoins{value: 0.5 ether}(coinId, 0, 3);
    }

    /* ==================================================================
    35. buyExactCoins – non-integral price reverts ──────────────────── */
    function testBuyExactCoinsNonIntegralReverts() public {
        delete coins;
        delete prices;
        coins.push(3); // 3 coins
        prices.push(uint96(2 ether)); // price per coin = 0.666… ETH

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        vm.deal(buyer1, 1 ether);
        vm.prank(buyer1);
        // 2 coins would cost 1.333… ETH (non-integral) → revert
        vm.expectRevert(ZAMMLaunch.InvalidMsgVal.selector);
        pad.buyExactCoins{value: 1 ether}(coinId, 0, 2);
    }

    /* ==================================================================
    36. buyExactCoins – request more shares than tranche reverts ─────── */
    function testBuyExactCoinsOverSubscriptionReverts() public {
        delete coins;
        delete prices;
        coins.push(4); // tranche size = 4
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        // 5 coins would exceed tranche; cost = 1.25 ETH
        vm.deal(buyer1, 2 ether);
        vm.prank(buyer1);
        vm.expectRevert(); // generic revert (ZAMM overflow)
        pad.buyExactCoins{value: 1.25 ether}(coinId, 0, 5);
    }

    /* ==================================================================
    37. buyExactCoins + legacy buy() inter-operability (Exact→Wei)────── */
    function testBuyExactThenWei() public {
        delete coins;
        delete prices;
        coins.push(4);
        prices.push(uint96(1 ether)); // 0.25 per coin
        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        /* Buyer-1 gets 3 coins via buyExactCoins (0.75 ETH) */
        vm.deal(buyer1, 1 ether);
        vm.prank(buyer1);
        pad.buyExactCoins{value: 0.75 ether}(coinId, 0, 3);

        /* Buyer-2 gets last coin via classic buy() (0.25 ETH) */
        vm.deal(buyer2, 0.25 ether);
        vm.prank(buyer2);
        pad.buy{value: 0.25 ether}(coinId, 0);

        /* Sale auto-finalised; both can claim */
        vm.prank(buyer1);
        pad.claim(coinId, 3);
        vm.prank(buyer2);
        pad.claim(coinId, 1);

        assertEq(zamm.balanceOf(buyer1, coinId), 3);
        assertEq(zamm.balanceOf(buyer2, coinId), 1);
    }

    /* ==================================================================
    38. buy() first, then buyExactCoins (Wei→Exact) inter-op test ───── */
    function testWeiThenBuyExactCoins() public {
        delete coins;
        delete prices;
        coins.push(4);
        prices.push(uint96(1 ether)); // 0.25 per coin
        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        /* Buyer-1 buys 1 coin via legacy buy() */
        vm.deal(buyer1, 0.25 ether);
        vm.prank(buyer1);
        pad.buy{value: 0.25 ether}(coinId, 0);

        /* Buyer-2 buys remaining 3 via buyExactCoins */
        vm.deal(buyer2, 1 ether);
        vm.prank(buyer2);
        pad.buyExactCoins{value: 0.9 ether}(coinId, 0, 3); // sends 0.9 (≥0.75) and gets refund

        /* Auto-finalised, claim balances */
        vm.prank(buyer1);
        pad.claim(coinId, 1);
        vm.prank(buyer2);
        pad.claim(coinId, 3);

        assertEq(zamm.balanceOf(buyer1, coinId), 1);
        assertEq(zamm.balanceOf(buyer2, coinId), 3);
    }

    /* ==================================================================
    39. trancheRemainingCoins mirrors remaining-wei logic ───────────── */
    function testTrancheRemainingCoins() public {
        /* tranche: 1 000 coins ↔ 2 ETH  →  price 0.002 ETH per coin     */
        delete coins;
        delete prices;
        coins.push(1_000);
        prices.push(uint96(2 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        /* initially: all 1 000 coins remain */
        assertEq(uint256(pad.trancheRemainingCoins(coinId, 0)), 1_000);

        /* Buyer-1 sends 1 ETH → receives 500 coins */
        vm.deal(buyer1, 1 ether);
        vm.prank(buyer1);
        pad.buy{value: 1 ether}(coinId, 0);

        /* 500 coins should remain */
        assertEq(uint256(pad.trancheRemainingCoins(coinId, 0)), 500);

        /* Buyer-2 sends the final 1 ETH → tranche filled, auto-finalise */
        vm.deal(buyer2, 1 ether);
        vm.prank(buyer2);
        pad.buy{value: 1 ether}(coinId, 0);

        /* after fill / finalise the helper returns 0 */
        assertEq(uint256(pad.trancheRemainingCoins(coinId, 0)), 0);

        /* invalid tranche index also returns 0 */
        assertEq(uint256(pad.trancheRemainingCoins(coinId, 1)), 0);
    }

    /* ==================================================================
    /* allow contracts in tests to receive ETH */
    receive() external payable {}
}
