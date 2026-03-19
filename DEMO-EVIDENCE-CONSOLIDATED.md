# Demo Evidence (Consolidated)

Generated: 2026-03-19T03:09:58Z

This document combines all demo evidence artifacts into a single file for judges/reviewers.

## Included Sources

- `LIFECYCLE-OUTPUTS.md`
- `LIFECYCLE-OUTPUTS-LAMBDA-RUNPOD.md`
- `PURE-FINANCING-TIMEWARP-OUTPUTS.md`
- `RUNPOD-REAL-JOB-LOG.md`
- `LOCAL-DEPLOY.md`

---

## Source: `LIFECYCLE-OUTPUTS.md`

# Lifecycle Outputs (Selected Providers)

## Bankr Lifecycle Retest (2026-03-19T03:09:22Z)

This retest confirms Bankr activation and final-pass metering/settlement:

- `providerResultStatus: "ok"`
- Usage seed call succeeded (`httpStatus: 200`)
- Final-pass metering on breach prepared usage (`submissionId: 1a7dbb4e-8ebd-499f-9ab2-f274f8117492`)
- Settlement succeeded (`txHash: 0xsettled-177388974701-1773889762572`)

```json
{
  "runAt": "2026-03-19T03:09:22Z",
  "selectedLifecycles": ["bankr"],
  "providers": {
    "bankr": {
      "agreementId": "177388974701",
      "activation": {
        "results": [
          {
            "meta": {
              "providerResultStatus": "ok",
              "providerResourceId": "bankr:177388974701"
            }
          }
        ]
      },
      "usageSeed": {
        "status": "ok",
        "httpStatus": 200,
        "model": "claude-opus-4.6"
      },
      "breach": {
        "results": [
          {
            "meta": {
              "finalMetering": {
                "status": "prepared",
                "usageRows": 2,
                "preparedItems": 2,
                "submissionId": "1a7dbb4e-8ebd-499f-9ab2-f274f8117492"
              }
            }
          }
        ]
      }
    }
  },
  "postBreachSettlement": {
    "processed": 1,
    "settled": 1,
    "failed": 0,
    "results": [
      {
        "status": "ok",
        "settled": true,
        "txHash": "0xsettled-177388974701-1773889762572"
      }
    ]
  }
}
```

## RunPod Activation Retest (2026-03-19T02:34:16Z)

This retest confirms the RunPod activation path is fixed:

- `providerResultStatus: "ok"`
- `providerResourceId: "iv85r0j8t8ubau"`
- Remaining gap: usage job stayed `IN_QUEUE`, so metering remained `no_usage` in this run.

```json
{
  "runAt": "2026-03-19T02:34:16Z",
  "selectedLifecycles": ["runpod"],
  "providers": {
    "runpod": {
      "agreementId": "177388750601",
      "activation": {
        "results": [
          {
            "meta": {
              "providerResultStatus": "ok",
              "providerResourceId": "iv85r0j8t8ubau"
            }
          }
        ]
      },
      "usageSeed": {
        "status": "partial",
        "reason": "job_not_completed_in_window",
        "finalStatus": "IN_QUEUE"
      },
      "metering": {
        "results": [
          {
            "status": "no_usage"
          }
        ]
      },
      "checks": {
        "activationAccepted": true,
        "providerProvisioned": true,
        "meteringPrepared": false,
        "submissionCount": 0,
        "settlementCount": 0
      }
    }
  }
}
```

```json
{
  "runAt": "2026-03-19T02:04:12Z",
  "detectedProviders": [
    "venice",
    "runpod"
  ],
  "selectedLifecycles": [
    "venice",
    "runpod"
  ],
  "providers": {
    "venice": {
      "agreementId": "177388580901",
      "activation": {
        "accepted": 1,
        "deduped": 0,
        "rejected": 0,
        "results": [
          {
            "accepted": true,
            "deduped": false,
            "eventKey": "31337:1858090:1",
            "eventType": "activation",
            "agreementId": "177388580901",
            "provider": "venice",
            "action": "activation_processed",
            "meta": {
              "providerResultStatus": "ok",
              "providerResourceId": "ea08ad26-33dc-4f3d-859a-c388f494c0ee"
            }
          }
        ]
      },
      "usageSeed": {
        "status": "ok",
        "httpStatus": 200,
        "model": "venice-uncensored",
        "responsePath": "/tmp/venice_usage_seed_response.json"
      },
      "metering": {
        "agreementsScanned": 1,
        "preparedCount": 1,
        "results": [
          {
            "agreementId": "177388580901",
            "provider": "venice",
            "status": "prepared",
            "to": "2026-03-19T02:03:50.772Z",
            "usageRows": 32,
            "aggregatedItems": [
              {
                "unitType": "VENICE_TEXT_TOKEN_IN",
                "amount": "0.596235"
              },
              {
                "unitType": "VENICE_TEXT_TOKEN_OUT",
                "amount": "0.00232"
              }
            ],
            "finalPass": false,
            "submissionId": "9c48e47f-9e91-45f2-af11-fe711de739f7"
          }
        ]
      },
      "submissions": {
        "submissions": [
          {
            "id": "9c48e47f-9e91-45f2-af11-fe711de739f7",
            "agreementId": "177388580901",
            "provider": "venice",
            "to": "2026-03-19T02:03:50.772Z",
            "usageDigest": "90aafd263b475bc21b59e7abac5a3d897f6f7a8e4b80077fea325f720c6e7dba",
            "items": [
              {
                "unitType": "VENICE_TEXT_TOKEN_IN",
                "amount": "0.596235"
              },
              {
                "unitType": "VENICE_TEXT_TOKEN_OUT",
                "amount": "0.00232"
              }
            ],
            "finalPass": false,
            "createdAt": "2026-03-19T02:03:51.143Z",
            "settlement": null
          }
        ]
      },
      "settlementBeforeBreach": {
        "processed": 1,
        "settled": 1,
        "failed": 0,
        "results": [
          {
            "processed": 1,
            "settled": 1,
            "failed": 0,
            "results": [
              {
                "id": "712dbdcc-3fd8-4f29-b5d4-5b5ad6e58563",
                "submissionId": "9c48e47f-9e91-45f2-af11-fe711de739f7",
                "agreementId": "177388580901",
                "provider": "venice",
                "attempt": 1,
                "status": "ok",
                "settled": true,
                "txHash": "0xsettled-177388580901-1773885831166",
                "at": "2026-03-19T02:03:51.168Z"
              }
            ]
          }
        ]
      },
      "breach": {
        "accepted": 1,
        "deduped": 0,
        "rejected": 0,
        "results": [
          {
            "accepted": true,
            "deduped": false,
            "eventKey": "31337:1858091:1",
            "eventType": "risk_covenant_breached",
            "agreementId": "177388580901",
            "provider": "venice",
            "action": "termination_attempted",
            "meta": {
              "drawFrozen": true,
              "terminationAttempt": {
                "attempt": 1,
                "status": "ok",
                "terminated": true
              },
              "finalMetering": {
                "status": "no_usage",
                "usageRows": 0,
                "preparedItems": 0
              }
            }
          }
        ]
      },
      "close": {
        "accepted": 1,
        "deduped": 0,
        "rejected": 0,
        "results": [
          {
            "accepted": true,
            "deduped": false,
            "eventKey": "31337:1858092:1",
            "eventType": "agreement_closed",
            "agreementId": "177388580901",
            "provider": "venice",
            "action": "agreement_closed_recorded"
          }
        ]
      },
      "finalState": {
        "agreementId": "177388580901",
        "state": "closed",
        "updatedAt": "2026-03-19T02:03:52.411Z"
      },
      "checks": {
        "activationAccepted": true,
        "providerProvisioned": true,
        "meteringPrepared": true,
        "submissionCount": 1,
        "settlementCount": 1
      }
    },
    "runpod": {
      "agreementId": "177388580902",
      "activation": {
        "accepted": 1,
        "deduped": 0,
        "rejected": 0,
        "results": [
          {
            "accepted": true,
            "deduped": false,
            "eventKey": "31337:1868090:1",
            "eventType": "activation",
            "agreementId": "177388580902",
            "provider": "runpod",
            "action": "activation_processed",
            "meta": {
              "providerResultStatus": "error"
            }
          }
        ]
      },
      "usageSeed": {
        "status": "skipped",
        "reason": "missing_provider_resource_id"
      },
      "metering": {
        "agreementsScanned": 1,
        "preparedCount": 0,
        "results": [
          {
            "agreementId": "177388580902",
            "provider": "venice",
            "status": "skipped",
            "to": "2026-03-19T02:04:12.802Z",
            "usageRows": 0,
            "aggregatedItems": [],
            "finalPass": false,
            "message": "no provider link found for agreement"
          }
        ]
      },
      "submissions": {
        "submissions": []
      },
      "settlementBeforeBreach": {
        "processed": 0,
        "settled": 0,
        "failed": 0,
        "results": []
      },
      "breach": {
        "accepted": 1,
        "deduped": 0,
        "rejected": 0,
        "results": [
          {
            "accepted": true,
            "deduped": false,
            "eventKey": "31337:1868091:1",
            "eventType": "risk_covenant_breached",
            "agreementId": "177388580902",
            "provider": "runpod",
            "action": "termination_attempted",
            "meta": {
              "drawFrozen": true,
              "terminationAttempt": {
                "attempt": 1,
                "status": "error",
                "terminated": false,
                "nextRetryAt": "2026-03-19T02:04:42.820Z"
              },
              "finalMetering": {
                "status": "skipped",
                "usageRows": 0,
                "preparedItems": 0
              }
            }
          }
        ]
      },
      "close": {
        "accepted": 1,
        "deduped": 0,
        "rejected": 0,
        "results": [
          {
            "accepted": true,
            "deduped": false,
            "eventKey": "31337:1868092:1",
            "eventType": "agreement_closed",
            "agreementId": "177388580902",
            "provider": "runpod",
            "action": "agreement_closed_recorded"
          }
        ]
      },
      "finalState": {
        "agreementId": "177388580902",
        "state": "closed",
        "updatedAt": "2026-03-19T02:04:12.827Z"
      },
      "checks": {
        "activationAccepted": true,
        "providerProvisioned": false,
        "meteringPrepared": false,
        "submissionCount": 0,
        "settlementCount": 0
      }
    }
  },
  "summary": {
    "providerCount": 2,
    "providersWithPreparedUsage": 1,
    "totalSubmissions": 1,
    "totalSettlements": 1
  },
  "postBreachSettlement": {
    "processed": 0,
    "settled": 0,
    "failed": 0,
    "results": []
  },
  "allSubmissions": {
    "submissions": [
      {
        "id": "9c48e47f-9e91-45f2-af11-fe711de739f7",
        "agreementId": "177388580901",
        "provider": "venice",
        "to": "2026-03-19T02:03:50.772Z",
        "usageDigest": "90aafd263b475bc21b59e7abac5a3d897f6f7a8e4b80077fea325f720c6e7dba",
        "items": [
          {
            "unitType": "VENICE_TEXT_TOKEN_IN",
            "amount": "0.596235"
          },
          {
            "unitType": "VENICE_TEXT_TOKEN_OUT",
            "amount": "0.00232"
          }
        ],
        "finalPass": false,
        "createdAt": "2026-03-19T02:03:51.143Z",
        "settlement": {
          "id": "712dbdcc-3fd8-4f29-b5d4-5b5ad6e58563",
          "submissionId": "9c48e47f-9e91-45f2-af11-fe711de739f7",
          "agreementId": "177388580901",
          "provider": "venice",
          "attempt": 1,
          "status": "ok",
          "settled": true,
          "txHash": "0xsettled-177388580901-1773885831166",
          "at": "2026-03-19T02:03:51.168Z"
        }
      }
    ]
  },
  "allSettlementAttempts": {
    "attempts": [
      {
        "id": "712dbdcc-3fd8-4f29-b5d4-5b5ad6e58563",
        "submissionId": "9c48e47f-9e91-45f2-af11-fe711de739f7",
        "agreementId": "177388580901",
        "provider": "venice",
        "attempt": 1,
        "status": "ok",
        "settled": true,
        "txHash": "0xsettled-177388580901-1773885831166",
        "at": "2026-03-19T02:03:51.168Z"
      }
    ]
  }
}
```

---

## Source: `LIFECYCLE-OUTPUTS-LAMBDA-RUNPOD.md`

# Lifecycle Outputs (Live Lambda + RunPod)

Run timestamp (UTC): 2026-03-18T19:36:45Z

## Summary

- Lambda: activation reached provider but returned `providerResultStatus=error`; no provider link, no metering submissions, no settlement attempts.
- RunPod: activation succeeded and resource IDs were created; metering returned `no_usage`; no settlement submissions were created.
- Risk breach/close transitions were processed in relayer state machine for both agreements.

## Latest Lifecycle JSON

```json
{
  "runAt": "2026-03-18T19:36:45Z",
  "lambda": {
    "agreementId": "lambda-live2-1773862562",
    "activation": {
      "accepted": 1,
      "deduped": 0,
      "rejected": 0,
      "results": [
        {
          "accepted": true,
          "deduped": false,
          "eventKey": "31337:950000:1",
          "eventType": "activation",
          "agreementId": "lambda-live2-1773862562",
          "provider": "lambda",
          "action": "activation_processed",
          "meta": {
            "providerResultStatus": "error"
          }
        }
      ]
    },
    "metering": {
      "agreementsScanned": 1,
      "preparedCount": 0,
      "results": [
        {
          "agreementId": "lambda-live2-1773862562",
          "provider": "venice",
          "status": "skipped",
          "to": "2026-03-18T19:36:36.383Z",
          "usageRows": 0,
          "aggregatedItems": [],
          "finalPass": false,
          "message": "no provider link found for agreement"
        }
      ]
    },
    "submissions": {
      "submissions": []
    },
    "settlementAttempts": {
      "attempts": []
    },
    "breach": {
      "accepted": 1,
      "deduped": 0,
      "rejected": 0,
      "results": [
        {
          "accepted": true,
          "deduped": false,
          "eventKey": "31337:950001:1",
          "eventType": "risk_covenant_breached",
          "agreementId": "lambda-live2-1773862562",
          "provider": "lambda",
          "action": "termination_attempted",
          "meta": {
            "drawFrozen": true,
            "terminationAttempt": {
              "attempt": 1,
              "status": "error",
              "terminated": false,
              "nextRetryAt": "2026-03-18T19:37:06.421Z"
            },
            "finalMetering": {
              "status": "skipped",
              "usageRows": 0,
              "preparedItems": 0
            }
          }
        }
      ]
    },
    "close": {
      "accepted": 1,
      "deduped": 0,
      "rejected": 0,
      "results": [
        {
          "accepted": true,
          "deduped": false,
          "eventKey": "31337:950002:1",
          "eventType": "agreement_closed",
          "agreementId": "lambda-live2-1773862562",
          "provider": "lambda",
          "action": "agreement_closed_recorded"
        }
      ]
    },
    "finalState": {
      "agreementId": "lambda-live2-1773862562",
      "state": "closed",
      "updatedAt": "2026-03-18T19:36:45.172Z"
    }
  },
  "runpod": {
    "agreementId": "runpod-live2-1773862562",
    "activation": {
      "accepted": 1,
      "deduped": 0,
      "rejected": 0,
      "results": [
        {
          "accepted": true,
          "deduped": false,
          "eventKey": "31337:960000:1",
          "eventType": "activation",
          "agreementId": "runpod-live2-1773862562",
          "provider": "runpod",
          "action": "activation_processed",
          "meta": {
            "providerResultStatus": "ok",
            "providerResourceId": "ywnw6q0slon38m"
          }
        }
      ]
    },
    "metering": {
      "agreementsScanned": 1,
      "preparedCount": 0,
      "results": [
        {
          "agreementId": "runpod-live2-1773862562",
          "provider": "runpod",
          "status": "no_usage",
          "to": "2026-03-18T19:36:36.390Z",
          "usageRows": 0,
          "aggregatedItems": [],
          "finalPass": false
        }
      ]
    },
    "submissions": {
      "submissions": []
    },
    "settlementAttempts": {
      "attempts": []
    },
    "breach": {
      "accepted": 1,
      "deduped": 0,
      "rejected": 0,
      "results": [
        {
          "accepted": true,
          "deduped": false,
          "eventKey": "31337:960001:1",
          "eventType": "risk_covenant_breached",
          "agreementId": "runpod-live2-1773862562",
          "provider": "runpod",
          "action": "termination_attempted",
          "meta": {
            "drawFrozen": true,
            "terminationAttempt": {
              "attempt": 1,
              "status": "error",
              "terminated": false,
              "nextRetryAt": "2026-03-18T19:37:15.165Z"
            },
            "finalMetering": {
              "status": "no_usage",
              "usageRows": 0,
              "preparedItems": 0
            }
          }
        }
      ]
    },
    "close": {
      "accepted": 1,
      "deduped": 0,
      "rejected": 0,
      "results": [
        {
          "accepted": true,
          "deduped": false,
          "eventKey": "31337:960002:1",
          "eventType": "agreement_closed",
          "agreementId": "runpod-live2-1773862562",
          "provider": "runpod",
          "action": "agreement_closed_recorded"
        }
      ]
    },
    "finalState": {
      "agreementId": "runpod-live2-1773862562",
      "state": "closed",
      "updatedAt": "2026-03-18T19:36:45.180Z"
    }
  },
  "settlementBeforeBreach": {
    "processed": 0,
    "settled": 0,
    "failed": 0,
    "results": []
  },
  "postBreachSettlement": {
    "processed": 0,
    "settled": 0,
    "failed": 0,
    "results": []
  }
}
```

## Verified External Errors

- Lambda launch API currently returns `instance-operations/launch/insufficient-capacity` for tested instance/region combinations.
- RunPod delete endpoint API returns HTTP 500 text, but follow-up GET returns 404 (`endpoint not found`), indicating deletion likely completes despite error response.

## Cleanup Performed

- Retried RunPod endpoint deletions for created resource IDs; post-delete checks returned 404 for all tested IDs.
- Removed temporary Lambda SSH keys created for these lifecycle runs.

---

## Source: `PURE-FINANCING-TIMEWARP-OUTPUTS.md`

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

The current `DeployV1.s.sol` install set does not include `AgenticRiskFacet` selectors by default.
For this lifecycle run, `AgenticRiskFacet` was deployed and added via `diamondCut`:

- Risk facet deployed: `0xe1Fd27F4390DcBE165f4D60DBF821e4B9Bb02dEd`
  - tx: `0xa609a5fc323439adcd3cb6e51d456afa1211ea902b2d697bb2e9a65b1654c349`
- Diamond cut tx (added `detectDelinquency`, `triggerDefault`, etc.):
  - tx: `0x5e5fdb4021b5b564ede01e1977e1c2206a02edeb8552078a2dcdea6ec189df77`

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

---

## Source: `RUNPOD-REAL-JOB-LOG.md`

# RunPod Real Job Log (Judge Evidence)

Generated: 2026-03-18 (UTC)

## Run Summary

- Endpoint tested: `https://api.runpod.ai/v2/iv85r0j8t8ubau/run`
- Result: live `/run` request accepted (`HTTP 200`) with real job ID returned
- Job ID: `7187d301-7117-4e64-aa5d-72e2d78a7ab0-u1`
- Initial status: `IN_QUEUE`
- Follow-up status checks (5 checks): remained `IN_QUEUE`

## Captured Output

```json
{
  "runAt": "2026-03-18T19:50:46Z",
  "endpoint": "https://api.runpod.ai/v2/iv85r0j8t8ubau/run",
  "http": {
    "health": "200",
    "runsync": "",
    "run": "200"
  },
  "job": {
    "id": "7187d301-7117-4e64-aa5d-72e2d78a7ab0-u1",
    "initialStatus": "IN_QUEUE",
    "finalStatus": null,
    "finalPoll": null
  }
}
```

### Health Snapshot

```json
{
  "jobs": {
    "completed": 0,
    "failed": 0,
    "inProgress": 0,
    "inQueue": 2,
    "retried": 0
  },
  "workers": {
    "idle": 2,
    "initializing": 0,
    "ready": 2,
    "running": 0,
    "throttled": 1,
    "unhealthy": 0
  }
}
```

### Run Request Response

```json
{
  "id": "7187d301-7117-4e64-aa5d-72e2d78a7ab0-u1",
  "status": "IN_QUEUE"
}
```

### Follow-Up Status Checks

```json
[
  {
    "id": "7187d301-7117-4e64-aa5d-72e2d78a7ab0-u1",
    "status": "IN_QUEUE"
  },
  {
    "id": "7187d301-7117-4e64-aa5d-72e2d78a7ab0-u1",
    "status": "IN_QUEUE"
  },
  {
    "id": "7187d301-7117-4e64-aa5d-72e2d78a7ab0-u1",
    "status": "IN_QUEUE"
  },
  {
    "id": "7187d301-7117-4e64-aa5d-72e2d78a7ab0-u1",
    "status": "IN_QUEUE"
  },
  {
    "id": "7187d301-7117-4e64-aa5d-72e2d78a7ab0-u1",
    "status": "IN_QUEUE"
  }
]
```

## Judge Notes

- This is a real provider call path using live RunPod API credentials.
- The endpoint accepted the job and issued a valid RunPod job ID.
- The job did not reach a terminal state within the short polling window and stayed queued.
- Latest re-check at `2026-03-18T19:53:35Z`: still `IN_QUEUE`.
- No API secrets are included in this log.

---

## Source: `LOCAL-DEPLOY.md`

# Local Deployment Addresses

Last updated: 2026-03-18 (EntryPoint v0.7 migration defaults)

## Network

- RPC: `http://127.0.0.1:8545`
- Chain ID: `31337` (Anvil)

## ERC-4337 (account-abstraction)

- EntryPoint (v0.7, canonical): `0x0000000071727De22Ee835bAF822C1d29692AA4B`
- SimpleAccountFactory (from `account-abstraction` `releases/v0.7`):
  - Read current address from: `../Projects/account-abstraction/deployments/dev/SimpleAccountFactory.json`
- Deterministic Deployment Proxy (Arachnid): `0x4e59b44847b379578588920ca78fbf26c0b4956c`

## ERC-8004 (vanity deployment)

- SAFE Singleton CREATE2 Factory: `0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7`
  - Funding tx: `0xe5f30ce39d02413bd079d689aeafd8c162400ce44e16770b607f7766a31f11a3`
  - Deploy tx: `0x41a6b731f53cf45627c3976abcb9ecd52fb2142f8f6fbbff4e0bb54a9b3667bc`
- MinimalUUPS placeholder: `0xd53dE688e0b0ad436FBdbDa00036832FF6499234`

### Canonical vanity proxies

- IdentityRegistry: `0x8004A818BFB912233c491871b3d84c89A494BD9e`
- ReputationRegistry: `0x8004B663056A597Dffe9eCcC1965A193B7388713`
- ValidationRegistry: `0x8004Cb1BF31DAf7788923b405b754f57acEB4272`

### Current implementations (after owner-impersonated upgrades)

- IdentityRegistry implementation: `0x92b3F652C385C67300e81cD724DDc2Ab43829041`
  - Upgrade tx: `0xf6f5ac83b633228a2614348ac54aa17efb416473349fe4d9862e052306d396f3`
- ReputationRegistry implementation: `0x62a6cEc2fb9248A32FC131B5f65C18Cd6Fc3E327`
  - Upgrade tx: `0x9a4b69bdaadea6ff46e0c93f2a26b272c900109da73e7809f90937d63026cbd4`
- ValidationRegistry implementation: `0xa57fbf0D1717Cebf662Ce17D0A6B4fC59cE063c3`
  - Upgrade tx: `0x1896e361b723f5b4642410a03d29faa5b270455aa3f0c09733e0fb48765342fa`

- Registry owner: `0x547289319C3e6aedB179C0b8e8aF0B5ACd062603`
- Local deployer account used: `0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266`

## ERC-6551 (reference deployment)

- ERC6551Registry (canonical): `0x000000006551c19487814612e58FE06813775758`
  - Deploy tx: `0x76d0744f85ad1d6bd313a5ef58fc923ce377fb69406b8c2a42e383958ecc4c2f`

## Latest DeployV1 broadcast (EqualFi)

- Broadcast file: `EqualFi/broadcast/DeployV1.s.sol/31337/runDeployV1-latest.json`
- Broadcast commit: `064d4be`
- Broadcast timestamp: `2026-03-17T16:32:57Z`
- Transaction count: `77`

### Core outputs

- Diamond: `0x21df544947ba3e8b3c32561399e88b52dc8b2823`
  - CREATE tx: `0x97a4fa0dde7d466975f4554fc25a7953479e5543b289f227ec64703133e3f5f9`
- PositionNFT: `0x2e2ed0cfd3ad2f1d34481277b3204d807ca2f8c2`
  - CREATE tx: `0xa88b26eb3f39041a68333563762c4ef55d5a5e36eb811df657942c3de9fb0166`
- OptionToken: `0xb0f05d25e41fbc2b52013099ed9616f1206ae21b`
  - CREATE tx: `0x170fbd1cfa61e97e1862f9ecbf46d55a6de63382d5d2a430ced672385e11094e`
- ERC-6900 PositionMSCA implementation: `0x976fcd02f7c4773dd89c309fbf55d5923b4c98a1`
  - CREATE tx: `0x3e496ac49192ea2a633d8abbc5dd1af0a9187efabadd7703184e4a2f2af3addd`

## Notes

- `EqualFi/script/DeployERC6551Registry.s.sol` now no-ops successfully because canonical registry code exists at `0x000000006551c19487814612e58FE06813775758`.
- All addresses above were verified on-chain (non-zero bytecode) on local Anvil.
- Legacy reference (no longer the target): EntryPoint v0.6 was `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789`.

---

