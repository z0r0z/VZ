# ZAMM
[Git Source](https://github.com/z0r0z/ZAMM/blob/bdf5b34ab60ecc6ca2f3ed346976aedaef3e6d12/src/ZAMM.sol)

**Inherits:**
[ZERC6909](/src/ZERC6909.sol/abstract.ZERC6909.md)


## State Variables
### MINIMUM_LIQUIDITY

```solidity
uint256 constant MINIMUM_LIQUIDITY = 1000;
```


### MAX_FEE

```solidity
uint256 constant MAX_FEE = 10000;
```


### pools

```solidity
mapping(uint256 poolId => Pool) public pools;
```


## Functions
### lock


```solidity
modifier lock();
```

### _safeTransfer


```solidity
function _safeTransfer(address token, address to, uint256 id, uint256 amount) internal;
```

### _safeTransferFrom


```solidity
function _safeTransferFrom(address token, uint256 id, uint256 amount) internal;
```

### constructor


```solidity
constructor() payable;
```

### _update


```solidity
function _update(
    Pool storage pool,
    uint256 poolId,
    uint256 balance0,
    uint256 balance1,
    uint112 reserve0,
    uint112 reserve1
) internal;
```

### _mintFee


```solidity
function _mintFee(Pool storage pool, uint256 poolId, uint112 reserve0, uint112 reserve1)
    internal
    returns (bool feeOn);
```

### swapExactIn


```solidity
function swapExactIn(
    PoolKey calldata poolKey,
    uint256 amountIn,
    uint256 amountOutMin,
    bool zeroForOne,
    address to,
    uint256 deadline
) public payable lock returns (uint256 amountOut);
```

### swapExactOut


```solidity
function swapExactOut(
    PoolKey calldata poolKey,
    uint256 amountOut,
    uint256 amountInMax,
    bool zeroForOne,
    address to,
    uint256 deadline
) public payable lock returns (uint256 amountIn);
```

### swap


```solidity
function swap(
    PoolKey calldata poolKey,
    uint256 amount0Out,
    uint256 amount1Out,
    address to,
    bytes calldata data
) public lock;
```

### addLiquidity


```solidity
function addLiquidity(
    PoolKey calldata poolKey,
    uint256 amount0Desired,
    uint256 amount1Desired,
    uint256 amount0Min,
    uint256 amount1Min,
    address to,
    uint256 deadline
) public payable lock returns (uint256 amount0, uint256 amount1, uint256 liquidity);
```

### removeLiquidity


```solidity
function removeLiquidity(
    PoolKey calldata poolKey,
    uint256 liquidity,
    uint256 amount0Min,
    uint256 amount1Min,
    address to,
    uint256 deadline
) public lock returns (uint256 amount0, uint256 amount1);
```

### make


```solidity
function make(address maker, uint256 supply, string calldata uri) public returns (uint256 coinId);
```

### makeLiquid


```solidity
function makeLiquid(
    address maker,
    address liqTo,
    uint256 mkrAmt,
    uint256 liqAmt,
    uint256 swapFee,
    string calldata uri
) public payable returns (uint256 coinId, uint256 poolId, uint256 liquidity);
```

### receive


```solidity
receive() external payable;
```

### deposit


```solidity
function deposit(address token, uint256 id, uint256 amount) public payable;
```

### _getTransientBalance


```solidity
function _getTransientBalance(address token, uint256 id) internal returns (uint256 bal);
```

### _useTransientBalance


```solidity
function _useTransientBalance(address token, uint256 id, uint256 amount)
    internal
    returns (bool credited);
```

### recoverTransientBalance


```solidity
function recoverTransientBalance(address token, uint256 id, address to)
    public
    lock
    returns (uint256 amount);
```

### _getPoolId


```solidity
function _getPoolId(PoolKey calldata poolKey) internal pure returns (uint256 poolId);
```

### _getAmountOut


```solidity
function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, uint96 swapFee)
    internal
    pure
    returns (uint256 amountOut);
```

### _getAmountIn


```solidity
function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint96 swapFee)
    internal
    pure
    returns (uint256 amountIn);
```

### setFeeTo


```solidity
function setFeeTo(address feeTo) public payable;
```

### setFeeToSetter


```solidity
function setFeeToSetter(address feeToSetter) public payable;
```

### multicall


```solidity
function multicall(bytes[] calldata data) public returns (bytes[] memory results);
```

### fallback


```solidity
fallback() external payable;
```

## Events
### Mint

```solidity
event Mint(uint256 indexed poolId, address indexed sender, uint256 amount0, uint256 amount1);
```

### Burn

```solidity
event Burn(
    uint256 indexed poolId,
    address indexed sender,
    uint256 amount0,
    uint256 amount1,
    address indexed to
);
```

### Swap

```solidity
event Swap(
    uint256 indexed poolId,
    address indexed sender,
    uint256 amount0In,
    uint256 amount1In,
    uint256 amount0Out,
    uint256 amount1Out,
    address indexed to
);
```

### Sync

```solidity
event Sync(uint256 indexed poolId, uint112 reserve0, uint112 reserve1);
```

### URI

```solidity
event URI(string uri, uint256 indexed coinId);
```

## Errors
### Reentrancy

```solidity
error Reentrancy();
```

### Overflow

```solidity
error Overflow();
```

### Expired

```solidity
error Expired();
```

### InvalidMsgVal

```solidity
error InvalidMsgVal();
```

### InsufficientLiquidity

```solidity
error InsufficientLiquidity();
```

### InsufficientInputAmount

```solidity
error InsufficientInputAmount();
```

### InsufficientOutputAmount

```solidity
error InsufficientOutputAmount();
```

### K

```solidity
error K();
```

### InvalidSwapFee

```solidity
error InvalidSwapFee();
```

### InvalidPoolTokens

```solidity
error InvalidPoolTokens();
```

### InsufficientLiquidityMinted

```solidity
error InsufficientLiquidityMinted();
```

### Unauthorized

```solidity
error Unauthorized();
```

## Structs
### PoolKey

```solidity
struct PoolKey {
    uint256 id0;
    uint256 id1;
    address token0;
    address token1;
    uint96 swapFee;
}
```

### Pool

```solidity
struct Pool {
    uint112 reserve0;
    uint112 reserve1;
    uint32 blockTimestampLast;
    uint256 price0CumulativeLast;
    uint256 price1CumulativeLast;
    uint256 kLast;
    uint256 supply;
}
```

