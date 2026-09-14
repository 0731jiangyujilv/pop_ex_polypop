# POP × Chainlink CRE

Chainlink CRE is the resolution and settlement automation layer for POP.

POP's AMM discovers what the market **believes**.  
Chainlink CRE determines what **actually happened**, signs the result, and delivers it onchain.

> **AMM discovers probability. Chainlink CRE finalizes the outcome.**

---

## How It Works

```text
External Data
     ↓
Chainlink CRE
     ↓
Read POP Market State on Arc
     ↓
Determine LOCK / RESOLVE
     ↓
Signed CRE Report
     ↓
Chainlink Forwarder
     ↓
POP Market Contract
     ↓
Onchain State Change
     ↓
USDC Settlement
```

CRE is used for:

- automated market monitoring
- external resolution data
- onchain state reads
- signed EVM reports
- onchain lock / resolution
- settlement automation

The integration uses:

`CronCapability` · `HTTPClient` · `EVMClient` · `runtime.report()` · `writeReport()`

---

## Onchain Lifecycle

Chainlink CRE can drive the market through:

```text
OPEN → LOCKED → RESOLVED
```

A valid CRE report is delivered through the Chainlink Forwarder and processed by the POP receiver contract.

After resolution:

```text
Winning Position
      ↓
Public Redeem
      or
Private Redeem
      ↓
USDC Payout
```

Private redeem remains an optional post-resolution settlement path inherited from PolyPOP.

---

## CRE Workflow

Main workflow:

- [`pop-resolution/`](./pop-resolution/)
- [`pop-resolution/main.ts`](./pop-resolution/main.ts)
- [`pop-resolution/README.md`](./pop-resolution/README.md)

Network configuration:

- [`project.yaml`](./project.yaml)

Onchain receiver:

- [`../contracts/src/interfaces/ReceiverTemplate.sol`](../contracts/src/interfaces/ReceiverTemplate.sol)
- [`../contracts/src/BinaryPredictionMarket.sol`](../contracts/src/BinaryPredictionMarket.sol)

---

## Run

```bash
cre workflow simulate ./pop-resolution \
  --target staging-settings
```

Broadcast the signed report onchain:

```bash
cre workflow simulate ./pop-resolution \
  --target staging-settings \
  --broadcast
```

---

## Continuity

PolyPOP originally used Chainlink CRE to automate binary-market resolution.

For POP, the trading layer evolves into a continuously tradable AMM while CRE remains the trusted external resolution layer.

```text
PolyPOP                         POP

Pooled Market                  AMM Market
     │                             │
     └──── Chainlink CRE ──────────┘
               │
               ▼
        Onchain Resolution
```

**Trading evolved. Chainlink CRE remains the settlement engine.**
