# safeTransferFrom
[Git Source](https://github.com/z0r0z/ZAMM/blob/c21fc3c66faff16115f1a70cca4055641603c62b/src/utils/TransferHelper.sol)

*Sends `amount` of ERC20 `token` from caller to `this`.
Reverts upon failure.
The caller account must have at least `amount` approved for
the current contract to manage.*


```solidity
function safeTransferFrom(address token, uint256 amount);
```

