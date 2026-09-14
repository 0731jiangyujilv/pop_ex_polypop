# POP Resolution — Chainlink CRE

Chainlink CRE is the external resolution layer for POP.

POP's AMM continuously discovers what the market **believes**.  
Chainlink CRE determines what **actually happened** and writes the final result onchain.

> **AMM discovers probability. Chainlink CRE finalizes the outcome.**

---

## Workflow

```text
External Data
     ↓
Chainlink CRE
     ↓
Read Market State on Arc
     ↓
Determine LOCK / RESOLVE
     ↓
Signed CRE Report
     ↓
Chainlink Forwarder
     ↓
POP Market Contract
     ↓
Onchain Settlement
     ↓
Public Redeem / Private Redeem
```

The workflow uses:

- `CronCapability` — monitors active markets
- `EVMClient` — reads market state on Arc
- `HTTPClient` — fetches external resolution data
- `runtime.report()` — creates a signed EVM report
- `writeReport()` — delivers the report onchain

---

## Market Lifecycle

CRE can trigger two onchain state transitions:

```text
OPEN → LOCKED → RESOLVED
```

- **LOCK** — closes trading when the market reaches its deadline
- **RESOLVE** — determines the final YES / NO outcome using external data

Once resolved, the winning outcome can proceed to USDC settlement.

---

## Private Redeem

After a market is resolved, POP can route eligible payouts through the existing private-redeem flow.

```text
RESOLVED
   ↓
Winning Position
   ↓
Private Redeem
   ↓
Policy / Privacy Layer
   ↓
USDC Payout
```

This privacy layer comes from the original PolyPOP implementation and remains part of the broader settlement stack.

The core CRE responsibility is still market resolution; private redeem is an optional post-resolution settlement path.

---

## Files

- [`main.ts`](./main.ts) — CRE resolution workflow
- [`workflow.yaml`](./workflow.yaml) — workflow configuration
- [`config.staging.json`](./config.staging.json) — Arc testnet config
- [`config.production.json`](./config.production.json) — production config

Onchain receiver:

- [`../../contracts/src/interfaces/ReceiverTemplate.sol`](../../contracts/src/interfaces/ReceiverTemplate.sol)
- [`../../contracts/src/BinaryPredictionMarket.sol`](../../contracts/src/BinaryPredictionMarket.sol)

---

## Run

```bash
cre workflow simulate . \
  --target staging-settings
```

With onchain broadcast:

```bash
cre workflow simulate . \
  --target staging-settings \
  --broadcast
```

---

## Continuity

This CRE settlement workflow was originally built for PolyPOP and remains the trusted external resolution layer as POP evolves toward a continuously tradable AMM.

**Trading evolves. Resolution stays verifiable.**
