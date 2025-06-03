// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/*──────────────────────────  ZAMMLaunch  ──────────────────────────*/
contract ZAMMLaunch {
    /* ───────── constants ───────── */
    IZAMM constant Z = IZAMM(0x000000000000040470635EB91b7CE4D132D616eD);
    uint56 constant SALE_DURATION = 1 weeks;
    uint256 constant DEFAULT_FEE_BPS = 100; // 1 %

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

    /* ───────── events ───────── */
    event Launch(address indexed creator, uint256 indexed coinId, uint96 saleSupply);
    event Buy(address indexed buyer, uint256 indexed coinId, uint256 ethIn, uint128 coinsOut);
    event Finalize(uint256 indexed coinId, uint256 ethLp, uint256 coinLp, uint256 lpMinted);

    /* ───────── constructor ───────── */
    constructor() payable {}

    /* ===================================================================== //
                                L A U N C H
    // =====================================================================*/

    error InvalidArray();

    function launch(
        uint96 creatorSupply,
        uint256 creatorUnlock, /*flag*/
        string calldata uri,
        uint96[] calldata trancheCoins,
        uint96[] calldata tranchePrice
    ) public returns (uint256 coinId) {
        uint256 L = trancheCoins.length;
        require(L != 0, InvalidArray());
        require(L == tranchePrice.length, InvalidArray());

        /* 1. mint coin to this contract */
        uint96 saleSupply;
        for (uint256 i; i != L; ++i) {
            saleSupply += trancheCoins[i];
        }
        coinId = Z.coin(address(this), creatorSupply + saleSupply + saleSupply, uri);

        /* 2. creator allocation */
        if (creatorSupply != 0) {
            // lock if forward-looking
            if (creatorUnlock > block.timestamp) {
                Z.lockup(address(Z), msg.sender, coinId, creatorSupply, creatorUnlock);
            } else {
                Z.transfer(msg.sender, coinId, creatorSupply);
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

            emit Launch(msg.sender, coinId, saleSupply);
        }
    }

    /* ===================================================================== //
                                  B U Y
    // =====================================================================*/

    error BadIndex();
    error Finalized();
    error InvalidMsgVal();

    function buy(uint256 coinId, uint256 trancheIdx) public payable returns (uint128 coinsOut) {
        Sale storage S = sales[coinId];
        require(S.creator != address(0), Finalized());
        require(trancheIdx < S.trancheCoins.length, BadIndex());

        uint96 coinsIn = S.trancheCoins[trancheIdx];
        uint96 ethOut = S.tranchePrice[trancheIdx];
        uint56 dl = S.deadlines[trancheIdx];

        Z.fillOrder{value: msg.value}(
            address(this),
            address(Z),
            coinId,
            coinsIn,
            address(0),
            0,
            ethOut,
            dl,
            true,
            uint96(msg.value)
        );

        unchecked {
            coinsOut = uint128(uint256(coinsIn) * msg.value / ethOut);
            S.ethRaised += uint128(msg.value);
            S.coinsSold += coinsOut;
        }

        require(coinsOut != 0, InvalidMsgVal());

        Z.transfer(msg.sender, coinId, coinsOut);

        emit Buy(msg.sender, coinId, msg.value, coinsOut);

        /* auto-finalize if no coins left */
        if (Z.balanceOf(address(this), coinId) == S.coinsSold) _finalize(S, coinId);
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
                address(0),
                0,
                ethTotal,
                S.deadlines[trancheIdx],
                true
            )
        );

        (,,, uint96 outDone) = Z.orders(orderHash);
        if (ethTotal > outDone) weiRemaining = ethTotal - outDone;
    }

    receive() external payable {}

    /* ===================================================================== //
                               F I N A L I Z E
    // =====================================================================*/

    error Pending();

    /// @notice Anyone may finalize after window.
    function finalize(uint256 coinId) public {
        Sale storage S = sales[coinId];
        require(S.creator != address(0), Finalized());
        require(block.timestamp >= S.deadlineLast, Pending());
        _finalize(S, coinId);
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
        returns (bool, /*partialFill*/ uint56, /*deadline*/ uint96, /*inDone*/ uint96); /*outDone*/

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
