# ZAMM

A Minimal Multitoken AMM. By [z0r0z](https://x.com/z0r0zzz).

## Getting Started

Run: `curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc && foundryup`

Build the foundry project with `forge build`. Run tests with `forge test`. Measure gas with `forge snapshot`. Format with `forge fmt`.

## Security Notes

Independent security researchers have made the following findings which are important to consider when integrating your app or DeFi process with ZAMM core:

> [@danielvf](https://x.com/danielvf): Because `makeLiquid()` does not use a nonce or user-specific storage but relies on `block.timestamp` (as gas-optimization technique), malicious creators could potentially make hidden LP tokens not held in the pool supply. While frontends can detect this and prevent interaction with poisoned pools, smart contracts should not automatically assume the safety of ZAMM native pools without implementing their own checks. A recommended solution is to use a helper contract if trying to interact with native ZAMM coins in a deterministic way, or use offchain services to confirm their safety. 

## Disclaimer

*These smart contracts and testing suite are being provided as is. No guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of anything provided herein or through related user interfaces. This repository and related code have not been audited and as such there can be no assurance anything will work as intended, and users may experience delays, failures, errors, omissions, loss of transmitted information or loss of funds. The creators are not liable for any of the foregoing. Users should proceed with caution and use at their own risk.*

## License

See [LICENSE](./LICENSE) for more details.
