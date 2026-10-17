# Contract: OpenAI-compatible chat client

`POST {baseUrl}/chat/completions`, with headers `Authorization: Bearer <apiKey>` and `Content-Type: application/json`.

## Requests

| Call | Body |
|---|---|
| Generate (model under test) | `{"model", "messages": <conversation messages unchanged>, "temperature": 0.3, "reasoning_effort"?}` |
| Grade one criterion | `{"model", "messages": [{"role":"user","content": <filled grader prompt>}], "temperature": 0.3, "reasoning_effort"?, "response_format": {"type":"json_schema","json_schema":{"name":"grading_result","schema":{"type":"object","properties":{"explanation":{"type":"string"},"criteria_met":{"type":"boolean"}},"required":["explanation","criteria_met"],"additionalProperties":false}}}}` |

- `reasoning_effort` is present only for `low`, `medium` and `high`.
- The answer is `choices[0].message.content`, which must be a non-empty string.

## Outcomes

| Response | Classification | Retried? | Effect on the run |
|---|---|---|---|
| 2xx with valid content | success | — | — |
| 2xx, no choices or empty content | `EmptyReplyError` | no | this conversation fails |
| 2xx, body > 16 MB or not JSON | `BadResponseError` | no | this conversation fails |
| 401 | `AuthenticationError` (fatal) | no | **the run stops (failed)** |
| 403 | `PermissionDeniedError` (fatal) | no | **the run stops (failed)** |
| 404 | `NotFoundError` (fatal: unknown model or endpoint) | no | **the run stops (failed)** |
| 408, 409, 429, ≥ 500 | `TransientError` | yes, up to 4 | after the retries: this conversation fails |
| Timeout (180 s) or connection error | `TransientError` | yes, up to 4 | after the retries: this conversation fails |
| Other 4xx | `RequestError` | no | this conversation fails |

The `x-should-retry: true|false` header overrides the "Retried?" column for non-fatal statuses.

## Backoff

Before retry *n* (0-based):
- If `retry-after-ms` or `retry-after` (seconds or an HTTP date) is between 0 and 60 s, wait exactly that long.
- Otherwise wait `min(0.5 × 2ⁿ, 8)` s × (1 − 0.25 × random).

## Error messages

They contain the error kind, the HTTP status, and the server's `error.message` (truncated to 500 characters). Every occurrence of the API key is replaced with `***` before a message leaves the client. Exceptions never carry request headers.
