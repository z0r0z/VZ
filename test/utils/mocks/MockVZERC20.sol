// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {VZERC20} from "../../../src/VZERC20.sol";
import {Brutalizer} from "@solady/test/utils/Brutalizer.sol";

/// @dev WARNING! This mock is strictly intended for testing purposes only.
/// Do NOT copy anything here into production code unless you really know what you are doing.
contract MockVZERC20 is VZERC20, Brutalizer {
    function mint(address to, uint256 value) public virtual {
        _mint(_brutalized(to), value);
    }

    function burn(address from, uint256 value) public virtual {
        _burn(_brutalized(from), value);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        return super.transfer(_brutalized(to), amount);
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        return super.transferFrom(_brutalized(from), _brutalized(to), amount);
    }
}
