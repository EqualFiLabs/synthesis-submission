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
