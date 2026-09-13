# Uniswap Developer Feedback

## Project

**POP** is an AMM-based prediction market using Uniswap for both asset routing and prediction-market liquidity.

### Relevant code

Trading API:
- [`webapp/src/lib/uniswapApi.ts`](./webapp/src/lib/uniswapApi.ts)
- [`webapp/src/lib/uniswap.ts`](./webapp/src/lib/uniswap.ts)

Uniswap v4 / OddsShift Hook:
- [`contracts-v2/src/v4/OddsShiftHook.sol`](./contracts-v2/src/v4/OddsShiftHook.sol)
- [`contracts-v2/src/v4/OddsShiftHookHelper.sol`](./contracts-v2/src/v4/OddsShiftHookHelper.sol)
- [`contracts-v2/src/v4/OutcomeTokenV4.sol`](./contracts-v2/src/v4/OutcomeTokenV4.sol)
- [`contracts-v2/src/v4/libraries/ShockFeeMath.sol`](./contracts-v2/src/v4/libraries/ShockFeeMath.sol)

## How We Use Uniswap

POP uses the Uniswap Trading API to route users into USDC before entering a market.

```text
ETH / other asset
        ↓
Uniswap Trading API
        ↓
       USDC
        ↓
    POP Market
```

The integration includes quote requests, approval checks, swap transaction construction, routing, slippage, gas estimates and price-impact data.

POP also uses Uniswap v4 as the AMM layer for YES / NO prediction markets.

```text
USDC
 ↓
YES + NO
 ↓
Uniswap v4 Pool
 ↓
Live Probability
```

## OddsShift Hook

**OddsShift** is the Uniswap v4 Hook used by POP to make prediction-market liquidity more adaptive during information shocks.

Prediction markets are highly event-driven. When new information arrives, probabilities can move quickly. On order-book venues, active market makers can widen spreads, reduce size or pull quotes. AMM liquidity is passive and always available, so repricing costs need to be handled differently.

The OddsShift Hook introduces a conditional fee-rebate mechanism:

```text
Trade
  │
  ├── Base Fee → LPs
  │
  └── Conditional Fee → Escrow
                         │
                ┌────────┴────────┐
                │                 │
        move persists       move reverses
                │                 │
                ▼                 ▼
               LPs          trader rebate
```

If the probability move persists, more value is retained for LPs. If the move reverses, part of the provisional fee can be returned to the trader.

The mechanism is market-driven and does not require an external news oracle.

Relevant implementation:
- `OddsShiftHook.sol` — market lifecycle and v4 Hook logic
- `OddsShiftHookHelper.sol` — single-sided YES / NO entry
- `ShockFeeMath.sol` — probability, retention and adaptive fee math
- `OutcomeTokenV4.sol` — YES / NO outcome tokens

## What Worked Well

- Trading API makes asset routing easy to embed inside a larger product flow.
- v4 Hooks are a natural fit for prediction markets because markets have explicit trading and resolution states.
- Pool price can map directly to prediction-market probability.
- Hook logic makes it possible to add prediction-market-specific fee behavior without rebuilding the AMM core.
- PoolManager provides a useful shared architecture for many individual markets.

## Friction

- A complete Trading API example covering quote → approval → permit → swap execution would help.
- PoolManager and Hook settlement flows have a relatively steep learning curve.
- Single-sided flows such as `USDC → Buy YES` require additional helper logic.
- More examples of dynamic fees, temporary fee state and conditional rebates would be useful for event-driven markets.
- More lightweight testing examples for PoolManager + custom Hooks would improve development speed.

## Overall

For POP, Uniswap is useful at two layers:

> **Uniswap helps users get into the market.**

and

> **Uniswap can become the market.**

The Trading API reduces entry friction, while Uniswap v4 provides the programmable AMM layer. OddsShift extends that layer with adaptive fee logic designed specifically for information shocks in prediction markets.
