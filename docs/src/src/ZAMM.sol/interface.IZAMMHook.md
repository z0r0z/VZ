# IZAMMHook
[Git Source](https://github.com/zammdefi/ZAMM/blob/b1f7385d35195895d467c8f3f1111586be121980/src/ZAMM.sol)


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

