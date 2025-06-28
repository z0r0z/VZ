# IZAMMHook
[Git Source](https://github.com/zammdefi/ZAMM/blob/01418cf0888a2a8e3cc999c814fa483ce70fd973/src/ZAMM.sol)


## Functions
### beforeAction


```solidity
function beforeAction(bytes4 sig, uint256 poolId, address sender, bytes calldata data)
    external
    returns (uint256 feeBps);
```

### afterAction


```solidity
function afterAction(
    bytes4 sig,
    uint256 poolId,
    address sender,
    int256 d0,
    int256 d1,
    int256 dLiq,
    bytes calldata data
) external;
```

