// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ShockFeeMath — pure maths for the OddsShift provisional shock fee
///
/// Deliberately dependency-free so the whole verdict rule is unit-testable without
/// standing up a PoolManager. Tick→sqrtPrice conversion is left to the call site
/// (v4-core's TickMath) so this library never imports v4.
///
/// The verdict rule, in one line:
///
///     r = (P* − P0) / (P1 − P0)
///
/// where P0 is the probability before a trade, P1 the probability immediately after it
/// (so P1 − P0 is the trader's own mechanical impact), and P* the TWAP over the judging
/// epoch. r answers "how much of MY push did the market retain?":
///
///     r ≤ 0   the move fully reverted or overshot back   → fair,  base fee
///     r = 1   price sat exactly where the trader left it → midpoint
///     r ≥ 2   the market travelled twice the trader's own impact, in their direction,
///             on other people's order flow                → toxic, full shock fee
///
/// Anchoring on P1 rather than P0 is what makes "no follow-on trading at all" resolve to
/// FAIR: with no subsequent flow, P* == P1, so r == 1 at most and never runs away. A P0
/// anchor would instead convict every price-moving trade in a quiet market.
library ShockFeeMath {
    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Basis points denominator. Probabilities, ratios and fees are all in BPS.
    uint256 internal constant BPS = 10_000;

    /// @dev Bits shifted off sqrtPriceX96 before squaring, so the square cannot
    ///      overflow uint256. sqrtPriceX96 < 2^160, so (s >> 48)^2 < 2^224.
    ///      Costs ~2^-47 relative precision, far below one BPS of probability.
    uint256 private constant SHIFT = 48;

    /// @dev 2^(192 - 2*SHIFT) == 2^96, the rebased "one" after the shift.
    uint256 private constant ONE_SHIFTED = 1 << 96;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroImpact();
    error InvalidCurve();

    /*//////////////////////////////////////////////////////////////
                             PROBABILITY
    //////////////////////////////////////////////////////////////*/

    /// @notice Convert a v4 `sqrtPriceX96` into P(YES), in BPS.
    /// @dev v4 encodes price = currency1/currency0 = (sqrtPriceX96 / 2^96)^2. For a
    ///      YES/NO pool the relative price of the two outcome tokens *is* the odds
    ///      ratio, because a fully collateralised pair satisfies P(YES) + P(NO) = 1.
    ///
    ///        yesIsCurrency0:  1 YES = price NO  →  P(YES)/P(NO) = price
    ///                                          →  P(YES) = price / (1 + price)
    ///        otherwise:                            P(YES) = 1 / (1 + price)
    ///
    ///      Substituting price = s²/2^192 and rebasing by 2^(2·SHIFT) keeps everything
    ///      inside uint256 without a full 512-bit mulDiv.
    /// @param sqrtPriceX96   Pool price, Q64.96.
    /// @param yesIsCurrency0 True when the YES token sorted below the NO token.
    /// @return probabilityBps P(YES) in BPS, clamped to [0, BPS].
    function probabilityBps(uint160 sqrtPriceX96, bool yesIsCurrency0)
        internal
        pure
        returns (uint256)
    {
        if (sqrtPriceX96 == 0) return 0;

        // sq = price · 2^96, i.e. the price rebased so that 1.0 == ONE_SHIFTED.
        uint256 shifted = uint256(sqrtPriceX96) >> SHIFT;
        uint256 sq = shifted * shifted;

        uint256 denominator = ONE_SHIFTED + sq;

        // numerator/denominator == price/(1+price) or 1/(1+price) respectively.
        uint256 numerator = yesIsCurrency0 ? sq : ONE_SHIFTED;

        uint256 p = (numerator * BPS) / denominator;
        return p > BPS ? BPS : p;
    }

    /*//////////////////////////////////////////////////////////////
                          RETENTION RATIO
    //////////////////////////////////////////////////////////////*/

    /// @notice The retention ratio r, in BPS (so BPS == 1.0).
    /// @dev Signed division is already direction-correct: a NO buy has both `ownImpact`
    ///      and `netMove` negative, and negative/negative is positive. Opposite signs
    ///      mean the market moved against the trader, giving r < 0 → fair.
    ///
    ///      Solidity truncates toward zero, which biases |r| very slightly downward,
    ///      i.e. toward the trader. That is the safe direction for a fee.
    /// @param ownImpact P1 − P0 in probability BPS: the trader's own mechanical impact.
    ///                  Must be non-zero; callers exempt sub-threshold trades first.
    /// @param netMove   P* − P0 in probability BPS: total move including everyone else.
    function retentionBps(int256 ownImpact, int256 netMove) internal pure returns (int256) {
        if (ownImpact == 0) revert ZeroImpact();
        return (netMove * int256(BPS)) / ownImpact;
    }

    /*//////////////////////////////////////////////////////////////
                             FEE CURVE
    //////////////////////////////////////////////////////////////*/

    /// @notice Linear interpolation from `baseFeeBps` at r ≤ 0 to `shockFeeBps` at
    ///         r ≥ `rMaxBps`.
    /// @dev Continuous by design. A binary threshold would put a ~10× cost cliff at a
    ///      publicly predictable checkpoint instant, making it worth a great deal to
    ///      nudge the price by one wei of tick; under a linear curve, moving the price
    ///      by ε changes the fee by ε.
    /// @param retention_  Retention ratio in BPS, from {retentionBps}.
    /// @param baseFeeBps  Fee floor — the ordinary LP fee a fair trade always pays.
    /// @param shockFeeBps Fee ceiling — the full provisional charge.
    /// @param rMaxBps     Retention at which the fee reaches `shockFeeBps`.
    /// @return feeBps Fee in BPS, always within [baseFeeBps, shockFeeBps].
    function feeBps(int256 retention_, uint256 baseFeeBps, uint256 shockFeeBps, uint256 rMaxBps)
        internal
        pure
        returns (uint256)
    {
        if (shockFeeBps < baseFeeBps || rMaxBps == 0) revert InvalidCurve();

        if (retention_ <= 0) return baseFeeBps;

        uint256 r = uint256(retention_);
        if (r >= rMaxBps) return shockFeeBps;

        return baseFeeBps + ((shockFeeBps - baseFeeBps) * r) / rMaxBps;
    }

    /// @notice One-shot verdict: impact and net move in, fee in BPS out.
    /// @dev Applies the sub-threshold exemption itself, so a dust trade that cannot
    ///      have moved the market is never convicted by somebody else's information.
    /// @param ownImpact    P1 − P0, probability BPS.
    /// @param netMove      P* − P0, probability BPS.
    /// @param minImpactBps Trades whose |ownImpact| is below this are charged `baseFeeBps`.
    function resolveFeeBps(
        int256 ownImpact,
        int256 netMove,
        uint256 minImpactBps,
        uint256 baseFeeBps,
        uint256 shockFeeBps,
        uint256 rMaxBps
    ) internal pure returns (uint256) {
        uint256 magnitude = ownImpact < 0 ? uint256(-ownImpact) : uint256(ownImpact);
        if (magnitude < minImpactBps) return baseFeeBps;

        return feeBps(retentionBps(ownImpact, netMove), baseFeeBps, shockFeeBps, rMaxBps);
    }

    /*//////////////////////////////////////////////////////////////
                              ESCROW SPLIT
    //////////////////////////////////////////////////////////////*/

    /// @notice Split a held escrow into the LP-protection share and the trader rebate.
    /// @dev `escrow` was taken at `shockFeeBps` of the swap; the trade turned out to
    ///      deserve `feeBps_`. Rounding leaves the remainder with the LPs, never
    ///      creating rebate the contract does not hold.
    /// @return lpAmount     Portion owed to liquidity providers.
    /// @return rebateAmount Portion owed back to the trader.
    function splitEscrow(uint256 escrow, uint256 feeBps_, uint256 shockFeeBps)
        internal
        pure
        returns (uint256 lpAmount, uint256 rebateAmount)
    {
        if (shockFeeBps == 0 || feeBps_ >= shockFeeBps) return (escrow, 0);

        // rebate = escrow · (1 − fee/shock); computed as a single floor division so
        // lpAmount picks up the dust.
        rebateAmount = (escrow * (shockFeeBps - feeBps_)) / shockFeeBps;
        lpAmount = escrow - rebateAmount;
    }
}
