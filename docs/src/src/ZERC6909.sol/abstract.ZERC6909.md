# ZERC6909
[Git Source](https://github.com/z0r0z/ZAMM/blob/c21fc3c66faff16115f1a70cca4055641603c62b/src/ZERC6909.sol)

**Author:**
Modified from Solady (https://github.com/vectorized/solady/blob/main/src/tokens/ERC6909.sol)

Highly optimized ERC6909 implementation for ZAMM.


## State Variables
### TRANSFER_EVENT_SIGNATURE

```solidity
uint256 constant TRANSFER_EVENT_SIGNATURE =
    0x1b3d7edb2e9c0b0e7c525b20aaaef0f5940d2ed71663c7d39266ecafac728859;
```


### OPERATOR_SET_EVENT_SIGNATURE

```solidity
uint256 constant OPERATOR_SET_EVENT_SIGNATURE =
    0xceb576d9f15e4e200fdb5096d64d5dfd667e16def20c1eefd14256d8e3faa267;
```


### APPROVAL_EVENT_SIGNATURE

```solidity
uint256 constant APPROVAL_EVENT_SIGNATURE =
    0xb3fd5071835887567a0671151121894ddccc2842f1d10bedad13e0d17cace9a7;
```


### ERC6909_MASTER_SLOT_SEED

```solidity
uint256 constant ERC6909_MASTER_SLOT_SEED = 0xedcaa89a82293940;
```


## Functions
### balanceOf


```solidity
function balanceOf(address owner, uint256 id) public view returns (uint256 amount);
```

### allowance


```solidity
function allowance(address owner, address spender, uint256 id)
    public
    view
    returns (uint256 amount);
```

### isOperator


```solidity
function isOperator(address owner, address spender) public view returns (bool status);
```

### transfer


```solidity
function transfer(address to, uint256 id, uint256 amount) public returns (bool);
```

### transferFrom


```solidity
function transferFrom(address from, address to, uint256 id, uint256 amount) public returns (bool);
```

### approve


```solidity
function approve(address spender, uint256 id, uint256 amount) public returns (bool);
```

### setOperator


```solidity
function setOperator(address operator, bool approved) public returns (bool);
```

### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId) public pure returns (bool result);
```

### _initMint


```solidity
function _initMint(address to, uint256 id, uint256 amount) internal;
```

### _mint


```solidity
function _mint(address to, uint256 id, uint256 amount) internal;
```

### _burn


```solidity
function _burn(uint256 id, uint256 amount) internal;
```

