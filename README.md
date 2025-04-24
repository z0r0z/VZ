# ZAMM

Contemporary Uniswap V2 (VZ) Singleton. By [z0r0z](https://x.com/z0r0zzz).

Deployed efficiently to every chain at [`0x0000000000009994A7A9A6Ec18E09EbA245E8410`](https://contractscan.xyz/contract/0x0000000000009994A7A9A6Ec18E09EbA245E8410).

Changes are meant to cause little disruption to the familiar and battle-tested [Uniswap V2 core](https://github.com/Uniswap/v2-core). While also introducing efficiency and optimized patterns the public has otherwise made through opinionated forks. VZ should consolidate, reform and optimize these variations as much as possible to represent a simple and useable VZ.

Changes include the following:

✵ ETH pool support (`address(0)`)

✵ Built-in router logic (easy pz)

✵ ERC6909 mulitoken swap support

✵ Native tokenization methods

✵ Flash accounting for gas

✵ Custom fee tiers (up to 100%)

✵ Adapted Syntax (e.g. safemath)

✵ Latest Solidity Compiler (0.8.29)

✵ *Solady* most of the things *etc.*

Note: The biggest design difference is that the VZ pairs singleton expects a `pull` pattern of `transferFrom` rather than direct transfers. The `deposit()` function should be called by external routers or locally via `multicall()`. Convenience functions are also provided such as `addLiquidity`, `removeLiquidity`, `swapExactIn` and `swapExactOut` to replicate the classic V2 router dev experience. Enjoy!

## Getting Started

Run: `curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup`

Build the foundry project with `forge build`. Run tests with `forge test`. Measure gas with `forge snapshot`. Format with `forge fmt`.

## Disclaimer

*These smart contracts and testing suite are being provided as is. No guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of anything provided herein or through related user interfaces. This repository and related code have not been audited and as such there can be no assurance anything will work as intended, and users may experience delays, failures, errors, omissions, loss of transmitted information or loss of funds. The creators are not liable for any of the foregoing. Users should proceed with caution and use at their own risk.*

## License

See [LICENSE](./LICENSE) for more details.
