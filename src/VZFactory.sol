// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import "./VZPair.sol";

/// @notice Contemporary Uniswap V2 Factory (VZ).
/// @author z0r0z.eth
contract VZFactory {
    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    constructor(address _feeToSetter) payable {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() public view returns (uint256) {
        return allPairs.length;
    }

    error IdenticalAddresses();
    error PairExists();

    function createPair(address tokenA, address tokenB) public payable returns (address pair) {
        if (tokenA == tokenB) revert IdenticalAddresses();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (getPair[token0][token1] != address(0)) revert PairExists();
        pair = address(
            new VZPair{salt: keccak256(abi.encodePacked(token0, token1)), value: msg.value}(
                token0, token1
            )
        );
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // Populate mapping in the reverse direction.
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    error Forbidden();

    function setFeeTo(address _feeTo) public payable {
        if (msg.sender != feeToSetter) revert Forbidden();
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) public payable {
        if (msg.sender != feeToSetter) revert Forbidden();
        feeToSetter = _feeToSetter;
    }
}
