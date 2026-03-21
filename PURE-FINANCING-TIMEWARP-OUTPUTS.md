# Pure Financing Lifecycle (Anvil Timewarp)

Run date (UTC): 2026-03-18

## Goal

Prove the pure onchain financing path (no external provider API calls) through:

1. Proposal -> approval -> activation
2. Usage draw registration
3. Timewarp-induced delinquency
4. Timewarp-induced default

## Deployment Context

- Chain: `31337` (Anvil)
- Diamond: `0xC9a43158891282A2B1475592D5719c001986Aaec`
- PositionNFT: `0x1c85638e118b37167e9298c2268758e058DdfDA0`
- Settlement token (local mock): `0xD49a0e9A4CD5979aE36840f542D2d7f02C4817Be`

## Important Note

For this specific lifecycle capture, `AgenticRiskFacet` was deployed and added via `diamondCut`:

- Risk facet deployed: `0xe1Fd27F4390DcBE165f4D60DBF821e4B9Bb02dEd`
  - tx: `0xa609a5fc323439adcd3cb6e51d456afa1211ea902b2d697bb2e9a65b1654c349`
- Diamond cut tx (added `detectDelinquency`, `triggerDefault`, etc.):
  - tx: `0x5e5fdb4021b5b564ede01e1977e1c2206a02edeb8552078a2dcdea6ec189df77`

In the current checkout, `DeployV1.s.sol` includes `AgenticRiskFacet` in `_installAgenticFacets`.

## Financing Inputs

- Pool ID: `1`
- Lender position ID: `1`
- Proposal ID: `1`
- Agreement ID: `1`
- Requested credit: `1000e18`
- Requested units: `1000e18`
- Draw executed via `registerUsage`: `400e18` units at `1e18` price (`principalDrawn = 400e18`)
- Interest params: annual `1200 bps`
- Fee schedule: origination `100 bps`, service `200 bps`, late `300 bps`
- Covenant cure period: `259200` seconds (`3 days`)

## Timewarp + State Transitions

### 1) After usage draw

- Status: `0` (`Active`)
- Tx (`registerUsage`): `0x307309e4cf2f5d8d80e0ba48a1854f61fc4f2b84742a8a9534d4be8ed8d34b50`
- Block/time: `140` / `2026-03-18T13:03:20Z`

### 2) Warp +1 day, accrue interest

- Timewarp: `anvil_increaseTime 86400`, then `evm_mine`
- Tx (`accrueInterest`): `0xa0e20fe880c273f97652805a5803296589bbc04a6881ff092fe8b14762c4b1f1`
- Block/time: `142` / `2026-03-19T13:03:55Z`
- Effect: `interestAccrued` and `feesAccrued` increased from zero

### 3) Warp +2 days +1 second, detect delinquency

- Timewarp: `anvil_increaseTime 172801`, then `evm_mine`
- Tx (`detectDelinquency`): `0x733bd556f7a00de37d20d8d2c3437bd7d30e7d19253d3b588776012c8d7410e3`
- Block/time: `144` / `2026-03-21T13:03:56Z`
- Status transition: `0 -> 2` (`Active -> Delinquent`)

### 4) Warp +3 days +1 second, trigger default

- Timewarp: `anvil_increaseTime 259201`, then `evm_mine`
- Tx (`triggerDefault`): `0x99b63aa9346621a2b49a530b7e017577d38d4f3a8197ec2bdfc7bdf83ba3f53e`
- Block/time: `146` / `2026-03-24T13:03:57Z`
- Status transition: `2 -> 3` (`Delinquent -> Defaulted`)

## Agreement Snapshots (Decoded Tuple Excerpts)

- After usage: status `0`, principalDrawn `400e18`
- After day-1 accrual: status `0`, interest/fees accrued
- After delinquency: status `2`
- After default: status `3`

Raw snapshot values are saved in:

- `/tmp/pure-finance/agreement_after_usage.txt`
- `/tmp/pure-finance/agreement_after_day1_accrual.txt`
- `/tmp/pure-finance/agreement_after_delinquency.txt`
- `/tmp/pure-finance/agreement_after_default.txt`

## Machine Summary

```json
{
  "runAt": "2026-03-18T20:14:15Z",
  "detectDelinquencyTx": "0x733bd556f7a00de37d20d8d2c3437bd7d30e7d19253d3b588776012c8d7410e3",
  "triggerDefaultTx": "0x99b63aa9346621a2b49a530b7e017577d38d4f3a8197ec2bdfc7bdf83ba3f53e"
}
```
