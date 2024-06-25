// SPDX-License-Identifier: VPL
pragma solidity 0.8.26;

abstract contract VZERC20 {
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed from, address indexed to, uint256 amount);

    error TotalSupplyOverflow();
    error InsufficientBalance();
    error InsufficientAllowance();

    uint256 constant _BALANCE_SLOT_SEED = 0x87a211a2;
    uint256 constant _ALLOWANCE_SLOT_SEED = 0x7f5e9f20;
    uint256 constant _TOTAL_SUPPLY_SLOT = 0x05345cdf77eb68f44c;
    uint256 constant _TRANSFER_EVENT_SIGNATURE =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    uint256 constant _APPROVAL_EVENT_SIGNATURE =
        0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;

    string public constant name = "VZ LP";
    string public constant symbol = "VZLP";
    uint256 public constant decimals = 18;

    function totalSupply() public view virtual returns (uint256 result) {
        assembly ("memory-safe") {
            result := sload(_TOTAL_SUPPLY_SLOT)
        }
    }

    function balanceOf(address owner) public view virtual returns (uint256 result) {
        assembly ("memory-safe") {
            mstore(0x0c, _BALANCE_SLOT_SEED)
            mstore(0x00, owner)
            result := sload(keccak256(0x0c, 0x20))
        }
    }

    function allowance(address owner, address spender)
        public
        view
        virtual
        returns (uint256 result)
    {
        assembly ("memory-safe") {
            mstore(0x20, spender)
            mstore(0x0c, _ALLOWANCE_SLOT_SEED)
            mstore(0x00, owner)
            result := sload(keccak256(0x0c, 0x34))
        }
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        assembly ("memory-safe") {
            mstore(0x20, spender)
            mstore(0x0c, _ALLOWANCE_SLOT_SEED)
            mstore(0x00, caller())
            sstore(keccak256(0x0c, 0x34), amount)
            mstore(0x00, amount)
            log3(0x00, 0x20, _APPROVAL_EVENT_SIGNATURE, caller(), shr(96, mload(0x2c)))
        }
        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        assembly ("memory-safe") {
            mstore(0x0c, _BALANCE_SLOT_SEED)
            mstore(0x00, caller())
            let fromBalanceSlot := keccak256(0x0c, 0x20)
            let fromBalance := sload(fromBalanceSlot)
            if gt(amount, fromBalance) {
                mstore(0x00, 0xf4d678b8) // `InsufficientBalance()`.
                revert(0x1c, 0x04)
            }
            sstore(fromBalanceSlot, sub(fromBalance, amount))
            mstore(0x00, to)
            let toBalanceSlot := keccak256(0x0c, 0x20)
            sstore(toBalanceSlot, add(sload(toBalanceSlot), amount))
            mstore(0x20, amount)
            log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE, caller(), shr(96, mload(0x0c)))
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        assembly ("memory-safe") {
            let from_ := shl(96, from)
            mstore(0x20, caller())
            mstore(0x0c, or(from_, _ALLOWANCE_SLOT_SEED))
            let allowanceSlot := keccak256(0x0c, 0x34)
            let allowance_ := sload(allowanceSlot)
            if add(allowance_, 1) {
                if gt(amount, allowance_) {
                    mstore(0x00, 0x13be252b) // `InsufficientAllowance()`.
                    revert(0x1c, 0x04)
                }
                sstore(allowanceSlot, sub(allowance_, amount))
            }
            mstore(0x0c, or(from_, _BALANCE_SLOT_SEED))
            let fromBalanceSlot := keccak256(0x0c, 0x20)
            let fromBalance := sload(fromBalanceSlot)
            if gt(amount, fromBalance) {
                mstore(0x00, 0xf4d678b8) // `InsufficientBalance()`.
                revert(0x1c, 0x04)
            }
            sstore(fromBalanceSlot, sub(fromBalance, amount))
            mstore(0x00, to)
            let toBalanceSlot := keccak256(0x0c, 0x20)
            sstore(toBalanceSlot, add(sload(toBalanceSlot), amount))
            mstore(0x20, amount)
            log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, from_), shr(96, mload(0x0c)))
        }
        return true;
    }

    function _mint(address to, uint256 amount) internal virtual {
        assembly ("memory-safe") {
            let totalSupplyBefore := sload(_TOTAL_SUPPLY_SLOT)
            let totalSupplyAfter := add(totalSupplyBefore, amount)
            if lt(totalSupplyAfter, totalSupplyBefore) {
                mstore(0x00, 0xe5cfe957) // `TotalSupplyOverflow()`.
                revert(0x1c, 0x04)
            }
            sstore(_TOTAL_SUPPLY_SLOT, totalSupplyAfter)
            mstore(0x0c, _BALANCE_SLOT_SEED)
            mstore(0x00, to)
            let toBalanceSlot := keccak256(0x0c, 0x20)
            sstore(toBalanceSlot, add(sload(toBalanceSlot), amount))
            mstore(0x20, amount)
            log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE, 0, shr(96, mload(0x0c)))
        }
    }

    function _burn(address from, uint256 amount) internal virtual {
        assembly ("memory-safe") {
            mstore(0x0c, _BALANCE_SLOT_SEED)
            mstore(0x00, from)
            let fromBalanceSlot := keccak256(0x0c, 0x20)
            let fromBalance := sload(fromBalanceSlot)
            if gt(amount, fromBalance) {
                mstore(0x00, 0xf4d678b8) // `InsufficientBalance()`.
                revert(0x1c, 0x04)
            }
            sstore(fromBalanceSlot, sub(fromBalance, amount))
            sstore(_TOTAL_SUPPLY_SLOT, sub(sload(_TOTAL_SUPPLY_SLOT), amount))
            mstore(0x00, amount)
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, shl(96, from)), 0)
        }
    }
}
