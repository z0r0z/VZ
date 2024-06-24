// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {VZPair, VZFactory} from "../src/VZFactory.sol";
import "@solady/test/utils/mocks/MockERC20.sol";

/// @dev Forked from Zuniswap (https://github.com/Jeiwan/zuniswapv2/blob/main/test/ZuniswapV2Factory.t.sol).
contract VZFactoryTest is Test {
    VZFactory internal factory;

    MockERC20 token0;
    MockERC20 token1;
    MockERC20 token2;
    MockERC20 token3;

    function setUp() public {
        factory = new VZFactory(makeAddr("alice"));

        token0 = new MockERC20("Token A", "TKNA", 18);
        token1 = new MockERC20("Token B", "TKNB", 18);
        token2 = new MockERC20("Token C", "TKNC", 18);
        token3 = new MockERC20("Token D", "TKND", 18);
    }

    function encodeError(string memory error) internal pure returns (bytes memory encoded) {
        encoded = abi.encodeWithSignature(error);
    }

    function testCreatePair() public {
        address pairAddress = factory.createPair(address(token1), address(token0));

        VZPair pair = VZPair(pairAddress);

        assertEq(pair.token0(), address(token0));
        assertEq(pair.token1(), address(token1));
    }

    function testCreatePairZeroAddress() public {
        vm.expectRevert(encodeError("ZERO_ADDRESS()"));
        factory.createPair(address(0), address(token0));

        vm.expectRevert(encodeError("ZERO_ADDRESS()"));
        factory.createPair(address(token1), address(0));
    }

    function testCreatePairPairExists() public {
        factory.createPair(address(token1), address(token0));

        vm.expectRevert(encodeError("PAIR_EXISTS()"));
        factory.createPair(address(token1), address(token0));
    }

    function testCreatePairIdenticalTokens() public {
        vm.expectRevert(encodeError("IDENTICAL_ADDRESSES()"));
        factory.createPair(address(token0), address(token0));
    }
}
