# safeTransferFrom
[Git Source](https://github.com/z0r0z/VZ/blob/5de7aedefa6cbedd22db6447d26ada8fcbe1d187/src/utils/TransferHelper.sol)

*Sends `amount` of ERC20 `token` from caller to `this`.
Reverts upon failure.
The caller account must have at least `amount` approved for
the current contract to manage.*


```solidity
function safeTransferFrom(address token, uint256 amount);
```

