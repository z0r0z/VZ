// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "@solady/test/utils/mocks/MockERC20.sol";
import {ZAMM} from "../src/ZAMM.sol";

contract ZAMMTimeLockTest is Test {
    // redeclare the Lock event so we can use emit in tests
    event Lock(address indexed sender, address indexed to, bytes32 indexed lockHash);

    ZAMM zamm;
    MockERC20 token;
    address recipient = address(0xBEEF);

    function setUp() public {
        // deploy ZAMM and a mock ERC20
        zamm = new ZAMM();
        token = new MockERC20("TKN", "TKN", 18);
        // fund and approve this test contract
        token.mint(address(this), 1_000e18);
        token.approve(address(zamm), type(uint256).max);
    }

    function testLockupAndUnlockEth() public {
        uint256 amount = 1 ether;
        uint256 unlockTime = block.timestamp + 1;

        // compute expected lockHash
        bytes32 lockHash = keccak256(abi.encode(address(0), recipient, 0, amount, unlockTime));

        // expect a Lock event from ZAMM
        vm.expectEmit(true, true, true, false, address(zamm));
        emit Lock(address(this), recipient, lockHash);

        // perform the lockup
        zamm.lockup{value: amount}(address(0), recipient, 0, amount, unlockTime);
        assertEq(zamm.lockups(lockHash), unlockTime);

        // too early → Pending()
        vm.expectRevert(ZAMM.Pending.selector);
        zamm.unlock(address(0), recipient, 0, amount, unlockTime);

        // warp to unlockTime and unlock
        vm.warp(unlockTime);
        uint256 beforeBal = recipient.balance;
        zamm.unlock(address(0), recipient, 0, amount, unlockTime);
        // mapping cleared and ETH delivered
        assertEq(zamm.lockups(lockHash), 0);
        assertEq(recipient.balance, beforeBal + amount);
    }

    function testLockupAndUnlockERC20() public {
        uint256 amount = 100e18;
        uint256 unlockTime = block.timestamp + 1;

        bytes32 lockHash = keccak256(abi.encode(address(token), recipient, 0, amount, unlockTime));

        vm.expectEmit(true, true, true, false, address(zamm));
        emit Lock(address(this), recipient, lockHash);

        // lock the ERC20
        zamm.lockup(address(token), recipient, 0, amount, unlockTime);
        assertEq(zamm.lockups(lockHash), unlockTime);
        assertEq(token.balanceOf(address(zamm)), amount);

        // too early → Pending()
        vm.expectRevert(ZAMM.Pending.selector);
        zamm.unlock(address(token), recipient, 0, amount, unlockTime);

        // warp & unlock
        vm.warp(unlockTime);
        zamm.unlock(address(token), recipient, 0, amount, unlockTime);
        assertEq(zamm.lockups(lockHash), 0);
        assertEq(token.balanceOf(recipient), amount);
    }

    function testLockupAndUnlockCoin() public {
        // mint a native ZAMM coin
        uint256 supply = 50;
        uint256 coinId = zamm.coin(address(this), supply, "uri");
        uint256 amount = 20;
        uint256 initBal = zamm.balanceOf(address(this), coinId);
        uint256 unlockTime = block.timestamp + 1;

        bytes32 lockHash =
            keccak256(abi.encode(address(zamm), recipient, coinId, amount, unlockTime));

        vm.expectEmit(true, true, true, false, address(zamm));
        emit Lock(address(this), recipient, lockHash);

        // lock the coin
        zamm.lockup(address(zamm), recipient, coinId, amount, unlockTime);
        assertEq(zamm.lockups(lockHash), unlockTime);
        assertEq(zamm.balanceOf(address(this), coinId), initBal - amount);

        // too early → Pending()
        vm.expectRevert(ZAMM.Pending.selector);
        zamm.unlock(address(zamm), recipient, coinId, amount, unlockTime);

        // warp & unlock
        vm.warp(unlockTime);
        zamm.unlock(address(zamm), recipient, coinId, amount, unlockTime);
        assertEq(zamm.lockups(lockHash), 0);
        assertEq(zamm.balanceOf(recipient, coinId), amount);
    }

    function testLockupAndUnlockLPShare() public {
        // prepare two ERC20s for liquidity
        MockERC20 A = new MockERC20("A", "A", 18);
        MockERC20 B = new MockERC20("B", "B", 18);
        A.mint(address(this), 1_000e18);
        B.mint(address(this), 1_000e18);
        A.approve(address(zamm), type(uint256).max);
        B.approve(address(zamm), type(uint256).max);

        // canonical ordering for ZAMM is by address value, so we sort A/B numerically
        (address t0, address t1) =
            address(A) < address(B) ? (address(A), address(B)) : (address(B), address(A));

        // set up a pool key (fee = 30 bps)
        ZAMM.PoolKey memory key =
            ZAMM.PoolKey({id0: 0, id1: 0, token0: t0, token1: t1, feeOrHook: 30});
        uint256 poolId = uint256(keccak256(abi.encode(key)));

        // seed the pool
        zamm.addLiquidity(
            key,
            100e18, // amount0
            100e18, // amount1
            0,
            0,
            address(this),
            block.timestamp + 1
        );

        // LP share = balanceOf(this, poolId)
        uint256 lpId = poolId;
        uint256 amount = zamm.balanceOf(address(this), lpId);
        uint256 unlockTime = block.timestamp + 1;

        bytes32 lockHash = keccak256(abi.encode(address(zamm), recipient, lpId, amount, unlockTime));

        vm.expectEmit(true, true, true, false, address(zamm));
        emit Lock(address(this), recipient, lockHash);

        // lock the LP share
        zamm.lockup(address(zamm), recipient, lpId, amount, unlockTime);
        assertEq(zamm.lockups(lockHash), unlockTime);
        assertEq(zamm.balanceOf(address(this), lpId), 0);

        // too early → Pending()
        vm.expectRevert(ZAMM.Pending.selector);
        zamm.unlock(address(zamm), recipient, lpId, amount, unlockTime);

        // warp & unlock
        vm.warp(unlockTime);
        zamm.unlock(address(zamm), recipient, lpId, amount, unlockTime);
        assertEq(zamm.lockups(lockHash), 0);
        assertEq(zamm.balanceOf(recipient, lpId), amount);
    }

    function testLockupTwiceReverts() public {
        uint256 amount = 1 ether;
        uint256 unlockTime = block.timestamp + 1;

        zamm.lockup{value: amount}(address(0), recipient, 0, amount, unlockTime);
        vm.expectRevert(ZAMM.Pending.selector);
        zamm.lockup{value: amount}(address(0), recipient, 0, amount, unlockTime);
    }

    function testUnlockNonexistentRevertsUnauthorized() public {
        uint256 amount = 1 ether;
        uint256 unlockTime = block.timestamp + 1;
        // no prior lock → Unauthorized()
        vm.expectRevert(ZAMM.Unauthorized.selector);
        zamm.unlock(address(0), recipient, 0, amount, unlockTime);
    }
}
