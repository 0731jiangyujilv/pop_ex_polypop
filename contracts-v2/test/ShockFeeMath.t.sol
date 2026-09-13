// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ShockFeeMath} from "../src/v4/libraries/ShockFeeMath.sol";

/// @dev Library calls are inlined JUMPs, not CALLs, so `vm.expectRevert` cannot see
///      them. Revert cases have to cross a real call boundary — hence this harness.
contract ShockFeeMathHarness {
    function retentionBps(int256 ownImpact, int256 netMove) external pure returns (int256) {
        return ShockFeeMath.retentionBps(ownImpact, netMove);
    }

    function feeBps(int256 retention, uint256 base, uint256 shock, uint256 rMax)
        external
        pure
        returns (uint256)
    {
        return ShockFeeMath.feeBps(retention, base, shock, rMax);
    }
}

/// @title ShockFeeMath unit tests
///
/// Covers the verdict rule in isolation — no PoolManager, no hook, no pool. The
/// headline case is {test_Silence_ResolvesFair}: a trade followed by no order flow at
/// all must come out FAIR, because that is precisely what a P0-anchored rule gets
/// wrong (it would convict every price-moving trade in a quiet market).
contract ShockFeeMathTest is Test {
    uint256 internal constant BPS = 10_000;

    // Demo curve: 0.30% floor, 3.00% ceiling, reached at r = 2.0.
    uint256 internal constant BASE_FEE_BPS = 30;
    uint256 internal constant SHOCK_FEE_BPS = 300;
    uint256 internal constant R_MAX_BPS = 20_000;
    uint256 internal constant MIN_IMPACT_BPS = 10;

    // 100 USDC at 6 decimals, and the 3% escrow taken from it.
    uint256 internal constant TRADE = 100_000_000;
    uint256 internal constant ESCROW = 3_000_000;

    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336; // 2^96

    ShockFeeMathHarness internal harness;

    function setUp() public {
        harness = new ShockFeeMathHarness();
    }

    /*//////////////////////////////////////////////////////////////
                              HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Inverse of {ShockFeeMath.probabilityBps} for the yesIsCurrency0 orientation:
    ///      price = p/(1-p), sqrtPriceX96 = sqrt(price) · 2^96.
    function _sqrtPriceForProbability(uint256 pBps) internal pure returns (uint160) {
        require(pBps > 0 && pBps < BPS, "p out of range");
        return uint160(Math.sqrt((pBps << 192) / (BPS - pBps)));
    }

    /*//////////////////////////////////////////////////////////////
                            PROBABILITY
    //////////////////////////////////////////////////////////////*/

    function test_Probability_FiftyFifty_BothOrientations() public pure {
        assertEq(ShockFeeMath.probabilityBps(SQRT_PRICE_1_1, true), 5_000, "yes=c0");
        assertEq(ShockFeeMath.probabilityBps(SQRT_PRICE_1_1, false), 5_000, "yes=c1");
    }

    function test_Probability_RoundTrip() public pure {
        uint256[7] memory targets = [uint256(100), 1_000, 3_700, 5_000, 6_300, 9_000, 9_900];

        for (uint256 i = 0; i < targets.length; i++) {
            uint160 sqrtPrice = _sqrtPriceForProbability(targets[i]);
            uint256 recovered = ShockFeeMath.probabilityBps(sqrtPrice, true);
            // One BPS of slack for the >> SHIFT precision trade-off and integer sqrt.
            assertApproxEqAbs(recovered, targets[i], 1, "round-trip");
        }
    }

    /// @dev The two orientations must be exact complements: P(YES) + P(NO) == 1.
    function test_Probability_OrientationsAreComplementary() public pure {
        uint160 sqrtPrice = _sqrtPriceForProbability(6_300);

        uint256 asC0 = ShockFeeMath.probabilityBps(sqrtPrice, true);
        uint256 asC1 = ShockFeeMath.probabilityBps(sqrtPrice, false);

        assertApproxEqAbs(asC0 + asC1, BPS, 1, "complementary");
    }

    function test_Probability_ZeroPrice() public pure {
        assertEq(ShockFeeMath.probabilityBps(0, true), 0);
    }

    function testFuzz_Probability_AlwaysInRange(uint160 sqrtPriceX96) public pure {
        uint256 p = ShockFeeMath.probabilityBps(sqrtPriceX96, true);
        assertLe(p, BPS, "never exceeds 1.0");
    }

    /*//////////////////////////////////////////////////////////////
                          RETENTION RATIO
    //////////////////////////////////////////////////////////////*/

    /// @notice Trade 50→63, then nothing happens. P* == P1, so r == 1.0 exactly.
    function test_Retention_Silence_IsExactlyOne() public pure {
        int256 ownImpact = 1_300; // 50 → 63
        int256 netMove = 1_300; // P* == P1 == 63
        assertEq(ShockFeeMath.retentionBps(ownImpact, netMove), int256(BPS));
    }

    /// @notice Confirmed path: 50→63, market carries on to 72.
    function test_Retention_Confirmed() public pure {
        int256 r = ShockFeeMath.retentionBps(1_300, 2_200); // P* = 72
        assertEq(r, 16_923); // 2200/1300 = 1.6923
        assertGt(r, int256(BPS), "beyond hold");
    }

    /// @notice Reverted path: 50→63, market falls back to 51.
    function test_Retention_Reverted() public pure {
        int256 r = ShockFeeMath.retentionBps(1_300, 100); // P* = 51
        assertEq(r, 769); // 0.0769
        assertLt(r, int256(BPS), "mostly given back");
    }

    /// @notice Overshoot back through the anchor gives a negative ratio.
    function test_Retention_OvershootBack_IsNegative() public pure {
        int256 r = ShockFeeMath.retentionBps(1_300, -500); // P* = 45
        assertLt(r, 0);
    }

    /// @notice A NO buy has both terms negative; signed division makes it symmetric
    ///         with the YES case without any explicit direction handling.
    function test_Retention_NoSide_MirrorsYesSide() public pure {
        int256 yes = ShockFeeMath.retentionBps(1_300, 2_200);
        int256 no = ShockFeeMath.retentionBps(-1_300, -2_200);
        assertEq(yes, no, "direction-symmetric");
    }

    function test_Retention_ZeroImpact_Reverts() public {
        vm.expectRevert(ShockFeeMath.ZeroImpact.selector);
        harness.retentionBps(0, 500);
    }

    /*//////////////////////////////////////////////////////////////
                             FEE CURVE
    //////////////////////////////////////////////////////////////*/

    function test_FeeCurve_Endpoints() public pure {
        assertEq(_fee(-50_000), BASE_FEE_BPS, "far negative");
        assertEq(_fee(0), BASE_FEE_BPS, "zero");
        assertEq(_fee(int256(R_MAX_BPS)), SHOCK_FEE_BPS, "at rMax");
        assertEq(_fee(int256(R_MAX_BPS * 5)), SHOCK_FEE_BPS, "past rMax");
    }

    /// @notice r = 1.0 sits exactly halfway up the curve: 0.30% → 1.65% → 3.00%.
    function test_FeeCurve_HoldIsMidpoint() public pure {
        assertEq(_fee(int256(BPS)), 165);
    }

    function test_FeeCurve_ConfirmedAndReverted() public pure {
        assertEq(_fee(16_923), 258); // 30 + 270·1.6923/2
        assertEq(_fee(769), 40); // 30 + 270·0.0769/2
    }

    function test_FeeCurve_RejectsInvalidCurve() public {
        vm.expectRevert(ShockFeeMath.InvalidCurve.selector);
        harness.feeBps(int256(BPS), SHOCK_FEE_BPS, BASE_FEE_BPS, R_MAX_BPS); // inverted

        vm.expectRevert(ShockFeeMath.InvalidCurve.selector);
        harness.feeBps(int256(BPS), BASE_FEE_BPS, SHOCK_FEE_BPS, 0); // rMax = 0
    }

    function testFuzz_FeeCurve_Bounded(int256 retention) public pure {
        uint256 fee = _fee(retention);
        assertGe(fee, BASE_FEE_BPS, "never below base");
        assertLe(fee, SHOCK_FEE_BPS, "never above shock");
    }

    function testFuzz_FeeCurve_Monotonic(int256 a, int256 b) public pure {
        vm.assume(a <= b);
        assertLe(_fee(a), _fee(b), "non-decreasing in r");
    }

    /*//////////////////////////////////////////////////////////////
                        RESOLVE (WITH EXEMPTION)
    //////////////////////////////////////////////////////////////*/

    /// @notice THE headline case. A trade moves the price and then absolutely nothing
    ///         happens. Under a P0 anchor this is the worst outcome (full 3%); under
    ///         the retention rule it is a mid-curve hold, and crucially it is bounded.
    function test_Silence_ResolvesFair() public pure {
        uint256 fee = _resolve(1_300, 1_300); // P* == P1
        assertEq(fee, 165, "silence is a hold, not a conviction");
        assertLt(fee, SHOCK_FEE_BPS, "must never be the full shock fee");
    }

    /// @notice A dust trade placed just before somebody else's 20-point shock must not
    ///         be convicted for information it did not have.
    function test_SubThresholdImpact_IsExempt() public pure {
        uint256 fee = _resolve(5, 2_000); // own impact 0.05 pts, market moved 20 pts
        assertEq(fee, BASE_FEE_BPS, "dust is exempt");
    }

    function test_SubThresholdImpact_ExemptInBothDirections() public pure {
        assertEq(_resolve(-5, -2_000), BASE_FEE_BPS);
    }

    /// @notice At exactly the threshold the exemption no longer applies.
    function test_ThresholdBoundary() public pure {
        assertEq(_resolve(int256(MIN_IMPACT_BPS) - 1, 2_000), BASE_FEE_BPS, "below");
        assertEq(_resolve(int256(MIN_IMPACT_BPS), 2_000), SHOCK_FEE_BPS, "at threshold");
    }

    function test_Resolve_ConfirmedPath() public pure {
        // 50 → 63, then 63 → 67 → 70 → 72.
        assertEq(_resolve(1_300, 2_200), 258);
    }

    function test_Resolve_RevertedPath() public pure {
        // 50 → 63, then 63 → 58 → 54 → 51.
        assertEq(_resolve(1_300, 100), 40);
    }

    /*//////////////////////////////////////////////////////////////
                           ESCROW SPLIT
    //////////////////////////////////////////////////////////////*/

    /// @notice The README's arithmetic: 100 USDC trade, 3.00 escrowed, fair verdict
    ///         returns 2.70 and leaves 0.30 with the LPs.
    function test_Split_FairVerdict_MatchesReadme() public pure {
        (uint256 lp, uint256 rebate) =
            ShockFeeMath.splitEscrow(ESCROW, BASE_FEE_BPS, SHOCK_FEE_BPS);

        assertEq(rebate, 2_700_000, "2.70 USDC rebated");
        assertEq(lp, 300_000, "0.30 USDC base LP fee");
        assertEq(lp + rebate, ESCROW, "conserved");
    }

    function test_Split_ToxicVerdict_AllToLp() public pure {
        (uint256 lp, uint256 rebate) =
            ShockFeeMath.splitEscrow(ESCROW, SHOCK_FEE_BPS, SHOCK_FEE_BPS);

        assertEq(rebate, 0, "no rebate");
        assertEq(lp, ESCROW, "3.00 USDC to LPs");
    }

    function test_Split_MidCurve() public pure {
        (uint256 lp, uint256 rebate) = ShockFeeMath.splitEscrow(ESCROW, 165, SHOCK_FEE_BPS);

        assertEq(lp, 1_650_000, "1.65 USDC");
        assertEq(rebate, 1_350_000, "1.35 USDC");
        assertEq(lp + rebate, ESCROW, "conserved");
    }

    /// @notice A fee above the ceiling can never mint rebate the contract does not hold.
    function test_Split_FeeAboveCeiling_ClampsToLp() public pure {
        (uint256 lp, uint256 rebate) = ShockFeeMath.splitEscrow(ESCROW, 10_000, SHOCK_FEE_BPS);
        assertEq(rebate, 0);
        assertEq(lp, ESCROW);
    }

    /// @notice Escrow is always fully assigned — dust must land with the LPs rather
    ///         than being minted into a rebate or silently lost.
    function testFuzz_Split_Conserved(uint128 escrow, uint256 feeBps_) public pure {
        feeBps_ = bound(feeBps_, 0, SHOCK_FEE_BPS);

        (uint256 lp, uint256 rebate) = ShockFeeMath.splitEscrow(escrow, feeBps_, SHOCK_FEE_BPS);

        assertEq(lp + rebate, escrow, "conserved exactly");
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL WRAPPERS
    //////////////////////////////////////////////////////////////*/

    function _fee(int256 retention) internal pure returns (uint256) {
        return ShockFeeMath.feeBps(retention, BASE_FEE_BPS, SHOCK_FEE_BPS, R_MAX_BPS);
    }

    function _resolve(int256 ownImpact, int256 netMove) internal pure returns (uint256) {
        return ShockFeeMath.resolveFeeBps(
            ownImpact, netMove, MIN_IMPACT_BPS, BASE_FEE_BPS, SHOCK_FEE_BPS, R_MAX_BPS
        );
    }
}
