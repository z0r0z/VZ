# safeTransferFrom
[Git Source](https://github.com/z0r0z/VZ/blob/7887795a7d796c3e39a2f68a5f449bf3715c5df3/src/utils/TransferHelper.sol)

*Sends `amount` of ERC20 `token` from caller to `this`.
Reverts upon failure.
The caller account must have at least `amount` approved for
the current contract to manage.*


```solidity
function safeTransferFrom(address token, uint256 amount);
```

