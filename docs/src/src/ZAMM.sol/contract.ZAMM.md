# ZAMM
[Git Source](https://github.com/zammdefi/ZAMM/blob/481ee36d21c44278ddb95f69fd35779cb4598874/src/ZAMM.sol)

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


### FLAG_BEFORE

```solidity
uint256 constant FLAG_BEFORE = 1 << 255;
```


### FLAG_AFTER

```solidity
uint256 constant FLAG_AFTER = 1 << 254;
```


### ADDR_MASK

```solidity
uint256 constant ADDR_MASK = (1 << 160) - 1;
```


### pools

```solidity
mapping(uint256 poolId => Pool) public pools;
```


### coins

```solidity
uint256 coins;
```


### lockups

```solidity
mapping(bytes32 lockHash => uint256 unlockTime) public lockups;
```


### orders

```solidity
mapping(bytes32 orderHash => Order) public orders;
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
function _safeTransferFrom(address token, address from, address to, uint256 id, uint256 amount)
    internal;
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

### _decode


```solidity
function _decode(uint256 v)
    internal
    pure
    returns (uint256 feeBps, address hook, bool pre, bool post);
```

### _postHook


```solidity
function _postHook(
    bytes4 sig,
    uint256 poolId,
    address sender,
    int256 d0,
    int256 d1,
    int256 dLiq,
    bytes memory data,
    address hook
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

### coin


```solidity
function coin(address creator, uint256 supply, string calldata uri)
    public
    returns (uint256 coinId);
```

### lockup


```solidity
function lockup(address token, address to, uint256 id, uint256 amount, uint256 unlockTime)
    public
    payable
    lock
    returns (bytes32 lockHash);
```

### unlock


```solidity
function unlock(address token, address to, uint256 id, uint256 amount, uint256 unlockTime)
    public
    lock;
```

### makeOrder


```solidity
function makeOrder(
    address tokenIn,
    uint256 idIn,
    uint96 amtIn,
    address tokenOut,
    uint256 idOut,
    uint96 amtOut,
    uint56 deadline,
    bool partialFill
) public payable lock returns (bytes32 orderHash);
```

### fillOrder


```solidity
function fillOrder(
    address maker,
    address tokenIn,
    uint256 idIn,
    uint96 amtIn,
    address tokenOut,
    uint256 idOut,
    uint96 amtOut,
    uint56 deadline,
    bool partialFill,
    uint96 fillPart
) public payable lock;
```

### cancelOrder


```solidity
function cancelOrder(
    address tokenIn,
    uint256 idIn,
    uint96 amtIn,
    address tokenOut,
    uint256 idOut,
    uint96 amtOut,
    uint56 deadline,
    bool partialFill
) public lock;
```

### _payOut


```solidity
function _payOut(address token, uint256 id, uint96 amt, address to) internal;
```

### _payIn


```solidity
function _payIn(address token, uint256 id, uint96 amt, address from) internal;
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
function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, uint256 swapFee)
    internal
    pure
    returns (uint256 amountOut);
```

### _getAmountIn


```solidity
function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint256 swapFee)
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

### Lock

```solidity
event Lock(address indexed sender, address indexed to, bytes32 indexed lockHash);
```

### Make

```solidity
event Make(address indexed maker, bytes32 indexed orderHash);
```

### Fill

```solidity
event Fill(address indexed taker, bytes32 indexed orderHash);
```

### Cancel

```solidity
event Cancel(address indexed maker, bytes32 indexed orderHash);
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

### InvalidFeeOrHook

```solidity
error InvalidFeeOrHook();
```

### InvalidPoolTokens

```solidity
error InvalidPoolTokens();
```

### InsufficientLiquidityMinted

```solidity
error InsufficientLiquidityMinted();
```

### Pending

```solidity
error Pending();
```

### BadSize

```solidity
error BadSize();
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
    uint256 feeOrHook;
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

### Order

```solidity
struct Order {
    bool partialFill;
    uint56 deadline;
    uint96 inDone;
    uint96 outDone;
}
```

