# IZAMMHook
[Git Source](https://github.com/zammdefi/ZAMM/blob/a16fe98b0b7a92f7973a9fafc3de78cf238deec1/src/ZAMM.sol)


## Functions
### beforeAction

*Optional pre-swap / pre-mint / pre-burn call.
May revert or return a feeBps override (0 = keep as-is).*


```solidity
function beforeAction(bytes4 sig, uint256 poolId, address sender, bytes calldata data)
    external
    returns (uint256 feeBps);
```

### afterAction

*Runs after reserves committed.*


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

