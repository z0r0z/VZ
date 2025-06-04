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

    receive() external payable {}
}
