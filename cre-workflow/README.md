# CRE Workflows

This repository now contains two CRE workflows:

- `por`
  Legacy proof-of-reserve workflow for stats verification
- `prediciton market`
  Hackathon workflow for the AMM prediction market data feed on Arc

## Binary Weather Workflow

Path:

- [cre-workflow/pop-resolution/main.ts](/Users/just/workspace/aibkh/chainlink/arc-uni-polypop/cre-workflow/pop-resolution/main.ts)

Purpose:

- scan binary markets from the Arc market factory
- send `lock` reports after the 10 minute betting window closes
- fetch weather forecast
- send `resolve(0/1)` reports after the market duration elapses

Docs:

- [cre-workflow/pop-resolution/README.md](/Users/just/workspace/aibkh/chainlink/arc-uni-polypop/cre-workflow/pop-resolution/README.md)

## Important notes

- The new hackathon demo no longer depends on Chainlink Automation for settlement.
- The binary market contract is CRE-ready through `ReceiverTemplate`.
- You must set the correct Arc CRE forwarder in the factory before creating markets.
