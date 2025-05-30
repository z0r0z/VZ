# safeTransferFrom
[Git Source](https://github.com/zammdefi/ZAMM/blob/a16fe98b0b7a92f7973a9fafc3de78cf238deec1/src/utils/TransferHelper.sol)

*Sends `amount` of ERC20 `token` from `from` to `to`.
Reverts upon failure.
The `from` account must have at least `amount` approved for
the current contract to manage.*


```solidity
function safeTransferFrom(address token, address from, address to, uint256 amount);
```

