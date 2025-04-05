// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "@solady/test/utils/mocks/MockERC20.sol";
import "@solady/test/utils/mocks/MockERC6909.sol";

import {VZPairs} from "../src/VZPairs.sol";

/// @dev Forked from Zuniswap (https://github.com/Jeiwan/zuniswapv2/blob/main/test/ZuniswapV2Pair.t.sol).
contract VZPairsTest is Test {
    MockERC20 token0;
    MockERC20 token1;
    MockERC20 ofToken;
    VZPairs pairs;
    TestUser testUser;

    MockERC6909 token6909A;
    MockERC6909 token6909B;
    uint256 token6909AId;
    uint256 token6909BId;

    // Use PoolKey structs with the same variable names
    VZPairs.PoolKey pair;
    VZPairs.PoolKey ethPair;
    VZPairs.PoolKey ofPair;
    VZPairs.PoolKey erc6909Pair;

    uint256 pairId;
    uint256 ethPairId;
    uint256 ofPairId;
    uint256 erc6909PairId;

    function setUp() public {
        // Existing setup code
        address tokenA = address(new MockERC20("Token A", "TKNA", 18));
        address tokenB = address(new MockERC20("Token B", "TKNB", 18));
        ofToken = new MockERC20("Overflow Token", "OVFL", 18);

        (address _token0, address _token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        token0 = MockERC20(_token0);
        token1 = MockERC20(_token1);

        // Set up ERC6909 tokens
        token6909A = new MockERC6909();
        token6909B = new MockERC6909();
        token6909AId = 123; // Custom token ID for token A
        token6909BId = 456; // Custom token ID for token B

        // Ensure token6909A address < token6909B address for consistent ordering
        (address _token6909A, address _token6909B, uint256 _id6909A, uint256 _id6909B) = address(
            token6909A
        ) < address(token6909B)
            ? (address(token6909A), address(token6909B), token6909AId, token6909BId)
            : (address(token6909B), address(token6909A), token6909BId, token6909AId);

        // Create PoolKey for ERC6909 tokens
        erc6909Pair = VZPairs.PoolKey({
            token0: _token6909A,
            id0: _id6909A,
            token1: _token6909B,
            id1: _id6909B,
            swapFee: 30
        });

        // Regular setup
        pairs = new VZPairs(address(1));

        // Create PoolKey structs using the same variable names as before
        pair = VZPairs.PoolKey({
            token0: address(token0),
            id0: 0,
            token1: address(token1),
            id1: 0,
            swapFee: 30
        });

        ethPair = VZPairs.PoolKey({
            token0: address(0),
            id0: 0,
            token1: address(token1),
            id1: 0,
            swapFee: 30
        });

        ofPair = VZPairs.PoolKey({
            token0: address(0),
            id0: 0,
            token1: address(ofToken),
            id1: 0,
            swapFee: 30
        });

        // For the TestUser, we need to compute the actual pair ID
        pairId = uint256(keccak256(abi.encode(address(token0), 0, address(token1), 0, 30)));
        ethPairId = uint256(keccak256(abi.encode(address(0), 0, address(token1), 0, 30)));
        ofPairId = uint256(keccak256(abi.encode(address(0), 0, address(ofToken), 0, 30)));
        erc6909PairId =
            uint256(keccak256(abi.encode(_token6909A, _id6909A, _token6909B, _id6909B, 30)));
        testUser = new TestUser(pairId, pair);

        // Mint regular tokens
        token0.mint(address(this), 10 ether);
        token1.mint(address(this), 10 ether);
        token0.mint(address(testUser), 10 ether);
        token1.mint(address(testUser), 10 ether);
        ofToken.mint(address(this), type(uint120).max);
        ofToken.mint(address(testUser), type(uint120).max);

        // Mint ERC6909 tokens
        token6909A.mint(address(this), token6909AId, 10 ether);
        token6909B.mint(address(this), token6909BId, 10 ether);
        token6909A.mint(address(testUser), token6909AId, 10 ether);
        token6909B.mint(address(testUser), token6909BId, 10 ether);

        payable(address(testUser)).transfer(3.33 ether);
        token1.approve(address(pairs), 2 ether);
    }

    /// @dev Helper function to compute poolId from PoolKey.
    function computePoolId(VZPairs.PoolKey memory key) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(key.token0, key.id0, key.token1, key.id1, key.swapFee)));
    }

    // Add helper functions for ERC6909 assertion
    function assertERC6909Reserves(uint112 expectedReserve0, uint112 expectedReserve1)
        internal
        view
    {
        (uint112 reserve0, uint112 reserve1,,,,,) = pairs.pools(computePoolId(erc6909Pair));
        assertEq(reserve0, expectedReserve0, "unexpected ERC6909 reserve0");
        assertEq(reserve1, expectedReserve1, "unexpected ERC6909 reserve1");
    }

    function encodeError(string memory error) internal pure returns (bytes memory encoded) {
        encoded = abi.encodeWithSignature(error);
    }

    function encodeError(string memory error, uint256 a)
        internal
        pure
        returns (bytes memory encoded)
    {
        encoded = abi.encodeWithSignature(error, a);
    }

    function assertReserves(uint112 expectedReserve0, uint112 expectedReserve1) internal view {
        (uint112 reserve0, uint112 reserve1,,,,,) = pairs.pools(computePoolId(pair));
        assertEq(reserve0, expectedReserve0, "unexpected reserve0");
        assertEq(reserve1, expectedReserve1, "unexpected reserve1");
    }

    function assertReservesETH(uint112 expectedReserve0, uint112 expectedReserve1) internal view {
        (uint112 reserve0, uint112 reserve1,,,,,) = pairs.pools(computePoolId(ethPair));
        assertEq(reserve0, expectedReserve0, "unexpected reserve0");
        assertEq(reserve1, expectedReserve1, "unexpected reserve1");
    }

    function assertCumulativePrices(uint256 expectedPrice0, uint256 expectedPrice1) internal view {
        (,,, uint256 price0CumulativeLast, uint256 price1CumulativeLast,,) =
            pairs.pools(computePoolId(pair));
        assertEq(price0CumulativeLast, expectedPrice0, "unexpected cumulative price 0");
        assertEq(price1CumulativeLast, expectedPrice1, "unexpected cumulative price 1");
    }

    function calculateCurrentPrice() internal view returns (uint256 price0, uint256 price1) {
        (uint112 reserve0, uint112 reserve1,,,,,) = pairs.pools(computePoolId(pair));
        price0 = reserve0 > 0 ? (reserve1 * uint256(UQ112x112.Q112)) / reserve0 : 0;
        price1 = reserve1 > 0 ? (reserve0 * uint256(UQ112x112.Q112)) / reserve1 : 0;
    }

    function assertBlockTimestampLast(uint32 expected) internal view {
        (,, uint32 blockTimestampLast,,,,) = pairs.pools(computePoolId(pair));

        assertEq(blockTimestampLast, expected, "unexpected blockTimestampLast");
    }

    function testMintBootstrap() public {
        token0.approve(address(pairs), 1 ether);
        token1.approve(address(pairs), 1 ether);

        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 1 ether);
        pairs.initialize(pair, address(this));

        assertEq(pairs.balanceOf(address(this), pairId), 1 ether - 1000);
        assertReserves(1 ether, 1 ether);
        (,,,,,, uint256 supply) = pairs.pools(pairId);
        assertEq(supply, 1 ether);
    }

    error PoolExists();

    function testMintBootstrapFailAlreadyInit() public {
        token0.approve(address(pairs), 1 ether);
        token1.approve(address(pairs), 1 ether);

        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 1 ether);
        pairs.initialize(pair, address(this));

        assertEq(pairs.balanceOf(address(this), pairId), 1 ether - 1000);
        assertReserves(1 ether, 1 ether);
        (,,,,,, uint256 supply) = pairs.pools(pairId);
        assertEq(supply, 1 ether);
        vm.expectRevert(PoolExists.selector);
        pairs.initialize(pair, address(this));
    }

    error Overflow();

    function testMintBootstrapFailOverflow() public {
        ofToken.approve(address(pairs), type(uint120).max);

        pairs.deposit{value: 1 ether}(address(0), 0, 1 ether);
        pairs.deposit(address(ofToken), 0, type(uint120).max);

        vm.expectRevert(Overflow.selector);
        pairs.initialize(ofPair, address(this));
    }

    function testMintWhenTheresLiquidity() public {
        token0.approve(address(pairs), 3 ether);
        token1.approve(address(pairs), 3 ether);

        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 1 ether);
        pairs.initialize(pair, address(this)); // + 1 LP.

        vm.warp(37);

        pairs.deposit(pair.token0, 0, 2 ether);
        pairs.deposit(pair.token1, 0, 2 ether);
        pairs.mint(pair, address(this)); // + 2 LP.

        assertEq(pairs.balanceOf(address(this), pairId), 3 ether - 1000);
        (,,,,,, uint256 supply) = pairs.pools(pairId);
        assertEq(supply, 3 ether);
        assertReserves(3 ether, 3 ether);
    }

    function testMintUnbalanced() public {
        token0.approve(address(pairs), 3 ether);
        token1.approve(address(pairs), 2 ether);

        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 1 ether);
        pairs.initialize(pair, address(this));

        assertEq(pairs.balanceOf(address(this), pairId), 1 ether - 1000);
        assertReserves(1 ether, 1 ether);

        pairs.deposit(pair.token0, 0, 2 ether);
        pairs.deposit(pair.token1, 0, 1 ether);

        pairs.mint(pair, address(this)); // + 1 LP
        assertEq(pairs.balanceOf(address(this), pairId), 2 ether - 1000);
        assertReserves(3 ether, 2 ether);
    }

    function testMintLiquidityUnderflow() public {
        // 0x11: If an arithmetic operation results in underflow or overflow outside of an unchecked { ... } block.
        vm.expectRevert(encodeError("Panic(uint256)", 0x11));
        pairs.initialize(pair, address(this));
    }

    function testMintZeroLiquidity() public {
        token0.approve(address(pairs), 1000);
        token1.approve(address(pairs), 1000);

        pairs.deposit(pair.token0, 0, 1000);
        pairs.deposit(pair.token1, 0, 1000);

        vm.expectRevert(encodeError("InsufficientLiquidityMinted()"));
        pairs.initialize(pair, address(this));
    }

    function testBurn() public {
        token0.approve(address(pairs), 1 ether);
        token1.approve(address(pairs), 1 ether);

        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 1 ether);
        pairs.initialize(pair, address(this));

        uint256 liquidity = pairs.balanceOf(address(this), pairId);
        pairs.transfer(address(pairs), pairId, liquidity);
        pairs.burn(pair, address(this));

        assertEq(pairs.balanceOf(address(this), pairId), 0);
        assertReserves(1000, 1000);
        (,,,,,, uint256 supply) = pairs.pools(pairId);
        assertEq(supply, 1000);
        assertEq(token0.balanceOf(address(this)), 10 ether - 1000);
        assertEq(token1.balanceOf(address(this)), 10 ether - 1000);
    }

    function testBurnUnbalanced() public {
        token0.approve(address(pairs), 3 ether);
        token1.approve(address(pairs), 2 ether);

        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 1 ether);
        pairs.initialize(pair, address(this));

        pairs.deposit(pair.token0, 0, 2 ether);
        pairs.deposit(pair.token1, 0, 1 ether);

        pairs.mint(pair, address(this)); // + 1 LP.

        uint256 liquidity = pairs.balanceOf(address(this), pairId);
        pairs.transfer(address(pairs), pairId, liquidity);
        pairs.burn(pair, address(this));

        assertEq(pairs.balanceOf(address(this), pairId), 0);
        assertReserves(1500, 1000);
        (,,,,,, uint256 supply) = pairs.pools(pairId);
        assertEq(supply, 1000);
        assertEq(token0.balanceOf(address(this)), 10 ether - 1500);
        assertEq(token1.balanceOf(address(this)), 10 ether - 1000);
    }

    function testBurnUnbalancedDifferentUsers() public {
        testUser.provideLiquidity(
            payable(address(pairs)), address(token0), address(token1), 1 ether, 1 ether
        );

        assertEq(pairs.balanceOf(address(this), pairId), 0);
        assertEq(pairs.balanceOf(address(testUser), pairId), 1 ether - 1000);
        (,,,,,, uint256 supply) = pairs.pools(pairId);
        assertEq(supply, 1 ether);

        token0.approve(address(pairs), 2 ether);
        token1.approve(address(pairs), 1 ether);

        pairs.deposit(address(token0), 0, 2 ether);
        pairs.deposit(address(token1), 0, 1 ether);

        pairs.mint(pair, address(this)); // + 1 LP

        uint256 liquidity = pairs.balanceOf(address(this), pairId);
        pairs.transfer(address(pairs), pairId, liquidity);
        pairs.burn(pair, address(this));

        // this user is penalized for providing unbalanced liquidity
        assertEq(pairs.balanceOf(address(this), pairId), 0);
        assertReserves(1.5 ether, 1 ether);
        (,,,,,, supply) = pairs.pools(pairId);
        assertEq(supply, 1 ether);
        assertEq(token0.balanceOf(address(this)), 10 ether - 0.5 ether);
        assertEq(token1.balanceOf(address(this)), 10 ether);

        testUser.removeLiquidity(payable(address(pairs)));

        // testUser receives the amount collected from this user
        assertEq(pairs.balanceOf(address(testUser), pairId), 0);
        assertReserves(1500, 1000);
        (,,,,,, supply) = pairs.pools(pairId);
        assertEq(supply, 1000);
        assertEq(token0.balanceOf(address(testUser)), 10 ether + 0.5 ether - 1500);
        assertEq(token1.balanceOf(address(testUser)), 10 ether - 1000);
    }

    function testBurnZeroTotalSupply() public {
        // 0x12; If you divide or modulo by zero.
        vm.expectRevert(encodeError("MulDivFailed()"));
        pairs.burn(pair, address(this));
    }

    function testBurnZeroLiquidity() public {
        // Transfer and mint as a normal user.
        token0.approve(address(pairs), 1 ether);
        token1.approve(address(pairs), 1 ether);

        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 1 ether);
        pairs.initialize(pair, address(this));

        vm.prank(address(0xdeadbeef));
        vm.expectRevert(encodeError("InsufficientLiquidityBurned()"));
        pairs.burn(pair, address(this));
    }

    function testSwapBasicScenario() public {
        token0.approve(address(pairs), 1.1 ether);
        token1.approve(address(pairs), 2 ether);

        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 2 ether);
        pairs.initialize(pair, address(this));

        uint256 amountOut = 0.181322178776029826 ether;
        pairs.deposit(pair.token0, 0, 0.1 ether);
        pairs.swap(pair, 0, amountOut, address(this), "");

        assertEq(
            token0.balanceOf(address(this)),
            10 ether - 1 ether - 0.1 ether,
            "unexpected token0 balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            10 ether - 2 ether + amountOut,
            "unexpected token1 balance"
        );
        assertReserves(1 ether + 0.1 ether, uint112(2 ether - amountOut));
    }

    function testSwapETHScenario() public {
        uint256 startingETHBalance = address(this).balance;
        token1.approve(address(pairs), 2 ether);

        pairs.deposit{value: 1 ether}(ethPair.token0, 0, 1 ether);
        pairs.deposit(ethPair.token1, 0, 2 ether);
        pairs.initialize(ethPair, address(this));

        uint256 amountOut = 0.181322178776029826 ether;
        pairs.deposit{value: 0.1 ether}(ethPair.token0, 0, 0.1 ether);
        pairs.swap(ethPair, 0, amountOut, address(this), "");

        assertEq(
            address(this).balance,
            startingETHBalance - 1 ether - 0.1 ether,
            "unexpected token0/eth balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            10 ether - 2 ether + amountOut,
            "unexpected token1 balance"
        );
        assertReservesETH(1 ether + 0.1 ether, uint112(2 ether - amountOut));
    }

    function testSwapETHScenarioGas() public payable {
        pairs.deposit{value: 1 ether}(address(0), 0, 1 ether);
        pairs.deposit(address(token1), 0, 2 ether);
        pairs.initialize(ethPair, address(this));

        uint256 amountOut = 0.181322178776029826 ether;
        pairs.deposit{value: 0.1 ether}(ethPair.token0, 0, 0.1 ether);
        pairs.swap(ethPair, 0, amountOut, address(this), "");
    }

    function testSwapBasicScenarioReverseDirection() public {
        token0.approve(address(pairs), 1 ether);
        token1.approve(address(pairs), 2.2 ether);

        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 2 ether);
        pairs.initialize(pair, address(this));

        pairs.deposit(pair.token1, 0, 0.2 ether);

        pairs.swap(pair, 0.09 ether, 0, address(this), "");

        assertEq(
            token0.balanceOf(address(this)),
            10 ether - 1 ether + 0.09 ether,
            "unexpected token0 balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            10 ether - 2 ether - 0.2 ether,
            "unexpected token1 balance"
        );
        assertReserves(1 ether - 0.09 ether, 2 ether + 0.2 ether);
    }

    function testSwapBidirectional() public {
        token0.approve(address(pairs), 1.1 ether);
        token1.approve(address(pairs), 2.2 ether);

        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 2 ether);
        pairs.initialize(pair, address(this));

        pairs.deposit(pair.token0, 0, 0.1 ether);
        pairs.deposit(pair.token1, 0, 0.2 ether);

        pairs.swap(pair, 0.09 ether, 0.18 ether, address(this), "");

        assertEq(
            token0.balanceOf(address(this)),
            10 ether - 1 ether - 0.01 ether,
            "unexpected token0 balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            10 ether - 2 ether - 0.02 ether,
            "unexpected token1 balance"
        );
        assertReserves(1 ether + 0.01 ether, 2 ether + 0.02 ether);
    }

    function testSwapZeroOut() public {
        token0.approve(address(pairs), 1 ether);
        token1.approve(address(pairs), 2 ether);

        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 2 ether);
        pairs.initialize(pair, address(this));

        vm.expectRevert(encodeError("InsufficientOutputAmount()"));
        pairs.swap(pair, 0, 0, address(this), "");
    }

    function testSwapInsufficientLiquidity() public {
        token0.approve(address(pairs), 1 ether);
        token1.approve(address(pairs), 2 ether);

        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 2 ether);
        pairs.initialize(pair, address(this));

        vm.expectRevert(encodeError("InsufficientLiquidity()"));
        pairs.swap(pair, 0, 2.1 ether, address(this), "");

        vm.expectRevert(encodeError("InsufficientLiquidity()"));
        pairs.swap(pair, 1.1 ether, 0, address(this), "");
    }

    function testSwapUnderpriced() public {
        token0.approve(address(pairs), 1.1 ether);
        token1.approve(address(pairs), 2 ether);

        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 2 ether);
        pairs.initialize(pair, address(this));

        pairs.deposit(pair.token0, 0, 0.1 ether);

        pairs.swap(pair, 0, 0.09 ether, address(this), "");

        assertEq(
            token0.balanceOf(address(this)),
            10 ether - 1 ether - 0.1 ether,
            "unexpected token0 balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            10 ether - 2 ether + 0.09 ether,
            "unexpected token1 balance"
        );
        assertReserves(1 ether + 0.1 ether, 2 ether - 0.09 ether);
    }

    function testSwapOverpriced() public {
        token0.approve(address(pairs), 1.1 ether);
        token1.approve(address(pairs), 2 ether);

        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 2 ether);
        pairs.initialize(pair, address(this));

        pairs.deposit(pair.token0, 0, 0.1 ether);

        vm.expectRevert(encodeError("K()"));
        pairs.swap(pair, 0, 0.36 ether, address(this), "");

        assertEq(
            token0.balanceOf(address(this)),
            10 ether - 1 ether - 0.1 ether,
            "unexpected token0 balance"
        );
        assertEq(token1.balanceOf(address(this)), 10 ether - 2 ether, "unexpected token1 balance");
        assertReserves(1 ether, 2 ether);
    }

    function testSwapUnpaidFee() public {
        token0.approve(address(pairs), 1.1 ether);
        token1.approve(address(pairs), 2 ether);

        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 2 ether);
        pairs.initialize(pair, address(this));

        pairs.deposit(pair.token0, 0, 0.1 ether);

        vm.expectRevert(encodeError("K()"));
        pairs.swap(pair, 0, 0.181322178776029827 ether, address(this), "");
    }

    function testCumulativePrices() public {
        vm.warp(0);
        token0.approve(address(pairs), 10 ether);
        token1.approve(address(pairs), 10 ether);

        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 1 ether);
        pairs.initialize(pair, address(this));

        (uint256 initialPrice0, uint256 initialPrice1) = calculateCurrentPrice();

        // 0 seconds passed.
        pairs.sync(pair);
        assertCumulativePrices(0, 0);

        // 1 second passed.
        vm.warp(1);
        pairs.sync(pair);
        assertBlockTimestampLast(1);
        assertCumulativePrices(initialPrice0, initialPrice1);

        // 2 seconds passed.
        vm.warp(2);
        pairs.sync(pair);
        assertBlockTimestampLast(2);
        assertCumulativePrices(initialPrice0 * 2, initialPrice1 * 2);

        // 3 seconds passed.
        vm.warp(3);
        pairs.sync(pair);
        assertBlockTimestampLast(3);
        assertCumulativePrices(initialPrice0 * 3, initialPrice1 * 3);

        // // Price changed.
        pairs.deposit(pair.token0, 0, 2 ether);
        pairs.deposit(pair.token1, 0, 1 ether);
        pairs.mint(pair, address(this));

        (uint256 newPrice0, uint256 newPrice1) = calculateCurrentPrice();

        // // 0 seconds since last reserves update.
        assertCumulativePrices(initialPrice0 * 3, initialPrice1 * 3);

        // // 1 second passed.
        vm.warp(4);
        pairs.sync(pair);
        assertBlockTimestampLast(4);
        assertCumulativePrices(initialPrice0 * 3 + newPrice0, initialPrice1 * 3 + newPrice1);

        // 2 seconds passed.
        vm.warp(5);
        pairs.sync(pair);
        assertBlockTimestampLast(5);
        assertCumulativePrices(initialPrice0 * 3 + newPrice0 * 2, initialPrice1 * 3 + newPrice1 * 2);

        // 3 seconds passed.
        vm.warp(6);
        pairs.sync(pair);
        assertBlockTimestampLast(6);
        assertCumulativePrices(initialPrice0 * 3 + newPrice0 * 3, initialPrice1 * 3 + newPrice1 * 3);
    }
    /*
    function testFlashloan() public {
        token0.approve(address(pairs), 1 ether);
        token1.approve(address(pairs), 2 ether);

        uint256 poolId = pairs.deposit(pair, 1 ether, 2 ether);
        pairs.initialize(pair, address(this));

        uint256 flashloanAmount = 0.1 ether;
        uint256 flashloanFee = (flashloanAmount * 1000) / 997 - flashloanAmount + 1;

        Flashloaner fl = new Flashloaner(poolId, pair);

        token1.transfer(address(fl), flashloanFee);

        fl.flashloan(address(pairs), 0, flashloanAmount, address(token1));

        assertEq(token1.balanceOf(address(fl)), 0);
        assertEq(token1.balanceOf(address(pairs)), 2 ether + flashloanFee);
    }
    */

    function testERC6909Bootstrap() public {
        token6909A.approve(address(pairs), token6909AId, 1 ether);
        token6909B.approve(address(pairs), token6909BId, 1 ether);

        pairs.deposit(erc6909Pair.token0, erc6909Pair.id0, 1 ether);
        pairs.deposit(erc6909Pair.token1, erc6909Pair.id1, 1 ether);
        pairs.initialize(erc6909Pair, address(this));

        // Verify LP tokens were minted
        assertEq(pairs.balanceOf(address(this), erc6909PairId), 1 ether - 1000);
        assertERC6909Reserves(uint112(1 ether), uint112(1 ether));
        (,,,,,, uint256 supply) = pairs.pools(erc6909PairId);
        assertEq(supply, 1 ether);
    }

    function testERC6909Mint() public {
        // Bootstrap the pair first
        testERC6909Bootstrap();

        token6909A.approve(address(pairs), token6909AId, 2 ether);
        token6909B.approve(address(pairs), token6909BId, 2 ether);

        pairs.deposit(erc6909Pair.token0, erc6909Pair.id0, 2 ether);
        pairs.deposit(erc6909Pair.token1, erc6909Pair.id1, 2 ether);

        // Mint more LP tokens
        pairs.mint(erc6909Pair, address(this));

        // Verify additional LP tokens were minted
        assertEq(pairs.balanceOf(address(this), erc6909PairId), 3 ether - 1000);
        assertERC6909Reserves(uint112(3 ether), uint112(3 ether));
        (,,,,,, uint256 supply) = pairs.pools(erc6909PairId);
        assertEq(supply, 3 ether);
    }

    function testERC6909Burn() public {
        // Bootstrap and mint additional liquidity
        testERC6909Mint();

        // Get all LP tokens
        uint256 liquidity = pairs.balanceOf(address(this), erc6909PairId);

        // Transfer LP tokens to the pair contract for burning
        pairs.transfer(address(pairs), erc6909PairId, liquidity);

        // Burn LP tokens to get tokens back
        pairs.burn(erc6909Pair, address(this));

        // Verify LP tokens were burned
        assertEq(pairs.balanceOf(address(this), erc6909PairId), 0);
        assertERC6909Reserves(uint112(1000), uint112(1000));
        (,,,,,, uint256 supply) = pairs.pools(erc6909PairId);
        assertEq(supply, 1000);

        // Check if tokens were returned correctly
        (address token6909First,,,) = address(token6909A) < address(token6909B)
            ? (address(token6909A), address(token6909B), token6909AId, token6909BId)
            : (address(token6909B), address(token6909A), token6909BId, token6909AId);

        if (token6909First == address(token6909A)) {
            assertEq(token6909A.balanceOf(address(this), token6909AId), 10 ether - 1000);
            assertEq(token6909B.balanceOf(address(this), token6909BId), 10 ether - 1000);
        } else {
            assertEq(token6909B.balanceOf(address(this), token6909BId), 10 ether - 1000);
            assertEq(token6909A.balanceOf(address(this), token6909AId), 10 ether - 1000);
        }
    }

    function testERC6909Swap() public {
        // Bootstrap the pair first
        testERC6909Bootstrap();

        // Get correct token order based on addresses
        (address token6909First,,,) = address(token6909A) < address(token6909B)
            ? (address(token6909A), address(token6909B), token6909AId, token6909BId)
            : (address(token6909B), address(token6909A), token6909BId, token6909AId);

        // Use direct transfer
        token6909A.approve(address(pairs), token6909AId, 0.1 ether);

        pairs.deposit(token6909First, token6909AId, 0.1 ether);

        // Calculate the amount to receive based on constant product formula
        uint256 amountOut = 0.09 ether;

        // Execute the swap
        if (token6909First == address(token6909A)) {
            pairs.swap(erc6909Pair, 0, amountOut, address(this), "");

            // Verify balances after swap
            assertEq(
                token6909A.balanceOf(address(this), token6909AId),
                10 ether - 1 ether - 0.1 ether,
                "unexpected token6909A balance"
            );
            assertEq(
                token6909B.balanceOf(address(this), token6909BId),
                10 ether - 1 ether + amountOut,
                "unexpected token6909B balance"
            );

            // Verify reserves after swap
            assertERC6909Reserves(uint112(1 ether + 0.1 ether), uint112(1 ether - amountOut));
        } else {
            pairs.swap(erc6909Pair, amountOut, 0, address(this), "");

            // Verify balances after swap
            assertEq(
                token6909A.balanceOf(address(this), token6909AId),
                10 ether - 1 ether - 0.1 ether + amountOut,
                "unexpected token6909A balance"
            );
            assertEq(
                token6909B.balanceOf(address(this), token6909BId),
                10 ether - 1 ether,
                "unexpected token6909B balance"
            );

            // Verify reserves after swap
            assertERC6909Reserves(uint112(1 ether - amountOut), uint112(1 ether + 0.1 ether));
        }
    }

    function testERC6909AndERC20Pair() public {
        // Create a pair with one ERC6909 token and one ERC20 token
        address token6909Addr = address(token6909A);
        address tokenERC20Addr = address(token0);

        // Get the correct order
        address tokenA;
        address tokenB;
        uint256 idA;
        uint256 idB;

        if (token6909Addr < tokenERC20Addr) {
            tokenA = token6909Addr;
            tokenB = tokenERC20Addr;
            idA = token6909AId;
            idB = 0;
        } else {
            tokenA = tokenERC20Addr;
            tokenB = token6909Addr;
            idA = 0;
            idB = token6909AId;
        }

        // Create PoolKey for mixed pair
        VZPairs.PoolKey memory mixedPairKey =
            VZPairs.PoolKey({token0: tokenA, id0: idA, token1: tokenB, id1: idB, swapFee: 30});

        // Store initial balances
        uint256 initialToken0Balance = token0.balanceOf(address(this));
        uint256 initialToken6909Balance = token6909A.balanceOf(address(this), token6909AId);

        // Approve tokens
        token6909A.approve(address(pairs), token6909AId, 1.1 ether);
        token0.approve(address(pairs), 1.1 ether);

        // Deposit tokens for initialization
        pairs.deposit(tokenA, idA, 1 ether);
        pairs.deposit(tokenB, idB, 1 ether);

        // Initialize the pair
        pairs.initialize(mixedPairKey, address(this));

        // Verify LP tokens were minted
        uint256 mixedPairId = computePoolId(mixedPairKey);
        assertEq(pairs.balanceOf(address(this), mixedPairId), 1 ether - 1000);

        // Verify reserves
        (uint112 reserve0, uint112 reserve1,,,,,) = pairs.pools(mixedPairId);
        assertEq(reserve0, 1 ether);
        assertEq(reserve1, 1 ether);

        // Deposit more token0 for the swap
        pairs.deposit(tokenA, idA, 0.1 ether);

        // Calculate the amount to receive based on constant product formula
        uint256 amountOut = 0.09 ether;

        // Execute the swap
        pairs.swap(mixedPairKey, 0, amountOut, address(this), "");

        // Calculate expected balances after all operations
        uint256 expectedToken0Balance;
        uint256 expectedToken6909Balance;

        if (tokenA == token6909Addr) {
            // token6909 is token0, token0 is token1
            expectedToken6909Balance = initialToken6909Balance - 1 ether - 0.1 ether;
            expectedToken0Balance = initialToken0Balance - 1 ether + amountOut;
        } else {
            // token0 is token0, token6909 is token1
            expectedToken0Balance = initialToken0Balance - 1 ether - 0.1 ether;
            expectedToken6909Balance = initialToken6909Balance - 1 ether + amountOut;
        }

        // Verify final balances
        assertEq(
            token0.balanceOf(address(this)), expectedToken0Balance, "unexpected token0 balance"
        );

        assertEq(
            token6909A.balanceOf(address(this), token6909AId),
            expectedToken6909Balance,
            "unexpected token6909A balance"
        );

        // Verify final reserves
        (reserve0, reserve1,,,,,) = pairs.pools(mixedPairId);
        assertEq(reserve0, 1 ether + 0.1 ether, "unexpected reserve0 after swap");
        assertEq(reserve1, 1 ether - amountOut, "unexpected reserve1 after swap");
    }

    function testMultiHopSwap() public {
        // Setup
        token0.approve(address(pairs), 10 ether);
        token1.approve(address(pairs), 10 ether);

        // Create pair0 (token0/token1)
        pairs.deposit(pair.token0, 0, 2 ether);
        pairs.deposit(pair.token1, 0, 2 ether);
        pairs.initialize(pair, address(this));

        // Create a second token for the next hop
        MockERC20 token2 = new MockERC20("Token C", "TKNC", 18);
        token2.mint(address(this), 10 ether);
        token2.approve(address(pairs), 10 ether);

        // Create pair1 (token1/token2) - ensure token addresses are ordered correctly
        address tokenA;
        address tokenB;
        if (address(token1) < address(token2)) {
            tokenA = address(token1);
            tokenB = address(token2);
        } else {
            tokenA = address(token2);
            tokenB = address(token1);
        }

        VZPairs.PoolKey memory pair1 =
            VZPairs.PoolKey({token0: tokenA, id0: 0, token1: tokenB, id1: 0, swapFee: 30});

        // Initialize pair1
        pairs.deposit(tokenA, 0, 2 ether);
        pairs.deposit(tokenB, 0, 2 ether);
        pairs.initialize(pair1, address(this));

        // Track initial balances - IMPORTANT: take balances AFTER creating the pairs
        uint256 initialToken0Balance = token0.balanceOf(address(this));
        uint256 initialToken1Balance = token1.balanceOf(address(this));
        uint256 initialToken2Balance = token2.balanceOf(address(this));

        // Execute multihop swap: token0 -> token1 -> token2
        // First swap: token0 -> token1 (using pair)
        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.swap(pair, 0, 0.5 ether, address(this), "");

        // Second swap: token1 -> token2 (using pair1)
        token1.approve(address(pairs), 0.5 ether);
        pairs.deposit(address(token1), 0, 0.5 ether);

        // Determine which token is which in the second pair
        uint256 amountOut;
        if (address(token1) == tokenA) {
            amountOut = 0.25 ether; // Amount of token2 to receive
            pairs.swap(pair1, 0, amountOut, address(this), "");
        } else {
            amountOut = 0.25 ether; // Amount of token2 to receive
            pairs.swap(pair1, amountOut, 0, address(this), "");
        }

        // Verify final balances
        assertEq(token0.balanceOf(address(this)), initialToken0Balance - 1 ether);

        // For token1, the balance accounting is:
        // initialToken1Balance + 0.5 ether (from first swap) - 0.5 ether (deposited for second swap)
        // = initialToken1Balance
        assertEq(token1.balanceOf(address(this)), initialToken1Balance);

        assertEq(token2.balanceOf(address(this)), initialToken2Balance + amountOut);
    }

    function testProtocolFeeCollection() public {
        // Set fee receiver (must use prank to simulate being the feeToSetter from constructor)
        address feeReceiver = address(0xFEE);
        vm.prank(address(1)); // This is the feeToSetter from constructor
        pairs.setFeeTo(feeReceiver);

        token0.approve(address(pairs), 10 ether);
        token1.approve(address(pairs), 10 ether);

        // Initialize pair
        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 1 ether);
        pairs.initialize(pair, address(this));

        // Add liquidity to generate fees
        pairs.deposit(pair.token0, 0, 2 ether);
        pairs.deposit(pair.token1, 0, 2 ether);
        pairs.mint(pair, address(this));

        // Make swaps to generate fees - use more reasonable amounts
        pairs.deposit(pair.token0, 0, 0.1 ether);
        // Calculate a valid amount that respects the constant product formula
        // For a 0.1 ETH input with 3 ETH reserves on both sides and 0.3% fee:
        // The maximum output would be approximately 0.09 ETH
        pairs.swap(pair, 0, 0.09 ether, address(this), "");

        pairs.deposit(pair.token1, 0, 0.1 ether);
        pairs.swap(pair, 0.09 ether, 0, address(this), "");

        // Record the current LP token balance
        uint256 myLpTokensBefore = pairs.balanceOf(address(this), pairId);

        // Add liquidity again to trigger fee mint
        pairs.deposit(pair.token0, 0, 1 ether);
        pairs.deposit(pair.token1, 0, 1 ether);
        pairs.mint(pair, address(this));

        // Check that fee receiver got LP tokens
        uint256 feeReceiverBalance = pairs.balanceOf(feeReceiver, pairId);
        assertTrue(feeReceiverBalance > 0, "Fee receiver should have LP tokens");

        // Also verify that our balance increased as expected
        uint256 myLpTokensAfter = pairs.balanceOf(address(this), pairId);
        // Should be approximately 1 ETH of LP tokens, but less than exactly 1 ETH
        // because some went to the fee receiver
        assertGt(myLpTokensAfter, myLpTokensBefore);
        assertLt(myLpTokensAfter - myLpTokensBefore, 1 ether);

        // Print out values to debug
        console.log("Fee receiver LP balance:", feeReceiverBalance);
        console.log("My LP tokens before:", myLpTokensBefore);
        console.log("My LP tokens after:", myLpTokensAfter);
        console.log("LP tokens added:", myLpTokensAfter - myLpTokensBefore);
    }
}

contract TestUser {
    uint256 immutable id;
    VZPairs.PoolKey pair;

    constructor(uint256 ID, VZPairs.PoolKey memory _pair) payable {
        id = ID;
        pair = _pair;
    }

    function provideLiquidity(
        address payable pairsAddress_,
        address token0Address_,
        address token1Address_,
        uint256 amount0_,
        uint256 amount1_
    ) public {
        bool ethBased = token0Address_ == address(0);
        if (ethBased) {
            ERC20(token1Address_).approve(pairsAddress_, amount1_);
            VZPairs(pairsAddress_).deposit{value: amount0_}(token0Address_, 0, amount0_);
            VZPairs(pairsAddress_).deposit(token1Address_, 0, amount1_);
            VZPairs(pairsAddress_).initialize(pair, address(this));
        } else {
            ERC20(token0Address_).approve(pairsAddress_, amount0_);
            ERC20(token1Address_).approve(pairsAddress_, amount1_);
            VZPairs(pairsAddress_).deposit(token0Address_, 0, amount0_);
            VZPairs(pairsAddress_).deposit(token1Address_, 0, amount1_);
            VZPairs(pairsAddress_).initialize(pair, address(this));
        }
    }

    function removeLiquidity(address payable pairAddress_) public {
        uint256 liquidity = VZPairs(pairAddress_).balanceOf(address(this), id);
        VZPairs(pairAddress_).transfer(pairAddress_, id, liquidity);
        VZPairs(payable(pairAddress_)).burn(pair, address(this));
    }

    receive() external payable {}
}

contract Flashloaner {
    error InsufficientFlashLoanAmount();

    uint256 expectedLoanAmount;

    uint256 immutable id;

    VZPairs.PoolKey pair;

    constructor(uint256 ID, VZPairs.PoolKey memory _pair) payable {
        id = ID;
        pair = _pair;
    }

    function flashloan(
        address pairsAddress,
        uint256 amount0Out,
        uint256 amount1Out,
        address tokenAddress
    ) public {
        if (amount0Out > 0) {
            expectedLoanAmount = amount0Out;
        }
        if (amount1Out > 0) {
            expectedLoanAmount = amount1Out;
        }

        VZPairs(payable(pairsAddress)).swap(
            pair, amount0Out, amount1Out, address(this), abi.encode(tokenAddress)
        );
    }

    function vzCall(uint256, address, uint256, uint256, bytes calldata data) public {
        address tokenAddress = abi.decode(data, (address));
        uint256 balance = ERC20(tokenAddress).balanceOf(address(this));

        if (balance < expectedLoanAmount) revert InsufficientFlashLoanAmount();

        ERC20(tokenAddress).approve(msg.sender, balance);

        VZPairs(payable(msg.sender)).deposit(pair.token0, 0, balance);
    }
}

/// @dev A library for handling binary fixed point numbers (https://en.wikipedia.org/wiki/Q_(number_format)).
/// range: [0, 2**112 - 1]
/// resolution: 1 / 2**112
library UQ112x112 {
    uint224 internal constant Q112 = 2 ** 112;

    /// @dev Encode a uint112 as a UQ112x112.
    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) * Q112; // never overflows
    }

    /// @dev Divide a UQ112x112 by a uint112, returning a UQ112x112.
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}
