// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {ZAMM} from "../src/ZAMM.sol";
import {ZAMMLaunch} from "../src/ZAMMLaunch.sol";

contract ZAMMLaunchpadTest is Test {
    ZAMM internal zamm;
    ZAMMLaunch internal pad;

    uint96[] internal coins;
    uint96[] internal prices;

    address internal creator = address(this);
    address internal buyer1 = address(0xB0B1);
    address internal buyer2 = address(0xB0B2);

    function setUp() public {
        zamm = new ZAMM();
        pad = new ZAMMLaunch(address(zamm));

        vm.deal(creator, 100 ether);
        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);
    }

    /* pool-id helper */
    function _poolId(uint256 coinId) internal view returns (uint256) {
        return uint256(
            keccak256(abi.encode(uint256(0), coinId, address(0), address(zamm), uint256(30)))
        );
    }

    /* √ helper (integer Babylonian) */
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

    /* ------------------------------------------------------------- */
    /*                2-tranche sale, LP locked                      */
    /* ------------------------------------------------------------- */
    function testTwoTrancheManualFinalize() public {
        delete coins;
        delete prices;
        coins.push(600);
        prices.push(uint96(1 ether));
        coins.push(400);
        prices.push(uint96(2 ether));

        uint256 coinId = pad.launch(0, coins, prices, "uri", false, 0, true, 30 days);

        vm.prank(buyer1);
        pad.buy{value: 1 ether}(coinId, 0, 0); // first tranche

        // launchpad still has full 1 000 coins (burn/mint cycle)
        assertEq(zamm.balanceOf(address(pad), coinId), 1_000);

        vm.warp(block.timestamp + 8 days);
        vm.prank(buyer2);
        pad.finalize(coinId); // third-party finalise

        uint256 pid = _poolId(coinId);

        /* compute expected LP amount: √(ETH * coins) - 1 000 */
        uint256 lpMinted = _sqrt(1 ether * 1_000) - 1_000;

        // lock entry exists
        bytes32 lockHash = keccak256(abi.encode(address(zamm), creator, pid, lpMinted, 30 days));
        assertEq(zamm.lockups(lockHash), 30 days);

        // creator has 0 LP while locked
        assertEq(zamm.balanceOf(creator, pid), 0);

        // escrow cleared
        assertEq(pad.ethRaised(coinId), 0);
        assertEq(pad.contributions(coinId, buyer1), 1 ether);
    }

    /* ================================================================== */
    /* ❶ Partial fill, explicit size, then remainder, then finalise       */
    /* ================================================================== */
    function testPartialFillExplicitSize() public {
        delete coins;
        delete prices;
        coins.push(1_000);
        prices.push(uint96(2 ether));

        uint256 coinId = pad.launch(0, coins, prices, "u", false, 0, false, 0);

        // buyer1 purchases exactly 1 ETH worth
        vm.prank(buyer1);
        pad.buy{value: 1 ether}(coinId, 0, 1 ether);

        // escrow = 1 ETH so far
        assertEq(pad.ethRaised(coinId), 1 ether);

        // buyer2 takes remainder
        vm.prank(buyer2);
        pad.buy{value: 1 ether}(coinId, 0, 0);

        // warp > 1 w and creator finalises
        vm.warp(block.timestamp + 8 days);
        pad.finalize(coinId);

        // escrow zeroed and total contributions = 2 ETH
        assertEq(pad.ethRaised(coinId), 0);
        assertEq(pad.contributions(coinId, buyer1) + pad.contributions(coinId, buyer2), 2 ether);
    }

    /* =============================================================== */
    /*        ❷  Early finalisation must revert (still in window)      */
    /* =============================================================== */
    function testEarlyFinalizeReverts() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, coins, prices, "u", false, 0, false, 0);

        // creator tries to finalise immediately
        vm.expectRevert("sale active");
        pad.finalize(coinId);
    }

    error Finalized();

    /* ====================================================================== */
    /* ❷  finalize() idempotency – 2nd call MUST revert with "done"           */
    /* ====================================================================== */
    function testFinalizeTwiceNoOp() public {
        delete coins;
        delete prices;
        coins.push(100);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(0, coins, prices, "u", false, 0, false, 0);

        vm.prank(buyer1);
        pad.buy{value: 1 ether}(coinId, 0, 0); // sale still inside window

        // early finalise reverts with "sale active"
        vm.expectRevert("sale active");
        pad.finalize(coinId);

        // after window: first finalise succeeds
        vm.warp(block.timestamp + 8 days);
        pad.finalize(coinId);
        assertEq(pad.ethRaised(coinId), 0); // escrow cleared

        // second call MUST revert with "Finalized()"
        vm.expectRevert(Finalized.selector);
        pad.finalize(coinId);
    }

    /* ====================================================================== */
    /* ❸  Unlocked-LP flow: single buyer, manual finalise, LP sent to creator */
    /* ====================================================================== */
    function testUnlockedLpFlow() public {
        delete coins;
        delete prices;
        coins.push(500);
        prices.push(uint96(1 ether));

        uint256 coinId = pad.launch(
            0,
            coins,
            prices,
            "u",
            false,
            0,
            false,
            0 // LP is **not** locked
        );

        // buyer fully fills tranche
        vm.prank(buyer1);
        pad.buy{value: 1 ether}(coinId, 0, 0);

        // warp past window and finalise
        vm.warp(block.timestamp + 8 days);
        pad.finalize(coinId);

        uint256 pid = _poolId(coinId);

        // LP tokens are now sitting directly in creator's wallet
        assertGt(zamm.balanceOf(creator, pid), 0);

        // there is NO lock entry
        bytes32 dummy = keccak256(
            abi.encode(address(zamm), creator, pid, zamm.balanceOf(creator, pid), uint256(0))
        );
        assertEq(zamm.lockups(dummy), 0);
    }
}
