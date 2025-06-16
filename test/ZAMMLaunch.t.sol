// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {ZAMM} from "../src/ZAMM.sol";
import {ZAMMLaunch} from "../periphery/ZAMMLaunch.sol";

contract ZAMMLaunchpadTest is Test {
    /* ── deployed artefacts ── */
    ZAMM constant zamm = ZAMM(payable(0x000000000000040470635EB91b7CE4D132D616eD));
    ZAMMLaunch pad;

    /* scratch arrays reused every test */
    uint96[] coins;
    uint96[] prices;

    address creator = address(this);
    address buyer1 = address(0xB0B1);
    address buyer2 = address(0xB0B2);

    /* ------------------------------------------------ */
    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("main"));
        pad = new ZAMMLaunch();

        vm.deal(creator, 100 ether);
        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);

        coins.push(600);
        coins.push(400);
        coins.push(200);

        prices.push(600);
        prices.push(400);
        prices.push(200);
    }

    /* helpers ------------------------------------------------------------ */

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

    // GAS ESTIMATION

    function testThreeTrancheSaleGasCost() public {
        pad.launch(0, 0, "uri", coins, prices);
    }

    /* 1 ───────────────────────────────────────────────────────────────── */
    function testTwoTrancheManualFinalize() public {
        /* tranche data – populate the reusable storage arrays */
        delete coins;
        delete prices;
        coins.push(600);
        coins.push(400);
        prices.push(uint96(1 ether));
        prices.push(uint96(2 ether));

        /* launch (no creator allocation) */
        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        /* buyer-1 fills first tranche (600 coins ↔ 1 ETH) */
        vm.prank(buyer1);
        pad.buy{value: 1 ether}(coinId, 0);

        /* 2 000 coins minted (saleSupply×2). 600 sold → 1 400 remain pre-finalize */
        assertEq(zamm.balanceOf(address(pad), coinId), 1_400);

        /* warp >1 week, buyer-2 finalises */
        vm.warp(block.timestamp + 8 days);
        vm.prank(buyer2);
        pad.finalize(coinId);

        /* LP tokens: √(ETH × sold) − 1 000 (min-liquidity) */
        uint256 expectedLp = _sqrt(1 ether * 600) - 1_000;
        uint256 pid = _poolId(coinId);
        assertEq(zamm.balanceOf(address(pad), pid), expectedLp);

        /* after depositing 600 coins into the pool, 800 duplicate coins remain */
        assertEq(zamm.balanceOf(address(pad), coinId), 800);

        /* finalise is idempotent */
        vm.expectRevert(ZAMMLaunch.Finalized.selector);
        pad.finalize(coinId);
    }

    /* 2 ───────────────── Partial-fill then remainder ─────────────────── */
    function testPartialFillExplicitSize() public {
        delete coins;
        delete prices;
        coins.push(1_000);
        prices.push(uint96(2 ether));

        uint256 id = pad.launch(0, 0, "uri", coins, prices);

        vm.prank(buyer1);
        pad.buy{value: 1 ether}(id, 0); // half the tranche

        (,,, uint128 raisedHalf,) = pad.sales(id);
        assertEq(raisedHalf, 1 ether);

        vm.prank(buyer2);
        pad.buy{value: 1 ether}(id, 0); // take remainder → auto-finalise

        (,,, uint128 raisedFin,) = pad.sales(id);
        assertEq(raisedFin, 0); // escrow swept to LP

        // further finalise must revert with Finalized()
        vm.expectRevert(ZAMMLaunch.Finalized.selector);
        pad.finalize(id);
    }

    /* 3 ───────────────── early-finalise guard ────────────────────────── */
    function testEarlyFinalizeReverts() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 id = pad.launch(0, 0, "u", coins, prices);

        vm.expectRevert(ZAMMLaunch.Pending.selector);
        pad.finalize(id);
    }

    /* 4 ───────────────── idempotent finalise ─────────────────────────── */
    function testFinalizeTwiceNoOp() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 id = pad.launch(0, 0, "u", coins, prices);

        // still inside window → Pending
        vm.expectRevert(ZAMMLaunch.Pending.selector);
        pad.finalize(id);

        vm.prank(buyer1);
        pad.buy{value: 1 ether}(id, 0); // auto-finalise

        vm.expectRevert(ZAMMLaunch.Finalized.selector);
        pad.finalize(id); // idempotent revert
    }

    /* 5 ───────────────── unlocked-LP path ────────────────────────────── */
    function testUnlockedLpFlow() public {
        delete coins;
        delete prices;
        coins.push(500);
        prices.push(uint96(1 ether));

        uint256 id = pad.launch(0, 0, "u", coins, prices);

        vm.prank(buyer1);
        pad.buy{value: 1 ether}(id, 0); // fills & auto-finalises

        uint256 pid = _poolId(id);
        assertGt(zamm.balanceOf(address(pad), pid), 0); // LP minted to pad

        vm.expectRevert(ZAMMLaunch.Finalized.selector);
        pad.finalize(id);
    }

    /* 6 ───────────────── trancheRemainingWei helper ───────────────────── */
    function testTrancheRemainingWei() public {
        /* single-tranche sale: 1 000 coins ↔ 2 ETH */
        delete coins;
        delete prices;
        coins.push(1_000);
        prices.push(uint96(2 ether));

        uint256 coinId = pad.launch(0, 0, "u", coins, prices);

        /* 0.  untouched → full 2 ETH still needed */
        assertEq(uint256(pad.trancheRemainingWei(coinId, 0)), 2 ether);

        /* 1. buyer-1 takes exactly 1 ETH worth (explicit fillPart) */
        vm.prank(buyer1);
        pad.buy{value: 1 ether}(coinId, 0);
        assertEq(uint256(pad.trancheRemainingWei(coinId, 0)), 1 ether);

        /* 2. buyer-2 takes the remainder (fillPart = 0) → auto-finalise */
        vm.prank(buyer2);
        pad.buy{value: 1 ether}(coinId, 0);
        assertEq(uint256(pad.trancheRemainingWei(coinId, 0)), 0);

        /* 3. sanity: wrong idx / finalised sale both return 0 */
        assertEq(uint256(pad.trancheRemainingWei(coinId, 1)), 0);
    }

    /* 7 ───────────────────────────────────────────────────────────────── */
    function testCannotDirectFillOrder() public {
        // single‐tranche sale: 100 tokens ↔ 1 ETH
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        // retrieve deadline for tranche 0 (only tranche), via public getter
        (, uint96 deadlineLast,,,) = pad.sales(coinId);

        // Attempt to call ZAMM.fillOrder directly (bypass pad.buy)
        vm.prank(buyer1);
        vm.expectRevert();
        zamm.fillOrder{value: 1 ether}(
            address(pad), // maker = pad
            address(zamm), // tokenIn = ZAMM contract
            coinId,
            coins[0], // amtIn = 100 tokens
            address(0), // tokenOut = ETH
            0,
            prices[0], // amtOut = 1 ETH
            uint56(deadlineLast),
            true, // partialFill = true
            uint96(1 ether) // fillPart = 1 ETH
        );
    }

    /* 8 ───────────────────────────────────────────────────────────────── */
    function testBuyAfterFinalizeReverts() public {
        delete coins;
        delete prices;
        coins.push(50);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "u", coins, prices);

        // Warp past the last tranche deadline so buy() will hit ZAMM’s Expired() check
        vm.warp(block.timestamp + 8 days);

        vm.prank(buyer1);
        vm.expectRevert(ZAMM.Expired.selector);
        pad.buy{value: 1 ether}(coinId, 0);
    }

    /* 9 ───────────────────────────────────────────────────────────────── */
    function testCoinWithPoolRevertsOnZeroEth() public {
        // Attempt coinWithPool with zero ETH → should revert deep inside ZAMM
        vm.expectRevert();
        pad.coinWithPool(100, 0, 0, "uri");
    }

    /* 10 ───────────────────────────────────────────────────────────────── */
    function testCoinWithPoolSuccessMintsLp() public {
        // Fund this test contract as “creator”
        vm.deal(address(this), 1 ether);

        // Call coinWithPool with 100 tokens and 1 ETH
        (uint256 coinId, uint256 lpMinted) = pad.coinWithPool{value: 1 ether}(
            100, // poolSupply
            0, // creatorSupply
            0, // creatorUnlock
            "uri" // uri
        );

        // Compute the expected pool ID and LP amount
        uint256 pid = _poolId(coinId);
        uint256 expectedLp = _sqrt(1 ether * 100) - 1_000;

        // The LP tokens should have been minted to this contract (the caller)
        assertEq(zamm.balanceOf(address(this), pid), expectedLp);
        assertEq(lpMinted, expectedLp);

        // The launchpad contract itself holds zero of the new coin (all 100 were used)
        assertEq(zamm.balanceOf(address(pad), coinId), 0);
    }

    /* 11 ───────────────── Zero‐Sale Finalize Reverts ───────────────────── */
    function testZeroSaleCannotFinalize() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        // No one calls buy(). Warp past deadline.
        vm.warp(block.timestamp + 8 days);

        // Attempt to finalize with zero ETH raised → should revert with NoRaise()
        vm.expectRevert(ZAMMLaunch.NoRaise.selector);
        pad.finalize(coinId);
    }

    /* 12 ───────────────── Unauthorized Direct ETH Transfer Reverts ────────── */
    function testUnauthorizedDirectETHReverts() public {
        // Fund buyer1
        vm.deal(buyer1, 1 ether);

        // Attempt to send ETH directly to pad (not via ZAMM)
        vm.prank(buyer1);
        (bool success,) = address(pad).call{value: 1 ether}("");
        assertFalse(success, "Direct ETH transfer should revert Unauthorized()");
    }

    /* 13 ───────────────── Partial‐Fill Across Multiple Tranches ───────────── */
    function testMultiTranchePartialAndFinalize() public {
        delete coins;
        delete prices;
        // Tranche 0: 200 tokens ↔ 1 ETH, Tranche 1: 300 tokens ↔ 2 ETH
        coins.push(200);
        coins.push(300);
        prices.push(uint96(1 ether));
        prices.push(uint96(2 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        // Buyer1 takes half of tranche 0: sends 0.5 ETH → receives 100 tokens
        vm.prank(buyer1);
        pad.buy{value: 0.5 ether}(coinId, 0);

        // After 100 sold, pad should hold 900 of 1000 minted
        assertEq(zamm.balanceOf(address(pad), coinId), 900);

        // trancheRemainingWei for tranche 0 should be 0.5 ETH left
        assertEq(uint256(pad.trancheRemainingWei(coinId, 0)), 0.5 ether);

        // Buyer2 takes the remainder of tranche 0: sends 0.5 ETH → receives 100 tokens
        vm.prank(buyer2);
        pad.buy{value: 0.5 ether}(coinId, 0);

        // Now the order for tranche 0 has been fully filled and deleted, so remainingWei = 0
        assertEq(uint256(pad.trancheRemainingWei(coinId, 0)), 0);

        // Buyer1 then takes all of tranche 1: sends 2 ETH → receives 300 tokens, triggers auto‐finalize
        vm.prank(buyer1);
        pad.buy{value: 2 ether}(coinId, 1);

        // Compute expected LP: sqrt((0.5 + 0.5 + 2) ETH * 500 tokens) - 1000
        uint256 totalRaised = 3 ether;
        uint256 soldTokens = 500;
        uint256 expectedLp = _sqrt(totalRaised * soldTokens) - 1_000;
        uint256 pid = _poolId(coinId);
        assertEq(zamm.balanceOf(address(pad), pid), expectedLp);

        // After seeding 500 tokens into the pool, pad should hold 0 leftover (500 → pool)
        assertEq(zamm.balanceOf(address(pad), coinId), 0);

        // Subsequent finalize should revert as already finalized
        vm.expectRevert(ZAMMLaunch.Finalized.selector);
        pad.finalize(coinId);
    }

    /* 14 ───────────────── Insufficient ETH in buy() Reverts ───────────────── */
    function testBuyWithTooLittleEthReverts() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        // Send only 0.009 ETH → fillOrder will revert with BadSize()
        vm.prank(buyer1);
        vm.expectRevert(ZAMM.BadSize.selector);
        pad.buy{value: 0.009 ether}(coinId, 0);
    }

    /* 15 ───────────────── Finalize With Pending Deadline Reverts ──────────── */
    function testFinalizeBeforeDeadlineReverts() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        // Before any sale, deadline hasn't passed → should revert Pending()
        vm.expectRevert(ZAMMLaunch.Pending.selector);
        pad.finalize(coinId);

        // Do a buy that sells all tokens and auto‐finalizes
        vm.prank(buyer1);
        pad.buy{value: 1 ether}(coinId, 0);

        // Now calling finalize should revert Finalized()
        vm.expectRevert(ZAMMLaunch.Finalized.selector);
        pad.finalize(coinId);
    }

    /* 16 ───────────────────────────────────────────────────────────────── */
    function testLaunchWithCreatorImmediateAllocation() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        // Launch with creatorSupply = 50, no lockup
        uint256 coinId = pad.launch(50, 0, "uri", coins, prices);

        // Total minted = creatorSupply + 2×saleSupply = 50 + (2×100) = 250
        // Creator (this contract) should hold 50
        assertEq(zamm.balanceOf(address(this), coinId), 50);
        // Launchpad should hold 200 (the 2×100)
        assertEq(zamm.balanceOf(address(pad), coinId), 200);
    }

    /* 17 ───────────────────────────────────────────────────────────────── */
    function testLaunchWithCreatorLockupAndUnlock() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        // Set creatorUnlock to “tomorrow”
        uint256 unlockTime = block.timestamp + 1 days;
        uint256 coinId = pad.launch(50, unlockTime, "uri", coins, prices);

        // Immediately after launch, creator (this) has 0
        assertEq(zamm.balanceOf(address(this), coinId), 0);

        // Warp to after unlockTime
        vm.warp(unlockTime + 1);

        // Call ZAMM.unlock(token=address(zamm), to=this, id=coinId, amount=50, unlockTime)
        zamm.unlock(address(zamm), address(this), coinId, 50, unlockTime);

        // Now creator sees 50 tokens
        assertEq(zamm.balanceOf(address(this), coinId), 50);
    }

    /* 18 ───────────────────────────────────────────────────────────────── */
    function testBuyInvalidTrancheIndexReverts() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        // Only trancheIdx=0 is valid; trancheIdx=1 should revert BadIndex()
        vm.prank(buyer1);
        vm.expectRevert(ZAMMLaunch.BadIndex.selector);
        pad.buy{value: 1 ether}(coinId, 1);
    }

    /* 19 ───────────────────────────────────────────────────────────────── */
    function testTrancheRemainingWeiInvalidSaleOrIndex() public {
        // Nonexistent sale (coinId=999): should return 0
        assertEq(pad.trancheRemainingWei(999, 0), 0);

        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));
        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        // Invalid tranche index (only index 0 exists): should return 0
        assertEq(pad.trancheRemainingWei(coinId, 1), 0);
    }

    /* 20 ───────────────────────────────────────────────────────────────── */
    function testPartialSaleFinalizeLeavesLockedTokens() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        // Buyer1 buys half the tranche: sends 0.5 ETH → receives 50 tokens
        vm.prank(buyer1);
        pad.buy{value: 0.5 ether}(coinId, 0);

        // After that purchase, Launchpad holds 200 − 50 = 150 tokens (200 = 2×100)
        assertEq(zamm.balanceOf(address(pad), coinId), 150);

        // Warp past deadline
        vm.warp(block.timestamp + 8 days);

        // Finalize: seeds pool with exactly the 50 sold tokens, leaving 100 locked in Launchpad
        pad.finalize(coinId);
        assertEq(zamm.balanceOf(address(pad), coinId), 100);
    }

    /* 21 ───────────────────────────────────────────────────────────────── */
    function testCoinWithPoolWithCreatorSupply() public {
        // Give this test contract 1 ETH
        vm.deal(address(this), 1 ether);

        // Call coinWithPool(poolSupply=100, creatorSupply=50, creatorUnlock=0)
        (uint256 coinId, uint256 lpMinted) = pad.coinWithPool{value: 1 ether}(
            100, // poolSupply
            50, // creatorSupply
            0, // creatorUnlock
            "uri" // uri
        );

        // After mint:
        // • total minted = 100 (pool) + 50 (creator) = 150 tokens
        // • creator (this) immediately gets 50
        assertEq(zamm.balanceOf(address(this), coinId), 50);

        // • Launchpad held 100 tokens, but then seeded all 100 into the pool → Launchpad ends with 0
        assertEq(zamm.balanceOf(address(pad), coinId), 0);

        // LP minted should match sqrt(1 ETH × 100 tokens) − 1 000
        uint256 pid = _poolId(coinId);
        uint256 expectedLp = _sqrt(1 ether * 100) - 1_000;
        assertEq(lpMinted, expectedLp);
        assertEq(zamm.balanceOf(address(this), pid), expectedLp);
    }

    /* 22 ───────────────────────────────────────────────────────────────── */
    function testBuyWithZeroEthReverts() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        // Attempt to buy with 0 ETH → should revert (ZAMM.BadSize())
        vm.prank(buyer1);
        vm.expectRevert(ZAMM.InvalidMsgVal.selector);
        pad.buy{value: 0}(coinId, 0);
    }

    /* 23 ───────────────────────────────────────────────────────────────── */
    function testLaunchInvalidArrayLengthsReverts() public {
        // coins length = 2, prices length = 1 → should revert InvalidArray()
        delete coins;
        delete prices;
        coins.push(100);
        coins.push(50);
        prices.push(uint96(1 ether));

        vm.expectRevert(ZAMMLaunch.InvalidArray.selector);
        pad.launch(0, 0, "uri", coins, prices);
    }

    /* 24 ───────────────────────────────────────────────────────────────── */
    function testBuyAfterImmediateSelloutButBeforeDeadlineReverts() public {
        delete coins;
        delete prices;
        // single‐tranche: 100 tokens ↔ 1 ETH
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        // Buyer1 drains the entire tranche in one call (1 ETH → 100 tokens)
        vm.prank(buyer1);
        pad.buy{value: 1 ether}(coinId, 0);

        // Immediately after that buy, the sale has already auto-finalized,
        // even though we are still within SALE_DURATION.
        // Thus, any further buy attempt must revert with Finalized(), not Expired().
        vm.prank(buyer2);
        vm.expectRevert(ZAMMLaunch.Finalized.selector);
        pad.buy{value: 1 ether}(coinId, 0);
    }

    /* 25 ───────────────────────────────────────────────────────────────── */
    function testFlooringRoundingBehavior() public {
        delete coins;
        delete prices;
        // single‐tranche: 3 tokens ↔ 2 ETH total
        coins.push(3);
        prices.push(uint96(2 ether));

        uint256 coinId = pad.launch(0, 0, "uri", coins, prices);

        // Buyer1 sends 1 ETH (half the price).  coinsOut = floor(3 * 1 / 2) = 1
        vm.prank(buyer1);
        pad.buy{value: 1 ether}(coinId, 0);

        // Buyer1 should only receive 1 token (not 1.5). Then pad.coinsSold = 1.
        assertEq(zamm.balanceOf(buyer1, coinId), 1);

        // After that purchase, launchpad holds 6 minted − 1 sold = 5 tokens
        assertEq(zamm.balanceOf(address(pad), coinId), 5);

        // trancheRemainingWei should be 2 ETH − 1 ETH = 1 ETH
        assertEq(uint256(pad.trancheRemainingWei(coinId, 0)), 1 ether);

        // Buyer2 sends 1 ETH (the remainder).  coinsOut = floor(3 * 1 / 2) = 1 again
        vm.prank(buyer2);
        pad.buy{value: 1 ether}(coinId, 0);

        // After Buyer2, launchpad holds 5 − 1 = 4 tokens
        assertEq(zamm.balanceOf(address(pad), coinId), 4);
        // Buyer2 got exactly 1 token
        assertEq(zamm.balanceOf(buyer2, coinId), 1);

        // Now the tranche is fully sold, so trancheRemainingWei() == 0
        assertEq(uint256(pad.trancheRemainingWei(coinId, 0)), 0);

        // Warp past deadline and finalize: it will seed pool with coinsSold = 2 tokens,
        // consuming 2 ETH from escrow and 2 tokens from launchpad.
        vm.warp(block.timestamp + 8 days);
        pad.finalize(coinId);

        // At finalize, pool sees (2 ETH, 2 tokens) → LP minted = sqrt(2*2)−1_000 = 2−1_000
        uint256 pid = _poolId(coinId);
        uint256 expectedLp = _sqrt(2 ether * 2) - 1_000;
        assertEq(zamm.balanceOf(address(pad), pid), expectedLp);

        // After seeding 2 tokens, launchpad’s leftover should be 4 − 2 = 2
        assertEq(zamm.balanceOf(address(pad), coinId), 2);
    }

    receive() external payable {}
}
