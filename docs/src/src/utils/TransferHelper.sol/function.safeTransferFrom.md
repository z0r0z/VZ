# safeTransferFrom
[Git Source](https://github.com/z0r0z/ZAMM/blob/bdf5b34ab60ecc6ca2f3ed346976aedaef3e6d12/src/utils/TransferHelper.sol)

*Sends `amount` of ERC20 `token` from caller to `this`.
Reverts upon failure.
The caller account must have at least `amount` approved for
the current contract to manage.*


```solidity
function safeTransferFrom(address token, uint256 amount);
```

