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
    function balanceOf(address owner, uint256 id) external view returns (uint256);
    function setOperator(address op, bool ok) external returns (bool);
}

/*──────────────────────────  ZAMMLaunch  ──────────────────────────*/
contract ZAMMLaunch {
    /* ───────── constants ───────── */
    IZAMM constant Z = IZAMM(0x000000000000040470635EB91b7CE4D132D616eD);
    uint56 constant SALE_DURATION = 1 weeks;
    uint256 constant DEFAULT_FEE_BPS = 100; // 1 %
    uint256 constant T_SLOT = 0xb67c553beecc9b0bdf5d20c9ef5c02f2d93da71346acde4059fad3ea1b83b6b9;

    // @to-do: please pack this struct for efficient storage and amend any related code

    /* ───────── storage ───────── */
    struct Sale {
        address creator;
        uint256 coinId;
        uint96[] trancheCoins; // coins offered per tranche
        uint96[] tranchePrice; // ETH wanted per tranche
        uint56[] deadlines; // one per tranche
        uint56 deadlineLast; // quick finalization check
        bool lockLp;
        uint256 lpUnlock;
        bool finalized;
    }

    mapping(uint256 coinId => Sale) public sales;
    mapping(uint256 coinId => uint256) public ethRaised;
    mapping(uint256 coinId => mapping(address buyer => uint256)) public contributions;

    /* ───────── events ───────── */
    event Launch(address indexed creator, uint256 indexed coinId);
    event Buy(address indexed buyer, uint256 indexed coinId, uint256 ethIn, uint96 coinOut);
    event Finalize(uint256 indexed coinId, uint256 ethLp, uint256 coinLp, uint256 lpMinted);

    /* ───────── constructor ───────── */
    constructor() payable {}

    /* ===================================================================== //
                                L A U N C H
    // =====================================================================*/

    error ArrayMismatch();

    function launch(
        uint96 creatorSupply,
        uint96[] calldata trancheCoins,
        uint96[] calldata tranchePrice,
        string calldata uri,
        bool lockCreatorSupply,
        uint256 creatorUnlock,
        bool lockLp,
        uint256 lpUnlockTime
    ) public returns (uint256 coinId) {
        uint256 L = trancheCoins.length;
        require(L == tranchePrice.length, ArrayMismatch());

        /* 1. mint coin to this contract */
        uint96 saleSupply;
        for (uint256 i; i != L; ++i) {
            saleSupply += trancheCoins[i];
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
        uint56 dl;

        for (uint256 i; i != L; ++i) {
            dl = dlBase + uint56(i); // unique hash
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

    error BadIndex();
    error Finalized();
    error InvalidMsgVal();

    /// @param fillPart 0 = take remainder, else exact ETH (must equal msg.value).
    function buy(uint256 coinId, uint256 trancheIdx, uint96 fillPart) public payable {
        Sale storage S = sales[coinId];
        require(!S.finalized, Finalized());
        require(trancheIdx < S.trancheCoins.length, BadIndex());
        require(fillPart == 0 ? msg.value != 0 : msg.value == fillPart, InvalidMsgVal());

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

        unchecked {
            contributions[coinId][msg.sender] += msg.value;
        }

        emit Buy(msg.sender, coinId, msg.value, fillPart);

        /* auto-finalize if no coins left (account for wei remainder) */
        if (Z.balanceOf(address(this), coinId) < 2) _finalize(S, coinId);
    }

    error Unauthorized();

    /* ZAMM sends ETH here during fillOrder. */
    receive() external payable {
        uint256 coinId;
        assembly {
            coinId := tload(T_SLOT)
        }
        require(coinId != 0, Unauthorized());
        unchecked {
            ethRaised[coinId] += msg.value;
        }
    }

    /* ===================================================================== //
                               F I N A L I Z E
    // =====================================================================*/

    error Pending();

    /// @notice Anyone may finalize after window or once all coins sold.
    function finalize(uint256 coinId) public {
        Sale storage S = sales[coinId];
        require(!S.finalized, Finalized());
        require(block.timestamp >= S.deadlineLast, Pending());
        _finalize(S, coinId);
    }

    /* ---------------- internal worker ---------------- */
    error NoRaise();

    function _finalize(Sale storage S, uint256 coinId) internal {
        if (S.finalized) return;
        S.finalized = true;

        uint256 coinBal = Z.balanceOf(address(this), coinId);
        uint256 escrow = ethRaised[coinId];
        delete ethRaised[coinId];
        require(escrow != 0, NoRaise());

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
    }
}
