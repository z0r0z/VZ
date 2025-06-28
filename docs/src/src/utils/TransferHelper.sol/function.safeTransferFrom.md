# safeTransferFrom
[Git Source](https://github.com/zammdefi/ZAMM/blob/b1f7385d35195895d467c8f3f1111586be121980/src/utils/TransferHelper.sol)

*Sends `amount` of ERC20 `token` from `from` to `to`.
Reverts upon failure.
The `from` account must have at least `amount` approved for
the current contract to manage.*


```solidity
function safeTransferFrom(address token, address from, address to, uint256 amount);
```

