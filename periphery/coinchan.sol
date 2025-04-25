// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

struct PoolKey {
    uint256 id0;
    uint256 id1;
    address token0;
    address token1;
    uint96 swapFee;
}

address constant COINS = 0x0000000000009710cd229bF635c4500029651eE8;
IZAMM constant ZAMM = IZAMM(0x0000000000009994A7A9A6Ec18E09EbA245E8410);

contract coinchan {
    uint256[] public coins;

    mapping(uint256 coinId => Lockup) public lockups;

    struct Lockup {
        address owner;     
        uint40 creation; 
        uint48 unlock;    
        bool vesting;
        uint96 swapFee; 
        uint256 claimed;
    }

    constructor() payable {
        ICOINS(COINS).setOperator(address(ZAMM), true);
    }

    // creator is owner of token minting and URI updates as well as both supplies

    function make(
        string calldata name, 
        string calldata symbol,
        string calldata tokenURI,
        uint256 poolSupply,
        uint256 ownerSupply,
        uint96 swapFee,
        address owner
    ) public payable returns (uint256 coinId, uint256 amount0, uint256 amount1, uint256 liquidity) {
        unchecked {
            coinId = _predictId(name, symbol);
            coins.push(coinId);
            ICOINS(COINS).create(name, symbol, tokenURI, address(this), poolSupply + ownerSupply);
            if (owner != address(0)) {
                ICOINS(COINS).transferOwnership(coinId, owner);
                if (ownerSupply != 0) ICOINS(COINS).transfer(owner, coinId, ownerSupply);
            }
            if (poolSupply != 0) 
                (amount0, amount1, liquidity) = ZAMM.addLiquidity{value: msg.value}
                    (PoolKey(0, coinId, address(0), COINS, swapFee), msg.value, poolSupply, 0, 0, owner, block.timestamp);
        }
    }

    // creator holds creator supply and the pool supply is locked inside ZAMM for creator until unlock (or vested)
    event Locked(uint256 indexed coinId, address indexed creator, uint256 liquidity, uint256 unlock, bool vesting);

    function makeLocked(
        string calldata name, 
        string calldata symbol,
        string calldata tokenURI,
        uint256 poolSupply,
        uint256 creatorSupply,
        uint96 swapFee,
        address creator,
        uint256 _unlock,
        bool vesting
    ) public payable returns (uint256 coinId, uint256 amount0, uint256 amount1, uint256 liquidity) {
        unchecked {
            coinId = _predictId(name, symbol);
            coins.push(coinId);
            ICOINS(COINS).create(name, symbol, tokenURI, address(this), poolSupply + creatorSupply);
            if (creatorSupply != 0) ICOINS(COINS).transfer(creator, coinId, creatorSupply);
            ICOINS(COINS).transferOwnership(coinId, address(0));
            (amount0, amount1, liquidity) = ZAMM.addLiquidity{value: msg.value}
                (PoolKey(0, coinId, address(0), COINS, swapFee), msg.value, poolSupply, 0, 0, address(this), block.timestamp);
            lockups[coinId] = Lockup(creator, uint40(block.timestamp), uint48(_unlock), vesting, swapFee, 0);
            emit Locked(coinId, creator, liquidity, _unlock, vesting);
        }
    }
    
    error Pending();
    error Unauthorized();
    error NothingToVest();

    function claimVested(uint256 coinId) public {
        Lockup storage lock = lockups[coinId];
        require(msg.sender == lock.owner, Unauthorized());

        PoolKey memory key;
        key.id1 = coinId;
        key.token1 = COINS;
        key.swapFee = lock.swapFee;

        uint256 poolId = _computePoolId(key);
        uint256 currentBalance = ZAMM.balanceOf(address(this), poolId);
        require(currentBalance != 0, NothingToVest());

        // if unlock time is reached, transfer and clear lockup
        if (block.timestamp >= lock.unlock) {
            ZAMM.transfer(msg.sender, poolId, currentBalance);
            delete lockups[coinId];
            return;
        }

        // before unlock time, only vesting may be claimed
        require(lock.vesting, Pending());

        unchecked {
            // compute vesting on a linear schedule
            uint256 totalDuration = lock.unlock - lock.creation;
            uint256 elapsed = block.timestamp - lock.creation;
            // originalLocked represents the total locked tokens at creation:
            // the sum of remaining tokens and already claimed tokens
            uint256 originalLocked = currentBalance + lock.claimed;
            uint256 totalVested = originalLocked * elapsed / totalDuration;
            require(totalVested >= lock.claimed, NothingToVest());
            uint256 claimable = totalVested - lock.claimed;
            lock.claimed += claimable;
            ZAMM.transfer(msg.sender, poolId, claimable);
        }
    }

    function getVestableAmount(uint256 coinId) public view returns (uint256) {
        unchecked {
            Lockup memory lock = lockups[coinId];
            if (lock.owner == address(0)) return 0;

            PoolKey memory key;
            key.id1 = coinId;
            key.token1 = COINS;
            key.swapFee = lock.swapFee;

            uint256 poolId = _computePoolId(key);
            uint256 currentBalance = ZAMM.balanceOf(address(this), poolId);

            if (currentBalance == 0) return 0;
            if (block.timestamp >= lock.unlock) return currentBalance;
            if (!lock.vesting) return 0;

            uint256 totalVestingDuration = lock.unlock - lock.creation;
            uint256 timeElapsed = block.timestamp - lock.creation;
            uint256 originalLocked = currentBalance + lock.claimed;
            uint256 totalVested = originalLocked * timeElapsed / totalVestingDuration;

            return totalVested > lock.claimed ? totalVested - lock.claimed : 0;
        }
    }

    // creator holds supply and lp

    function makeHold(
        string calldata name, 
        string calldata symbol,
        string calldata tokenURI,
        uint256 poolSupply,
        uint256 creatorSupply,
        uint96 swapFee,
        address creator
    ) public payable returns (uint256 coinId, uint256 amount0, uint256 amount1, uint256 liquidity) {
        unchecked {
            coinId = _predictId(name, symbol);
            coins.push(coinId);
            ICOINS(COINS).create(name, symbol, tokenURI, address(this), poolSupply + creatorSupply);
            if (creatorSupply != 0) ICOINS(COINS).transfer(creator, coinId, creatorSupply);
            ICOINS(COINS).transferOwnership(coinId, address(0));
            if (poolSupply != 0) 
                (amount0, amount1, liquidity) = ZAMM.addLiquidity{value: msg.value}
                    (PoolKey(0, coinId, address(0), COINS, swapFee), msg.value, poolSupply, 0, 0, creator, block.timestamp);
        }
    }

    // airdrop

    error InvalidArrays();

    function airdrop(uint256 coinId, address[] calldata tos, uint256[] calldata amounts, uint256 sum) public {
        require(tos.length == amounts.length, InvalidArrays());
        // optimization note: do ensure sum is equal to total of amounts if doing pull
        if (sum != 0) ICOINS(COINS).transferFrom(msg.sender, address(this), coinId, sum);
        for (uint256 i; i != tos.length; ++i) ICOINS(COINS).transfer(tos[i], coinId, amounts[i]);
    }

    // helpers

    function _predictId(string calldata name, string calldata symbol) internal pure returns (uint256 predicted) {
        bytes32 salt = keccak256(abi.encodePacked(name, COINS, symbol));
        predicted = uint256(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            COINS,
            salt,
            bytes32(0x6594461b4ce3b23f6cbdcdcf50388d5f444bf59a82f6e868dfd5ef2bfa13f6d4)
        )))));
    }

    function _computePoolId(PoolKey memory poolKey) internal pure returns (uint256 poolId) {
        assembly ("memory-safe") {
            poolId := keccak256(poolKey, 0xa0)
        }
    }

    function multicall(bytes[] calldata data) public payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i; i != data.length; ++i) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(result, 0x20), mload(result))
                }
            }
            results[i] = result;
        }
    }

    function getCoins(uint256 start, uint256 finish) public view returns (uint256[] memory) {
        unchecked {
            uint256 total = coins.length;
            if (start >= total) return new uint256[](0);       
            if (finish >= total) finish = total - 1;             
            if (start > finish) return new uint256[](0);         

            uint256 size = finish - start + 1;
            uint256[] memory result = new uint256[](size);
            for (uint256 i; i != size; ++i) result[i] = coins[start + i];
            return result;
        }
    }

    function getCoinsCount() public view returns (uint256) {
        return coins.length;
    }
}

interface IZAMM {
    function addLiquidity(
        PoolKey calldata poolKey,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amount0, uint256 amount1, uint256 liquidity);
    function transfer(address, uint256, uint256) external returns (bool);
    function balanceOf(address, uint256) external view returns (uint256);
}

interface ICOINS {
    function transferOwnership(uint256, address) external;
    function setOperator(address, bool) external returns (bool);
    function transfer(address, uint256, uint256) external returns (bool);
    function transferFrom(address, address, uint256, uint256) external returns (bool);
    function create(string calldata, string calldata, string calldata, address, uint256) external;
}