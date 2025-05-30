// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "@solady/test/utils/mocks/MockERC20.sol";
import "@solady/test/utils/mocks/MockERC721.sol";
import {ZAMM} from "../src/ZAMM.sol";

contract ZAMMOrderbookTest is Test {
    ZAMM zamm;
    MockERC20 A;
    MockERC20 B;
    MockERC721 NFT;
    address taker = makeAddr("taker");
    address unauthorized = makeAddr("unauth");

    function setUp() public {
        // deploy ZAMM and tokens
        zamm = new ZAMM();
        A = new MockERC20("A", "A", 18);
        B = new MockERC20("B", "B", 18);
        NFT = new MockERC721();

        // fund & approve maker (this)
        A.mint(address(this), 1_000e18);
        B.mint(address(this), 1_000e18);
        A.approve(address(zamm), type(uint256).max);
        B.approve(address(zamm), type(uint256).max);
        vm.deal(address(this), 5 ether);

        // mint NFT
        NFT.mint(address(this), 123);

        // fund & approve taker
        vm.startPrank(taker);
        A.mint(taker, 1_000e18);
        B.mint(taker, 1_000e18);
        A.approve(address(zamm), type(uint256).max);
        B.approve(address(zamm), type(uint256).max);
        vm.deal(taker, 5 ether);
        vm.stopPrank();
    }

    function testMakeOrderERC20() public {
        uint96 amtIn = 10e18;
        uint96 amtOut = 5e18;
        uint56 dl = uint56(block.timestamp + 1);

        // maker creates order
        bytes32 h = zamm.makeOrder(address(A), 0, amtIn, address(B), 0, amtOut, dl, false);

        // read back via public getter (returns tuple)
        (bool pf, uint56 storedDl, uint96 inDone, uint96 outDone) = zamm.orders(h);
        assertFalse(pf, "partialFill should be false");
        assertEq(storedDl, dl, "deadline stored");
        assertEq(inDone, 0, "inDone starts at 0");
        assertEq(outDone, 0, "outDone starts at 0");
    }

    function testFillOrderFullERC20() public {
        uint96 amtIn = 10e18;
        uint96 amtOut = 5e18;
        uint56 dl = uint56(block.timestamp + 1);

        // make
        bytes32 h = zamm.makeOrder(address(A), 0, amtIn, address(B), 0, amtOut, dl, false);

        // snapshot balances
        uint256 mA = A.balanceOf(address(this));
        uint256 mB = B.balanceOf(address(this));
        uint256 tA = A.balanceOf(taker);
        uint256 tB = B.balanceOf(taker);

        // taker fills
        vm.prank(taker);
        zamm.fillOrder(address(this), address(A), 0, amtIn, address(B), 0, amtOut, dl, false, 0);

        // order removed
        (, uint56 postDl,,) = zamm.orders(h);
        assertEq(postDl, 0, "order should be deleted");

        // balances updated
        assertEq(A.balanceOf(address(this)), mA - amtIn);
        assertEq(B.balanceOf(address(this)), mB + amtOut);
        assertEq(A.balanceOf(taker), tA + amtIn);
        assertEq(B.balanceOf(taker), tB - amtOut);
    }

    function testFillOrderPartialERC20() public {
        uint96 amtIn = 10e18;
        uint96 amtOut = 5e18;
        uint56 dl = uint56(block.timestamp + 1);

        // make partial
        bytes32 h = zamm.makeOrder(address(A), 0, amtIn, address(B), 0, amtOut, dl, true);

        // first partial fill of 2 tokens out
        vm.prank(taker);
        zamm.fillOrder(address(this), address(A), 0, amtIn, address(B), 0, amtOut, dl, true, 2e18);

        // check inDone/outDone updated
        (bool pf1,, uint96 inDone1, uint96 outDone1) = zamm.orders(h);
        assertTrue(pf1, "partialFill flag");
        assertEq(outDone1, 2e18, "outDone updated");
        assertEq(inDone1, uint96((uint256(amtIn) * 2e18) / amtOut), "inDone scaled");

        // second fill remainder (fillPart = 0)
        vm.prank(taker);
        zamm.fillOrder(address(this), address(A), 0, amtIn, address(B), 0, amtOut, dl, true, 0);

        // order removed
        (, uint56 postDl,,) = zamm.orders(h);
        assertEq(postDl, 0, "order should be deleted after full fill");
    }

    function testFillOrderUnauthorized() public {
        vm.prank(taker);
        vm.expectRevert(ZAMM.Unauthorized.selector);
        zamm.fillOrder(
            address(this),
            address(A),
            0,
            1e18,
            address(B),
            0,
            1e18,
            uint56(block.timestamp + 1),
            false,
            0
        );
    }

    function testFillOrderExpired() public {
        uint96 amtIn = 1e18;
        uint96 amtOut = 1e18;
        uint56 dl = uint56(block.timestamp + 1);

        zamm.makeOrder(address(A), 0, amtIn, address(B), 0, amtOut, dl, false);

        vm.warp(dl + 1);
        vm.prank(taker);
        vm.expectRevert(ZAMM.Expired.selector);
        zamm.fillOrder(address(this), address(A), 0, amtIn, address(B), 0, amtOut, dl, false, 0);
    }

    function testCancelOrderERC20() public {
        uint96 amtIn = 1e18;
        uint96 amtOut = 1e18;
        uint56 dl = uint56(block.timestamp + 1);

        bytes32 h = zamm.makeOrder(address(A), 0, amtIn, address(B), 0, amtOut, dl, false);

        // cancel by maker
        zamm.cancelOrder(address(A), 0, amtIn, address(B), 0, amtOut, dl, false);

        (, uint56 postDl,,) = zamm.orders(h);
        assertEq(postDl, 0, "order deleted on cancel");
    }

    function testCancelOrderUnauthorized() public {
        uint56 dl = uint56(block.timestamp + 1);
        vm.prank(taker);
        vm.expectRevert(ZAMM.Unauthorized.selector);
        zamm.cancelOrder(address(A), 0, 1e18, address(B), 0, 1e18, dl, false);
    }

    function testMakeAndCancelPartialOrderRefundsEth() public {
        // ETH-based partial order
        uint56 dl = uint56(block.timestamp + 1);
        uint96 amt = 2 ether;

        zamm.makeOrder{value: amt}(address(0), 0, amt, address(A), 0, 1e18, dl, true);

        uint256 before = address(this).balance;
        zamm.cancelOrder(address(0), 0, amt, address(A), 0, 1e18, dl, true);
        assertEq(address(this).balance, before + amt, "ETH refunded on cancel");
    }

    function testOrderWithLPShare() public {
        // set up pool for LP
        A = new MockERC20("A", "A", 18);
        B = new MockERC20("B", "B", 18);
        A.mint(address(this), 100e18);
        B.mint(address(this), 100e18);
        A.approve(address(zamm), type(uint256).max);
        B.approve(address(zamm), type(uint256).max);

        // canonical ordering
        (address t0, address t1) =
            address(A) < address(B) ? (address(A), address(B)) : (address(B), address(A));
        ZAMM.PoolKey memory key =
            ZAMM.PoolKey({id0: 0, id1: 0, token0: t0, token1: t1, feeOrHook: 30});

        zamm.addLiquidity(key, 100e18, 100e18, 0, 0, address(this), block.timestamp + 1);

        uint256 lpId = uint256(keccak256(abi.encode(key)));
        uint96 amtOut = 10e18;
        uint96 amtIn = uint96(zamm.balanceOf(address(this), lpId));
        uint56 dl = uint56(block.timestamp + 1);

        // make order selling LP shares for A
        zamm.makeOrder(address(zamm), lpId, amtIn, address(A), 0, amtOut, dl, false);

        // fill by taker
        uint256 preA = A.balanceOf(address(this));

        A.mint(taker, 100e18);
        vm.prank(taker);
        A.approve(address(zamm), type(uint256).max);
        vm.prank(taker);
        zamm.fillOrder(
            address(this), address(zamm), lpId, amtIn, address(A), 0, amtOut, dl, false, 0
        );

        // LP burned, A received
        assertEq(zamm.balanceOf(address(this), lpId), 0);
        assertEq(A.balanceOf(address(this)), preA + amtOut);
    }

    function testSellERC721ForERC20() public {
        NFT.setApprovalForAll(address(zamm), true);

        // 2) maker posts an order: sell NFT#123 for 50 A
        uint96 nftId = 123;
        uint96 wantAmt = 50e18;
        uint56 deadline = uint56(block.timestamp + 1);

        bytes32 h = zamm.makeOrder(
            address(NFT), // tokenIn = the ERC-721 contract
            0, // idIn = 0 ⇒ triggers ERC-721 path
            nftId, // amtIn = tokenId
            address(A), // tokenOut = ERC-20
            0,
            wantAmt,
            deadline,
            false // no partial fills
        );

        // 3) taker fills the order
        uint256 makerBeforeA = A.balanceOf(address(this));

        A.mint(taker, 100e18);
        vm.prank(taker);
        A.approve(address(zamm), type(uint256).max);
        vm.prank(taker);
        zamm.fillOrder(
            address(this), // maker
            address(NFT),
            0,
            nftId,
            address(A),
            0,
            wantAmt,
            deadline,
            false,
            0
        );

        // 4) assert: maker got the A, taker got the NFT, order cleared
        assertEq(A.balanceOf(address(this)), makerBeforeA + wantAmt);
        assertEq(NFT.ownerOf(nftId), taker);

        (, uint56 postDl,,) = zamm.orders(h);
        assertEq(postDl, 0, "order should be deleted");
    }

    /// @dev You can’t make the same order twice
    function testMakeDuplicateReverts() public {
        uint96 inAmt = 1e18;
        uint96 outAmt = 1e18;
        uint56 dl = uint56(block.timestamp + 1);

        zamm.makeOrder(address(A), 0, inAmt, address(B), 0, outAmt, dl, false);
        vm.expectRevert(ZAMM.Pending.selector);
        zamm.makeOrder(address(A), 0, inAmt, address(B), 0, outAmt, dl, false);
    }

    /// @dev Non-partial fills must use fillPart == 0 or == amtOut
    function testFillNonPartialWrongFillPartReverts() public {
        uint96 inAmt = 5e18;
        uint96 outAmt = 2e18;
        uint56 dl = uint56(block.timestamp + 1);

        bytes32 h = zamm.makeOrder(address(A), 0, inAmt, address(B), 0, outAmt, dl, false);
        vm.prank(taker);
        vm.expectRevert(ZAMM.BadSize.selector);
        zamm.fillOrder(
            address(this),
            address(A),
            0,
            inAmt,
            address(B),
            0,
            outAmt,
            dl,
            false,
            1e18 // neither 0 nor outAmt
        );
    }

    /// @dev Partial‐fill sliceOut > amtOut should revert Overflow()
    function testPartialFillOverflowReverts() public {
        uint96 inAmt = 4e18;
        uint96 outAmt = 2e18;
        uint56 dl = uint56(block.timestamp + 1);

        bytes32 h = zamm.makeOrder(address(A), 0, inAmt, address(B), 0, outAmt, dl, true);
        vm.prank(taker);
        vm.expectRevert(ZAMM.Overflow.selector);
        zamm.fillOrder(
            address(this),
            address(A),
            0,
            inAmt,
            address(B),
            0,
            outAmt,
            dl,
            true,
            3e18 // sliceOut > outAmt
        );
    }

    /// @dev Cancelling a partial ETH order refunds only the un-filled remainder
    function testPartialCancelRefundsRemainingEth() public {
        uint96 inAmt = 4 ether;
        uint96 outAmt = 2 ether;
        uint56 dl = uint56(block.timestamp + 1);
        // make partial ETH order
        zamm.makeOrder{value: inAmt}(address(0), 0, inAmt, address(A), 0, outAmt, dl, true);
        // taker takes 1 out => inDone = (4 * 1) / 2 = 2
        vm.prank(taker);
        zamm.fillOrder(
            address(this), address(0), 0, inAmt, address(A), 0, outAmt, dl, true, 1 ether
        );
        uint256 before = address(this).balance;
        // cancel should refund inAmt - inDone = 2 ETH
        zamm.cancelOrder(address(0), 0, inAmt, address(A), 0, outAmt, dl, true);
        assertEq(address(this).balance, before + 2 ether);
    }

    /// @dev Expired orders are still cancelable
    function testCancelAfterExpiryAllowed() public {
        uint96 inAmt = 1e18;
        uint96 outAmt = 1e18;
        uint56 dl = uint56(block.timestamp + 1);
        zamm.makeOrder(address(A), 0, inAmt, address(B), 0, outAmt, dl, false);
        vm.warp(dl + 10);
        // should not revert
        zamm.cancelOrder(address(A), 0, inAmt, address(B), 0, outAmt, dl, false);
        // and order is gone
        (, uint56 postDl,,) = zamm.orders(
            keccak256(
                abi.encode(msg.sender, address(A), 0, inAmt, address(B), 0, outAmt, dl, false)
            )
        );
        assertEq(postDl, 0);
    }

    receive() external payable {}
}
