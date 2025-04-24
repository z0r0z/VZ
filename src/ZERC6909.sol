// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @notice Highly optimized ERC6909 implementation for ZAMM.
/// @author Modified from Solady (https://github.com/vectorized/solady/blob/main/src/tokens/ERC6909.sol)
/// @dev For a better understanding of optimization choices and full documentation, consult Solady ERC6909.
abstract contract ZERC6909 {
    uint256 constant TRANSFER_EVENT_SIGNATURE =
        0x1b3d7edb2e9c0b0e7c525b20aaaef0f5940d2ed71663c7d39266ecafac728859;
    uint256 constant OPERATOR_SET_EVENT_SIGNATURE =
        0xceb576d9f15e4e200fdb5096d64d5dfd667e16def20c1eefd14256d8e3faa267;
    uint256 constant APPROVAL_EVENT_SIGNATURE =
        0xb3fd5071835887567a0671151121894ddccc2842f1d10bedad13e0d17cace9a7;
    uint256 constant ERC6909_MASTER_SLOT_SEED = 0xedcaa89a82293940;

    function balanceOf(address owner, uint256 id) public view returns (uint256 amount) {
        assembly ("memory-safe") {
            mstore(0x20, ERC6909_MASTER_SLOT_SEED)
            mstore(0x14, owner)
            mstore(0x00, id)
            amount := sload(keccak256(0x00, 0x40))
        }
    }

    function allowance(address owner, address spender, uint256 id)
        public
        view
        returns (uint256 amount)
    {
        assembly ("memory-safe") {
            mstore(0x34, ERC6909_MASTER_SLOT_SEED)
            mstore(0x28, owner)
            mstore(0x14, spender)
            mstore(0x00, id)
            amount := sload(keccak256(0x00, 0x54))
            mstore(0x34, 0x00)
        }
    }

    function isOperator(address owner, address spender) public view returns (bool status) {
        assembly ("memory-safe") {
            mstore(0x20, ERC6909_MASTER_SLOT_SEED)
            mstore(0x14, owner)
            mstore(0x00, spender)
            status := sload(keccak256(0x0c, 0x34))
        }
    }

    function transfer(address to, uint256 id, uint256 amount) public returns (bool) {
        assembly ("memory-safe") {
            mstore(0x20, ERC6909_MASTER_SLOT_SEED)
            mstore(0x14, caller())
            mstore(0x00, id)
            let fromBalanceSlot := keccak256(0x00, 0x40)
            let fromBalance := sload(fromBalanceSlot)
            if gt(amount, fromBalance) {
                mstore(0x00, 0xf4d678b8)
                revert(0x1c, 0x04)
            }
            sstore(fromBalanceSlot, sub(fromBalance, amount))
            mstore(0x14, to)
            mstore(0x00, id)
            let toBalanceSlot := keccak256(0x00, 0x40)
            let toBalanceBefore := sload(toBalanceSlot)
            let toBalanceAfter := add(toBalanceBefore, amount)
            if lt(toBalanceAfter, toBalanceBefore) {
                mstore(0x00, 0x89560ca1)
                revert(0x1c, 0x04)
            }
            sstore(toBalanceSlot, toBalanceAfter)
            mstore(0x00, caller())
            mstore(0x20, amount)
            log4(0x00, 0x40, TRANSFER_EVENT_SIGNATURE, caller(), shr(96, shl(96, to)), id)
            mstore(0x00, 1)
            return(0x00, 0x20)
        }
    }

    function transferFrom(address from, address to, uint256 id, uint256 amount)
        public
        returns (bool)
    {
        assembly ("memory-safe") {
            mstore(0x34, ERC6909_MASTER_SLOT_SEED)
            mstore(0x28, from)
            mstore(0x14, caller())
            if iszero(sload(keccak256(0x20, 0x34))) {
                mstore(0x00, id)
                let allowanceSlot := keccak256(0x00, 0x54)
                let allowance_ := sload(allowanceSlot)
                if add(allowance_, 1) {
                    if gt(amount, allowance_) {
                        mstore(0x00, 0xdeda9030)
                        revert(0x1c, 0x04)
                    }
                    sstore(allowanceSlot, sub(allowance_, amount))
                }
            }
            mstore(0x14, id)
            let fromBalanceSlot := keccak256(0x14, 0x40)
            let fromBalance := sload(fromBalanceSlot)
            if gt(amount, fromBalance) {
                mstore(0x00, 0xf4d678b8)
                revert(0x1c, 0x04)
            }
            sstore(fromBalanceSlot, sub(fromBalance, amount))
            mstore(0x28, to)
            mstore(0x14, id)
            let toBalanceSlot := keccak256(0x14, 0x40)
            let toBalanceBefore := sload(toBalanceSlot)
            let toBalanceAfter := add(toBalanceBefore, amount)
            if lt(toBalanceAfter, toBalanceBefore) {
                mstore(0x00, 0x89560ca1)
                revert(0x1c, 0x04)
            }
            sstore(toBalanceSlot, toBalanceAfter)
            mstore(0x00, caller())
            mstore(0x20, amount)
            // forgefmt: disable-next-line
            log4(0x00, 0x40, TRANSFER_EVENT_SIGNATURE, shr(96, shl(96, from)), shr(96, shl(96, to)), id)
            mstore(0x34, 0x00)
            mstore(0x00, 1)
            return(0x00, 0x20)
        }
    }

    function approve(address spender, uint256 id, uint256 amount) public returns (bool) {
        assembly ("memory-safe") {
            mstore(0x34, ERC6909_MASTER_SLOT_SEED)
            mstore(0x28, caller())
            mstore(0x14, spender)
            mstore(0x00, id)
            sstore(keccak256(0x00, 0x54), amount)
            mstore(0x00, amount)
            log4(0x00, 0x20, APPROVAL_EVENT_SIGNATURE, caller(), shr(96, mload(0x20)), id)
            mstore(0x34, 0x00)
            mstore(0x00, 1)
            return(0x00, 0x20)
        }
    }

    function setOperator(address operator, bool approved) public returns (bool result) {
        assembly ("memory-safe") {
            let approvedCleaned := iszero(iszero(approved))
            mstore(0x20, ERC6909_MASTER_SLOT_SEED)
            mstore(0x14, caller())
            mstore(0x00, operator)
            sstore(keccak256(0x0c, 0x34), approvedCleaned)
            mstore(0x20, approvedCleaned)
            log3(0x20, 0x20, OPERATOR_SET_EVENT_SIGNATURE, caller(), shr(96, mload(0x0c)))
            result := 1
        }
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool result) {
        assembly ("memory-safe") {
            let s := shr(224, interfaceId)
            result := or(eq(s, 0x01ffc9a7), eq(s, 0x0f632fb3))
        }
    }

    function _initMint(address to, uint256 id, uint256 amount) internal {
        assembly ("memory-safe") {
            mstore(0x20, ERC6909_MASTER_SLOT_SEED)
            mstore(0x14, to)
            mstore(0x00, id)
            sstore(keccak256(0x00, 0x40), amount)
            mstore(0x00, caller())
            mstore(0x20, amount)
            log4(0x00, 0x40, TRANSFER_EVENT_SIGNATURE, 0, shr(96, shl(96, to)), id)
        }
    }

    function _mint(address to, uint256 id, uint256 amount) internal {
        assembly ("memory-safe") {
            mstore(0x20, ERC6909_MASTER_SLOT_SEED)
            mstore(0x14, to)
            mstore(0x00, id)
            let toBalanceSlot := keccak256(0x00, 0x40)
            let toBalanceBefore := sload(toBalanceSlot)
            let toBalanceAfter := add(toBalanceBefore, amount)
            if lt(toBalanceAfter, toBalanceBefore) {
                mstore(0x00, 0x89560ca1)
                revert(0x1c, 0x04)
            }
            sstore(toBalanceSlot, toBalanceAfter)
            mstore(0x00, caller())
            mstore(0x20, amount)
            log4(0x00, 0x40, TRANSFER_EVENT_SIGNATURE, 0, shr(96, shl(96, to)), id)
        }
    }

    function _burn(uint256 id, uint256 amount) internal {
        assembly ("memory-safe") {
            mstore(0x20, ERC6909_MASTER_SLOT_SEED)
            mstore(0x14, caller())
            mstore(0x00, id)
            let fromBalanceSlot := keccak256(0x00, 0x40)
            let fromBalance := sload(fromBalanceSlot)
            if gt(amount, fromBalance) {
                mstore(0x00, 0xf4d678b8)
                revert(0x1c, 0x04)
            }
            sstore(fromBalanceSlot, sub(fromBalance, amount))
            mstore(0x00, caller())
            mstore(0x20, amount)
            log4(0x00, 0x40, TRANSFER_EVENT_SIGNATURE, shr(96, shl(96, caller())), 0, id)
        }
    }
}
