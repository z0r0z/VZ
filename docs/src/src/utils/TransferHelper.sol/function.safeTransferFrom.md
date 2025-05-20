# safeTransferFrom
[Git Source](https://github.com/zammdefi/ZAMM/blob/acf5c5bb2c446e0854e0315d682019d8a2d87e22/src/utils/TransferHelper.sol)

*Sends `amount` of ERC20 `token` from caller to `this`.
Reverts upon failure.
The caller account must have at least `amount` approved for
the current contract to manage.*


```solidity
function safeTransferFrom(address token, uint256 amount);
```

