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
    1.  Manual finalise after partial sale ─────────────────────────── */
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
    3.  Early-finalise guard works ─────────────────────────────────── */
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
    4.  Idempotent finalise ────────────────────────────────────────── */
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
    13. Multi-tranche partial & auto-finalise ──────────────────────── */
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
    15. Finalize before deadline / after auto-finalise ─────────────── */
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

        /* buyer1 buys entire tranche → triggers auto-finalise */
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
    20. Finalise after partial sale leaves extra duplicates ────────── */
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
    24. Auto-finalise then further buy() must revert Finalized() ───── */
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

    /* allow contracts in tests to receive ETH */
    receive() external payable {}
}
