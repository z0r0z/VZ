// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/*──────────────────────────  ZAMMLaunch  ──────────────────────────*/
contract ZAMMLaunch {
    /* ───────── constants ───────── */
    IZAMM constant Z = IZAMM(0x000000000000040470635EB91b7CE4D132D616eD);
    uint56 constant SALE_DURATION = 1 weeks;
    uint256 constant DEFAULT_FEE_BPS = 100; // 1%

    /* ───────── storage ───────── */
    struct Sale {
        address creator;
        uint96 deadlineLast;
        uint256 coinId;
        uint96[] trancheCoins;
        uint96[] tranchePrice;
        uint56[] deadlines;
        uint128 ethRaised;
        uint128 coinsSold;
    }

    mapping(uint256 coinId => Sale) public sales;
    mapping(uint256 coinId => mapping(address user => uint256)) public balances;

    /* ───────── events ───────── */
    event Launch(address indexed creator, uint256 indexed coinId, uint96 saleSupply);
    event Buy(address indexed buyer, uint256 indexed coinId, uint256 ethIn, uint128 coinsOut);
    event Finalize(uint256 indexed coinId, uint256 ethLp, uint256 coinLp, uint256 lpMinted);

    /* ───────── guard ───────── */
    // Solady (https://github.com/Vectorized/soledge/blob/main/src/utils/ReentrancyGuard.sol)
    error Reentrancy();

    modifier lock() {
        assembly ("memory-safe") {
            if tload(0x929eee149b4bd21268) {
                mstore(0x00, 0xab143c06) // `Reentrancy()`
                revert(0x1c, 0x04)
            }
            tstore(0x929eee149b4bd21268, address())
        }
        _;
        assembly ("memory-safe") {
            tstore(0x929eee149b4bd21268, 0)
        }
    }

    /* ───────── constructor ───────── */
    constructor() payable {}

    /* ===================================================================== //
                                L A U N C H
    // =====================================================================*/

    error InvalidArray();
    error InvalidUnlock();

    function launch(
        uint96 creatorSupply,
        uint256 creatorUnlock, /*flag*/
        string calldata uri,
        uint96[] calldata trancheCoins,
        uint96[] calldata tranchePrice
    ) public returns (uint256 coinId) {
        uint256 L = trancheCoins.length;
        require(L != 0, InvalidArray());
        require(L <= 100, InvalidArray()); // sanity max
        require(L == tranchePrice.length, InvalidArray());

        /* 1. mint coin to this contract */
        uint96 saleSupply;
        for (uint256 i; i != L; ++i) {
            saleSupply += trancheCoins[i];
        }
        coinId = Z.coin(address(this), creatorSupply + (saleSupply * 2), /*pool-dupe*/ uri);

        /* 2. creator allocation */
        if (creatorSupply != 0) {
            // lock if forward-looking
            if (creatorUnlock > block.timestamp) {
                Z.lockup(address(Z), msg.sender, coinId, creatorSupply, creatorUnlock);
            } else {
                balances[coinId][msg.sender] = creatorSupply;
            }
        }

        /* 3. store sale meta & post tranche orders */
        Sale storage S = sales[coinId];
        S.creator = msg.sender;
        S.coinId = coinId;

        unchecked {
            uint56 dlBase = uint56(block.timestamp) + SALE_DURATION;
            uint56 dl;

            for (uint256 i; i != L; ++i) {
                dl = dlBase + uint56(i); // unique hash
                Z.makeOrder(
                    address(Z),
                    coinId,
                    trancheCoins[i], // sell coin
                    address(this),
                    0,
                    tranchePrice[i], // want ETH
                    dl,
                    true
                );
                S.trancheCoins.push(trancheCoins[i]);
                S.tranchePrice.push(tranchePrice[i]);
                S.deadlines.push(dl);
            }
            S.deadlineLast = dlBase + uint56(L - 1);

            /* prevent creator unlock while sale is running */
            require(creatorUnlock == 0 || creatorUnlock > S.deadlineLast, InvalidUnlock());

            emit Launch(msg.sender, coinId, saleSupply);
        }
    }

    /* ───────── direct coin methods ───────── */

    function coinWithPool(
        uint256 poolSupply,
        uint256 creatorSupply,
        uint256 creatorUnlock,
        string calldata uri
    ) public payable returns (uint256 coinId, uint256 lp) {
        coinId = Z.coin(address(this), poolSupply + creatorSupply, uri);

        if (creatorSupply != 0) {
            // lock if forward-looking
            if (creatorUnlock > block.timestamp) {
                Z.lockup(address(Z), msg.sender, coinId, creatorSupply, creatorUnlock);
            } else {
                Z.transfer(msg.sender, coinId, creatorSupply);
            }
        }

        IZAMM.PoolKey memory key = IZAMM.PoolKey({
            id0: 0,
            id1: coinId,
            token0: address(0),
            token1: address(Z),
            feeOrHook: DEFAULT_FEE_BPS
        });

        (,, lp) = Z.addLiquidity{value: msg.value}(
            key, msg.value, poolSupply, 0, 0, msg.sender, block.timestamp
        );
    }

    function coinWithPoolCustom(
        bool lpLock,
        uint256 swapFee,
        uint256 poolSupply,
        uint256 creatorSupply,
        uint256 creatorUnlock,
        string calldata uri
    ) public payable returns (uint256 coinId, uint256 lp) {
        coinId = Z.coin(address(this), poolSupply + creatorSupply, uri);

        if (creatorSupply != 0) {
            // lock if forward-looking
            if (creatorUnlock > block.timestamp) {
                Z.lockup(address(Z), msg.sender, coinId, creatorSupply, creatorUnlock);
            } else {
                Z.transfer(msg.sender, coinId, creatorSupply);
            }
        }

        IZAMM.PoolKey memory key = IZAMM.PoolKey({
            id0: 0,
            id1: coinId,
            token0: address(0),
            token1: address(Z),
            feeOrHook: swapFee
        });

        address receiver;
        lpLock ? receiver = address(this) : msg.sender;

        (,, lp) = Z.addLiquidity{value: msg.value}(
            key, msg.value, poolSupply, 0, 0, receiver, block.timestamp
        );

        if (lpLock) Z.lockup(address(Z), msg.sender, uint256(keccak256(abi.encode(key))), lp, creatorUnlock);
    }

    function coinWithLockup(
        uint256 creatorSupply,
        uint256 creatorLockup,
        uint256 creatorUnlock,
        string calldata uri
    ) public returns (uint256 coinId) {
        coinId = Z.coin(address(this), creatorSupply + creatorLockup, uri);

        // -- immediate portion --
        if (creatorSupply != 0) Z.transfer(msg.sender, coinId, creatorSupply);
        
        // -- locked portion --
        if (creatorLockup != 0) {
            require(creatorUnlock > block.timestamp, InvalidUnlock());
            Z.lockup(address(Z), msg.sender, coinId, creatorLockup, creatorUnlock);
        }
    }

    /* ===================================================================== //
                                  B U Y
    // =====================================================================*/

    error BadIndex();
    error Finalized();
    error InvalidMsgVal();

    /// @notice Purchase coins from selected tranche. Finalizes pool liquidity if last fill.
    function buy(uint256 coinId, uint256 trancheIdx) public payable lock returns (uint128 coinsOut) {
        Sale storage S = sales[coinId];
        require(S.creator != address(0), Finalized());
        require(trancheIdx < S.trancheCoins.length, BadIndex());

        uint96 coinsIn = S.trancheCoins[trancheIdx];
        uint96 ethOut = S.tranchePrice[trancheIdx];

        if (mulmod(msg.value, coinsIn, ethOut) != 0) revert InvalidMsgVal();

        Z.fillOrder(
            address(this),
            address(Z),
            coinId,
            coinsIn,
            address(this),
            0,
            ethOut,
            S.deadlines[trancheIdx],
            true,
            uint96(msg.value)
        );

        unchecked {
            coinsOut = uint128((coinsIn * msg.value) / ethOut);
            require(coinsOut != 0, InvalidMsgVal()); // sanity
            S.ethRaised += uint128(msg.value);
            S.coinsSold += coinsOut;
            balances[coinId][msg.sender] += coinsOut;
        }

        emit Buy(msg.sender, coinId, msg.value, coinsOut);

        /* auto-finalize if no coins left */
        if (S.coinsSold == _saleSupply(S)) _finalize(S, coinId);
    }

    function _saleSupply(Sale storage S) internal view returns (uint256 sum) {
        unchecked {
            for (uint256 i; i != S.trancheCoins.length; ++i) sum += S.trancheCoins[i];
        }
    }

    /// @dev Dummy ERC20 token stub in order to lock all orderbook interactions to launchpad.
    function transferFrom(address from, address to, uint256) public payable returns (bool) {
        require(msg.sender == address(Z));
        require(from == address(this));
        require(to == address(this));
        return true;
    }

    /// @notice Remaining wei to fill a given tranche order (0 if sold-out or finalized).
    function trancheRemainingWei(uint256 coinId, uint256 trancheIdx)
        public
        view
        returns (uint96 weiRemaining)
    {
        Sale storage S = sales[coinId];
        if (S.creator == address(0) || trancheIdx >= S.trancheCoins.length) return 0;

        uint96 ethTotal = S.tranchePrice[trancheIdx];

        bytes32 orderHash = keccak256(
            abi.encode(
                address(this),
                address(Z),
                coinId,
                S.trancheCoins[trancheIdx],
                address(this),
                0,
                ethTotal,
                S.deadlines[trancheIdx],
                true
            )
        );

        /* if order has been deleted (deadline==0), treat as sold */
        (, uint56 deadline,, uint96 outDone) = Z.orders(orderHash);
        if (deadline == 0) {
            return 0;
        }
        if (ethTotal > outDone) {
            weiRemaining = ethTotal - outDone;
        }
    }

    /* ---------------- share helpers ---------------- */

    /// ------------------------------------------------------------------
    /// buyExactCoins  –  share-driven purchase with automatic refund
    /// ------------------------------------------------------------------
    
    error ZeroShares();

    function buyExactCoins(
        uint256 coinId,
        uint256 trancheIdx,
        uint96 shares // exact number of coins desired
    ) public lock payable returns (uint128 coinsOut) {
        if (shares == 0) revert ZeroShares();

        Sale storage S = sales[coinId];
        require(S.creator != address(0), Finalized());
        require(trancheIdx < S.trancheCoins.length, BadIndex());

        uint96 coinsIn = S.trancheCoins[trancheIdx]; 
        uint96 ethOut  = S.tranchePrice[trancheIdx]; 

        // -------- price calculation ------------------------------------
        uint256 numerator = uint256(shares) * ethOut;
        require(numerator % coinsIn == 0, InvalidMsgVal());
        uint256 costWei   = numerator / coinsIn;
        require(msg.value >= costWei, InvalidMsgVal());

        // -------- call into ZAMM fillOrder directly --------------------
        Z.fillOrder(
            address(this),
            address(Z),
            coinId,
            coinsIn,
            address(this),
            0,
            ethOut,
            S.deadlines[trancheIdx],
            true,
            uint96(costWei) // we pay only the exact cost                        
        );

        // -------- update accounting ------------------------------------
        unchecked {
            coinsOut = shares; // by construction                  
            S.ethRaised += uint128(costWei);
            S.coinsSold += coinsOut;
            balances[coinId][msg.sender] += coinsOut;
        }

        emit Buy(msg.sender, coinId, costWei, coinsOut);

        // auto-finalise when fully sold
        if (S.coinsSold == _saleSupply(S)) _finalize(S, coinId);

        // -------- refund surplus (if any) ------------------------------
        if (msg.value > costWei) {
            unchecked {
                safeTransferETH(msg.sender, msg.value - costWei);
            }
        }
    }

    /// @notice Remaining coins to fill a given tranche order (0 if sold-out or finalized).
    function trancheRemainingCoins(uint256 coinId, uint256 trancheIdx)
        public
        view
        returns (uint96 coinsRemaining)
    {
        Sale storage S = sales[coinId];
        if (S.creator == address(0) || trancheIdx >= S.trancheCoins.length) return 0;

        uint96 coinsTotal = S.trancheCoins[trancheIdx];
        uint96 ethTotal   = S.tranchePrice[trancheIdx];

        bytes32 orderHash = keccak256(
            abi.encode(
                address(this),
                address(Z),
                coinId,
                coinsTotal, 
                address(this),
                0,
                ethTotal,            
                S.deadlines[trancheIdx],
                true                 
            )
        );

        /* if order has been deleted (deadline == 0) treat as sold-out */
        (, uint56 deadline, uint96 inDone,) = Z.orders(orderHash);
        if (deadline == 0) return 0;

        if (coinsTotal > inDone) {
            coinsRemaining = coinsTotal - inDone;
        }
    }


    /* ===================================================================== //
                               F I N A L I Z E
    // =====================================================================*/

    error Pending();

    /// @notice Anyone may finalize after window.
    function finalize(uint256 coinId) public lock {
        Sale storage S = sales[coinId];
        require(S.creator != address(0), Finalized());
        require(block.timestamp >= S.deadlineLast, Pending());
        _finalize(S, coinId);
    }

    /// @notice Anyone may claim after finalized.
    function claim(uint256 coinId, uint256 amount) public lock {
        Sale storage S = sales[coinId];
        require(S.creator == address(0), Pending());
        balances[coinId][msg.sender] -= amount;
        Z.transfer(msg.sender, coinId, amount);
    }

    /* ---------------- internal worker ---------------- */

    error NoRaise();

    function _finalize(Sale storage S, uint256 coinId) internal {
        if (S.creator == address(0)) return;

        uint256 escrow = S.ethRaised;
        uint256 coinBal = S.coinsSold;
        require(escrow != 0, NoRaise());

        delete S.creator;
        delete S.deadlineLast;
        delete S.coinId;
        delete S.trancheCoins;
        delete S.tranchePrice;
        delete S.deadlines;
        delete S.ethRaised;
        delete S.coinsSold;

        IZAMM.PoolKey memory key = IZAMM.PoolKey({
            id0: 0,
            id1: coinId,
            token0: address(0),
            token1: address(Z),
            feeOrHook: DEFAULT_FEE_BPS
        });

        (,, uint256 lp) = Z.addLiquidity{value: escrow}(
            key, escrow, coinBal, 0, 0, address(this), block.timestamp
        );

        emit Finalize(coinId, escrow, coinBal, lp);
    }
}

/*───────────────────────────  ZAMM interface  ───────────────────────────*/
interface IZAMM {
    /* ── Order-book ── */
    function makeOrder(
        address tokenIn,
        uint256 idIn,
        uint96 amtIn,
        address tokenOut,
        uint256 idOut,
        uint96 amtOut,
        uint56 deadline,
        bool partialFill
    ) external payable returns (bytes32 orderHash);

    function fillOrder(
        address maker,
        address tokenIn,
        uint256 idIn,
        uint96 amtIn,
        address tokenOut,
        uint256 idOut,
        uint96 amtOut,
        uint56 deadline,
        bool partialFill,
        uint96 fillPart
    ) external payable;

    /* ── Order-book view ── */
    function orders(bytes32 orderHash)
        external
        view
        returns (bool partialFill, uint56 deadline, uint96 inDone, uint96 outDone);

    /* ── Liquidity ── */
    struct PoolKey {
        uint256 id0;
        uint256 id1;
        address token0;
        address token1;
        uint256 feeOrHook;
    }

    function addLiquidity(
        PoolKey calldata poolKey,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amount0, uint256 amount1, uint256 liquidity);

    function lockup(address token, address to, uint256 id, uint256 amount, uint256 unlockTime)
        external
        payable
        returns (bytes32 lockHash);

    /* ── ERC-6909 coin ── */
    function coin(address creator, uint256 supply, string calldata uri)
        external
        returns (uint256 coinId);
    function transfer(address to, uint256 id, uint256 amount) external returns (bool);
}

// Modified from Solady (https://github.com/Vectorized/solady/blob/main/src/utils/SafeTransferLib.sol)

/// @dev Sends `amount` (in wei) ETH to `to`.
function safeTransferETH(address to, uint256 amount) {
    assembly ("memory-safe") {
        if iszero(call(gas(), to, amount, codesize(), 0x00, codesize(), 0x00)) {
            mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`
            revert(0x1c, 0x04)
        }
    }
}
