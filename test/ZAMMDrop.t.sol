// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {IZAMM, ZAMMDrop} from "../periphery/ZAMMDrop.sol";

/// @dev a minimal ERC-6909 mock implementing only transferFrom/transfer
contract Mock6909 {
    mapping(address => mapping(uint256 => uint256)) public balanceOf;
    mapping(address => mapping(uint256 => mapping(address => bool))) public isOperator;

    bool public shouldFailTransferFrom;
    bool public shouldFailTransfer;

    function mint(address to, uint256 id, uint256 amt) external {
        balanceOf[to][id] += amt;
    }

    function setOperator(address spender, uint256 id, bool ok) external {
        isOperator[msg.sender][id][spender] = ok;
    }

    function setFailTransferFrom(bool v) external {
        shouldFailTransferFrom = v;
    }

    function setFailTransfer(bool v) external {
        shouldFailTransfer = v;
    }

    function transferFrom(address from, address to, uint256 id, uint256 amt)
        external
        returns (bool)
    {
        if (shouldFailTransferFrom) return false;
        require(balanceOf[from][id] >= amt, "bal");
        balanceOf[from][id] -= amt;
        balanceOf[to][id] += amt;
        return true;
    }

    function transfer(address to, uint256 id, uint256 amt) external returns (bool) {
        if (shouldFailTransfer) return false;
        require(balanceOf[msg.sender][id] >= amt, "bal");
        balanceOf[msg.sender][id] -= amt;
        balanceOf[to][id] += amt;
        return true;
    }
}

contract ZAMMDropTest is Test {
    ZAMMDrop drop;
    Mock6909 token;

    address constant alice = address(0xA11CE);
    address constant bob = address(0xB0B);
    address constant carol = address(0xCAFE);
    uint256 constant ID = 1;

    function setUp() public {
        drop = new ZAMMDrop();
        token = new Mock6909();

        // give Alice 100 tokens of ID=1, and let drop pull them
        token.mint(alice, ID, 100);
        vm.prank(alice);
        token.setOperator(address(drop), ID, true);
    }

    /// @notice happy path: Alice airdrops 40→Bob and 60→Carol
    function testDropHappyPath() public {
        address[] memory tos = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        tos[0] = bob;
        amounts[0] = 40;
        tos[1] = carol;
        amounts[1] = 60;

        vm.prank(alice);
        drop.drop(IZAMM(address(token)), ID, 100, tos, amounts);

        assertEq(token.balanceOf(alice, ID), 0);
        assertEq(token.balanceOf(bob, ID), 40);
        assertEq(token.balanceOf(carol, ID), 60);
        assertEq(token.balanceOf(address(drop), ID), 0);
    }

    /// @notice mismatched arrays must revert
    function testMismatchedLengthsReverts() public {
        address[] memory tos = new address[](2);
        uint256[] memory amounts = new uint256[](1);

        tos[0] = bob;
        tos[1] = carol;
        amounts[0] = 10;

        vm.prank(alice);
        vm.expectRevert();
        drop.drop(IZAMM(address(token)), ID, 10, tos, amounts);
    }

    /// @notice simulate transferFrom failure
    function testTransferFromFailReverts() public {
        token.setFailTransferFrom(true);

        address[] memory tos = new address[](1);
        uint256[] memory amounts = new uint256[](1);

        tos[0] = bob;
        amounts[0] = 10;

        vm.prank(alice);
        vm.expectRevert();
        drop.drop(IZAMM(address(token)), ID, 10, tos, amounts);
    }

    /// @notice if totalAmount > sum(amounts), leftovers stay in the contract
    function testTotalGreaterThanSumLeavesResidue() public {
        address[] memory tos = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        tos[0] = bob;
        amounts[0] = 10;
        tos[1] = carol;
        amounts[1] = 20;

        vm.prank(alice);
        drop.drop(IZAMM(address(token)), ID, 40, tos, amounts);

        assertEq(token.balanceOf(bob, ID), 10);
        assertEq(token.balanceOf(carol, ID), 20);
        assertEq(token.balanceOf(address(drop), ID), 10);
        assertEq(token.balanceOf(alice, ID), 60);
    }

    /// @notice dropping to zero recipients is allowed (no-op)
    function testZeroRecipients() public {
        address[] memory tos = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.prank(alice);
        drop.drop(IZAMM(address(token)), ID, 0, tos, amounts);

        assertEq(token.balanceOf(alice, ID), 100);
        assertEq(token.balanceOf(address(drop), ID), 0);
    }
}
