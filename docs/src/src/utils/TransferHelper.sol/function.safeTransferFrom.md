# safeTransferFrom
[Git Source](https://github.com/zammdefi/ZAMM/blob/01418cf0888a2a8e3cc999c814fa483ce70fd973/src/utils/TransferHelper.sol)

*Sends `amount` of ERC20 `token` from `from` to `to`.
Reverts upon failure.
The `from` account must have at least `amount` approved for
the current contract to manage.*


```solidity
function safeTransferFrom(address token, address from, address to, uint256 amount);
```

