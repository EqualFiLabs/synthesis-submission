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
