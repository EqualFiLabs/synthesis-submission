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
