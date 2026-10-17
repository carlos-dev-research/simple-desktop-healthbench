# Research: 002 evaluation core

**Date:** 2026-10-17 · Reference: `pygrader/` in the reference repo (models.py, tools.py, grader.py, runner.py), studied line by line.

## R1. OpenAI client: write our own

| Option | Verdict |
|---|---|
| `openai_dart` (davidmiguel.com, 11.0.1), `dart_openai` (gwhyyy.com, 8.0.0) | **Not Flutter Favorites**, so not allowed (Constitution IX). `openai_dart` also doesn't automatically retry 5xx errors on POST requests, but the reference relies on the official SDK retrying them |
| **Our own minimal client on `package:http`** (dart.dev, 1.6.0, first-party) | We only need one endpoint (`POST {baseUrl}/chat/completions`). `MockClient` makes it unit-testable. **Chosen** |

The client is written in the core (pure Dart, Article VI).

## R2. Retry policy, matching the official Python SDK the reference used

The reference builds `OpenAI(max_retries=4, timeout=180)`, so it gets the SDK's retry logic. Ported from `openai-python` `_base_client.py`:

- **Retried:** HTTP **408, 409, 429, ≥ 500**, plus timeouts and connection errors. The `x-should-retry: true/false` response header overrides this.
- **Wait before attempt *n*:**
  - If the server sends `retry-after-ms` or `retry-after` (seconds or an HTTP date) with a value of 60 s or less, wait exactly that long.
  - Otherwise, wait `min(0.5 s × 2ⁿ, 8 s)`, reduced by a random 0–25%.
- **Max retries 4, timeout 180 s per request** (spec FR-007).
- **Errors that will repeat every time and stop the run** (the reference's `FATAL_ERRORS`): **401, 403, 404**. They are never retried.
- Any other 4xx (for example 400 or 422) isn't retried and fails that conversation only, like the reference's generic `Exception` path.

For tests, the timeout, retry count and backoff base can be set through `ClientOptions`, so tests run in milliseconds.

## R3. Grader prompt and filling it in

- The template is the reference `GRADER.md`, stored as a Dart constant with single braces (the reference doubles `{{ }}` only because Python's `str.format` needs it).
- **It is filled in a single pass**, using one regular expression over `{prompt}`, `{completion}` and `{criterion}`. Replacing them one after another could substitute placeholders that appear *inside* model output, such as a reply containing the text "{criterion}".
- The conversation is turned into text as `"<role>\n<content>"`, with a blank line between messages, as in `grade_prompt`.
- The run file records `graderPrompt.id = "pygrader-GRADER.md"` and the SHA-256 of the template text (spec FR-009).

## R4. Reading the grader's answer

- Port `get_result` exactly: scan for balanced `{…}` and parse the candidate. If it doesn't parse, reset and keep scanning. The first object that parses wins. The scan does not track string literals (same as the reference). Any difference in behaviour would make results stop matching the toolkit.
- **`criteria_met`:** a JSON boolean is accepted. The strings `"true"` and `"false"` (any case) are accepted as well (spec edge case). Anything else, including a missing value, fails that conversation's grading with the reason "grader answer has no valid criteria_met". The reference would crash on `int("true")`, so this is a deliberate, documented tolerance.
- **`explanation`:** a missing explanation is stored as an empty string.

## R5. Request bodies, matching the reference exactly

- **Model under test:** `{model, messages: <conversation unchanged>, temperature: 0.3, reasoning_effort?}`.
- **Grader:** `{model, messages: [{role: user, content: <filled template>}], temperature: 0.3, reasoning_effort?, response_format: {type: json_schema, json_schema: {name: grading_result, schema: {explanation: string, criteria_met: boolean, required both, additionalProperties: false}}}}`.
- `reasoning_effort` is sent only for `low`, `medium` and `high` (spec FR-005).
- The reply is `choices[0].message.content`. A missing or empty value, or no choices at all, fails the conversation with the reason "empty reply".

## R6. Run-file shape: append-only events

The status has to change over time (running → stopped → running → completed), but rewriting the file risks losing it in a crash. **Decision: the file is never rewritten, only appended to.** It contains three line types:
- `header`: line 1, exactly once.
- `conversation`: one per graded conversation.
- `status`: added at start, stop, continue, completion and failure.

The **current status is the last `status` line**. If that says `running` but the run isn't active in this app, the run is shown as **interrupted**. That status is derived when reading and never written. Full format: [contracts/run-file.md](contracts/run-file.md).

## R7. File name and timestamp

- **File name:** `healthbench-run-YYYYMMDD-HHMMSS.jsonl`, in **local** time so people recognise it, like the reference's `test-<timestamp>`. If two runs start in the same second, `-2`, `-3`, … is added.
- **Pattern:** `^healthbench-run-\d{8}-\d{6}(-[1-9]\d*)?\.jsonl$`.
- **Header:** `createdAt` is ISO-8601 *with* the UTC offset, so the time is unambiguous across time zones.

## R8. Identifying the dataset, for continue (spec US5-5)

- The header stores the dataset **file name** (no folder path: paths contain the username and differ between machines), its **SHA-256**, its total conversation count, and the selection limit.
- Continuing requires the caller to supply the dataset file. The core recomputes the SHA-256 and refuses if it differs.
- SHA-256 comes from `package:crypto` (dart.dev, 3.0.7, first-party), because the Dart SDK has no SHA-256.
- **Duplicate `prompt_id`s** in a dataset are rejected when it's read, because continuing depends on unique ids.

## R9. Base URL in the run file

The base URL is needed to continue a run (US5-3: everything except the key comes from the file). But base URLs *can* carry credentials (`https://user:pass@host`, `?key=`). **Decision:** the core rejects base URLs that have user info, a query or a fragment, and accepts only `http` or `https`. A base URL that passes validation contains no secret, so storing it is safe.

## R10. Making writes durable (NFR-004)

Each line is written with `RandomAccessFile` in append mode, followed by `flush()`, which forces the data to disk, **before** the next conversation starts. When continuing, if the file doesn't end with a newline, it is truncated back to the last newline before anything is appended (US5-4).

## R11. Reading the dataset off the caller's thread (NFR-003)

Read the bytes asynchronously, compute the SHA-256, then parse with `Isolate.run`, which runs on a separate Dart isolate. Both are pure Dart.

## R12. Size limits (NFR-005, Article IV)

| Item | Limit | When exceeded |
|---|---|---|
| Dataset line | 8 MB | The read fails, naming the line |
| Run-file line | 16 MB | Rejected as invalid |
| HTTP response body | 16 MB | That conversation fails ("response too large") |

The limits are far above real data (the largest HealthBench lines are tens of KB).

## R13. Stopping during a retry (spec edge case)

FR-015 says a stop takes effect *after* the current conversation, so a stop requested during a retry wait still lets that conversation finish or fail. In the worst case that's 5 attempts × 180 s. **Decision:** keep FR-015 as written. The progress report shows "stopping after current conversation" so the user knows the stop was registered. If that proves too slow in practice, a "stop now" option (which discards the current conversation) would be a spec change for the UI feature.

## R14. One active run per file

The core keeps an in-memory set of run files that are currently active. Starting or continuing a run whose file is already active is refused (spec edge case). Locking between separate processes isn't needed: the app runs as a single instance.

## R15. Verifying outgoing network access in the sandboxed app (carried over from 001 US3-3)

002 has no UI, so its core can't be exercised inside the *release* app yet. **Decision:**
- An **integration test** (`integration_test/network_test.dart`) runs inside the sandboxed macOS app (a debug build). It starts a local fake endpoint and makes a real HTTP request to it through the core client. This proves outgoing connections work in the sandbox.
- The release-build check against a real endpoint moves to feature 003, the first one with a UI. See plan S1.

## R16. Trying a real endpoint by hand before the UI exists

`tool/try_run.dart`, run with `fvm dart run`, is a **developer-only script**. It is not part of the app and not shipped, and it uses the core directly. It reads the key from the `HEALTHBENCH_API_KEY` environment variable, never stores it, and runs N conversations against a real endpoint. This lets you validate 002 against Groq before 003. See plan S2: it needs your approval.
