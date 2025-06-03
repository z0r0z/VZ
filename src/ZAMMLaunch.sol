// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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
    ) external payable returns (bytes32);

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

    /* ── Liquidity ── */
    struct PoolKey {
        uint256 id0;
        uint256 id1;
        address token0;
        address token1;
        uint256 feeOrHook;
    }

    function addLiquidity(
        PoolKey calldata key,
        uint256 a0,
        uint256 a1,
        uint256 m0,
        uint256 m1,
        address to,
        uint256 deadline
    ) external payable returns (uint256, uint256, uint256);

    function lockup(address token, address to, uint256 id, uint256 amount, uint256 unlockTime)
        external
        returns (bytes32);

    /* ── ERC-6909 coin ── */
    function coin(address creator, uint256 supply, string calldata uri)
        external
        returns (uint256);
    function transfer(address to, uint256 id, uint256 amount) external returns (bool);
    function balanceOf(address owner, uint256 id) external view returns (uint256);
    function setOperator(address op, bool ok) external returns (bool);
}

/*──────────────────────────  ZAMMLaunch  ──────────────────────────*/
contract ZAMMLaunch {
    /* ───────── constants ───────── */
    IZAMM public immutable Z;
    uint56 internal constant SALE_DURATION = 1 weeks;
    uint256 internal constant DEFAULT_FEE_BPS = 30; // 0.30 %
    uint256 internal constant T_SLOT =
        0xb67c553beecc9b0bdf5d20c9ef5c02f2d93da71346acde4059fad3ea1b83b6b9;

    /* ───────── storage ───────── */
    struct Sale {
        address creator;
        uint256 coinId;
        uint96[] trancheCoins; // coins offered per tranche
        uint96[] tranchePrice; // ETH wanted  per tranche
        uint56[] deadlines; // one per tranche
        uint56 deadlineLast; // quick finalization check
        bool lockLp;
        uint256 lpUnlock;
        bool finalized;
    }

    mapping(uint256 => Sale) public sales; // coinId → Sale
    mapping(uint256 => uint256) public ethRaised; // coinId → ETH
    mapping(uint256 => mapping(address => uint256)) public contributions; // coinId → buyer → ETH

    /* ───────── events ───────── */
    event Launch(address indexed creator, uint256 indexed coinId);
    event Buy(address indexed buyer, uint256 indexed coinId, uint256 ethIn, uint96 coinOut);
    event Finalize(uint256 indexed coinId, uint256 ethLp, uint256 coinLp, uint256 lpMinted);

    /* ───────── constructor ───────── */
    constructor(address zammSingleton) {
        Z = IZAMM(zammSingleton);
        Z.setOperator(address(this), true); // launchpad may burn/mint during fills
    }

    /* ===================================================================== //
                                L A U N C H
    // =====================================================================*/
    function launch(
        uint96 creatorSupply,
        uint96[] calldata trancheCoins,
        uint96[] calldata tranchePrice,
        string calldata uri,
        bool lockCreatorSupply,
        uint256 creatorUnlock,
        bool lockLp,
        uint256 lpUnlockTime
    ) external returns (uint256 coinId) {
        uint256 L = trancheCoins.length;
        require(L == tranchePrice.length, "array mismatch");

        /* 1. mint coin to this contract */
        uint96 saleSupply;
        unchecked {
            for (uint256 i; i < L; ++i) {
                saleSupply += trancheCoins[i];
            }
        }
        coinId = Z.coin(address(this), creatorSupply + saleSupply, uri);

        /* 2. creator allocation */
        if (creatorSupply != 0) {
            if (lockCreatorSupply) {
                Z.lockup(address(Z), msg.sender, coinId, creatorSupply, creatorUnlock);
            } else {
                Z.transfer(msg.sender, coinId, creatorSupply);
            }
        }

        /* 3. store sale meta & post tranche orders */
        Sale storage S = sales[coinId];
        S.creator = msg.sender;
        S.coinId = coinId;
        S.lockLp = lockLp;
        S.lpUnlock = lpUnlockTime;

        uint56 dlBase = uint56(block.timestamp) + SALE_DURATION;

        for (uint256 i; i < L; ++i) {
            uint56 dl = dlBase + uint56(i); // unique hash
            Z.makeOrder(
                address(Z),
                coinId,
                trancheCoins[i], // sell coin
                address(0),
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

        emit Launch(msg.sender, coinId);
    }

    /* ===================================================================== //
                                  B U Y
    // =====================================================================*/
    /// @param fillPart 0 = take remainder, else exact ETH (must equal msg.value).
    function buy(uint256 coinId, uint256 trancheIdx, uint96 fillPart) external payable {
        Sale storage S = sales[coinId];
        require(!S.finalized, "finalized");
        require(trancheIdx < S.trancheCoins.length, "bad index");
        require(fillPart == 0 ? msg.value != 0 : msg.value == fillPart, "value mismatch");

        uint96 coinsIn = S.trancheCoins[trancheIdx];
        uint96 ethOut = S.tranchePrice[trancheIdx];
        uint56 dl = S.deadlines[trancheIdx];

        /* tag ETH using transient storage */
        assembly {
            tstore(T_SLOT, coinId)
        }

        Z.fillOrder{value: msg.value}(
            address(this), address(Z), coinId, coinsIn, address(0), 0, ethOut, dl, true, fillPart
        );

        assembly {
            tstore(T_SLOT, 0)
        }

        contributions[coinId][msg.sender] += msg.value;
        emit Buy(msg.sender, coinId, msg.value, fillPart == 0 ? coinsIn : fillPart);

        /* auto-finalize if no coins left */
        if (Z.balanceOf(address(this), coinId) == 0) _finalize(coinId);
    }

    /* ZAMM sends ETH here during fillOrder. */
    receive() external payable {
        uint256 coinId;
        assembly {
            coinId := tload(T_SLOT)
        }
        require(coinId != 0, "direct ETH rejected");
        ethRaised[coinId] += msg.value;
    }

    /* ===================================================================== //
                               F I N A L I Z E
    // =====================================================================*/

    error Finalized();

    /// @notice anyone may finalize after window or once all coins sold.
    function finalize(uint256 coinId) external {
        Sale storage S = sales[coinId];
        require(!S.finalized, Finalized());
        require(block.timestamp >= S.deadlineLast, "sale active");
        _finalize(coinId);
    }

    /* ---------------- internal worker ---------------- */
    function _finalize(uint256 coinId) internal {
        Sale storage S = sales[coinId];
        if (S.finalized) return;
        S.finalized = true;

        uint256 coinBal = Z.balanceOf(address(this), coinId);
        uint256 escrow = ethRaised[coinId];
        ethRaised[coinId] = 0;
        require(escrow != 0, "nothing raised");

        IZAMM.PoolKey memory key = IZAMM.PoolKey({
            id0: 0,
            id1: coinId,
            token0: address(0),
            token1: address(Z),
            feeOrHook: DEFAULT_FEE_BPS
        });

        (,, uint256 lp) = Z.addLiquidity{value: escrow}(
            key, escrow, coinBal, 0, 0, S.lockLp ? address(this) : S.creator, block.timestamp
        );

        /* optional LP lock */
        if (S.lockLp) {
            uint256 poolId = uint256(
                keccak256(abi.encode(key.id0, key.id1, key.token0, key.token1, key.feeOrHook))
            );
            Z.lockup(address(Z), S.creator, poolId, lp, S.lpUnlock);
        }

        emit Finalize(coinId, escrow, coinBal, lp);

        uint256 dust = address(this).balance;
        if (dust != 0) payable(S.creator).transfer(dust);
    }
}
