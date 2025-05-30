# safeTransferFrom
[Git Source](https://github.com/zammdefi/ZAMM/blob/fa189555585feef833515e20b93171c09b0534a0/src/utils/TransferHelper.sol)

*Sends `amount` of ERC20 `token` from `from` to `to`.
Reverts upon failure.
The `from` account must have at least `amount` approved for
the current contract to manage.*


```solidity
function safeTransferFrom(address token, address from, address to, uint256 amount);
```

