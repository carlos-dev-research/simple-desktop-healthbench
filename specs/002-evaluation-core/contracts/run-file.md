# Contract: run file

One run = one UTF-8 file of JSON lines (`\n`-terminated), **appended only, never rewritten**.

## File name

```
healthbench-run-YYYYMMDD-HHMMSS[-N].jsonl          e.g. healthbench-run-20261017-163000.jsonl
regex: ^healthbench-run-\d{8}-\d{6}(-[1-9]\d*)?\.jsonl$
```

The time is the run's start time, in local time. `-N` is added only if a file with that name already exists.
The **run id** is the file name without `.jsonl`.

## Line types

Every line is a JSON object with a `"type"` field. Field names are camelCase.

### 1. `header`: line 1, exactly once

```jsonc
{
  "type": "header",
  "runId": "healthbench-run-20261017-163000",
  "app": "HealthBench Evals",
  "appVersion": "0.1.0",
  "createdAt": "2026-10-17T16:30:00.000-05:00",       // ISO-8601 with offset
  "baseUrl": "https://api.groq.com/openai/v1",         // http(s); no user info, query or fragment
  "modelTest":   { "name": "openai/gpt-oss-20b", "reasoningEffort": "low" },   // "none" | "low" | "medium" | "high"
  "modelGrader": { "name": "openai/gpt-oss-20b", "reasoningEffort": "low" },
  "temperature": 0.3,
  "graderPrompt": { "id": "pygrader-GRADER.md", "sha256": "<64 hex>" },
  "dataset": {
    "fileName": "2025-05-07-06-14-12_oss_eval.jsonl",  // name only, never a folder path
    "sha256": "<64 hex>",
    "conversationCount": 5000,                        // conversations in the file
    "limit": 10                                       // null = all
  }
}
```

### 2. `status`: any number of times, after the header

```jsonc
{
  "type": "status",
  "status": "running",            // "running" | "stopped" | "completed" | "failed"
  "at": "2026-10-17T16:30:00.120-05:00",
  "graded": 0,                    // conversation lines in the file at this point
  "score": null,                  // run score over all graded conversations; required number when status is "completed"
  "reason": null                  // required non-empty string when status is "failed"; otherwise null
}
```

The first `status` line comes immediately after the header (`running`). Continuing appends another `running` line.

### 3. `conversation`: one per graded conversation

```jsonc
{
  "type": "conversation",
  "index": 0,                     // 0-based position in the dataset
  "promptId": "…",
  "exampleTags": ["theme:emergency_referrals"],
  "prompt": [ { "role": "user", "content": "…" } ],
  "completion": "…",              // reply of the model under test (Markdown, untrusted)
  "rubrics": [
    {
      "criterion": "…",
      "points": 7,                // integer, may be negative
      "tags": ["axis:accuracy", "level:example"],
      "criteriaMet": true,
      "explanation": "…"
    }
  ],
  "gradedAt": "2026-10-17T16:31:02.004-05:00"
}
```

## Validation rules (applied when reading; any failure rejects the whole file with a reason)

| ID | Rule |
|---|---|
| RF-1 | The file name matches the pattern, and `header.runId` equals the file name without `.jsonl` |
| RF-2 | Line 1 is a valid `header`, and no other line is a header |
| RF-3 | Every line is a JSON object of 16 MB or less, with a known `type` and all required fields of the right JSON type. Extra fields are rejected |
| RF-4 | `reasoningEffort` is one of the four values. `temperature` is a number. Hashes are 64 lowercase hex characters. Timestamps parse as ISO-8601 |
| RF-5 | There is at least one `status` line. `score` and `reason` follow the rules above |
| RF-6 | `conversation` lines have unique `promptId` and unique `index`, with `0 ≤ index < dataset.conversationCount` |
| RF-7 | Each `status.graded` equals the number of conversation lines before it. For `completed`, `score` equals the recomputed run score (within 1e-9) |
| RF-8 | `baseUrl` follows the R9 rules (http/https, no user info, query or fragment) |
| RF-9 | Only the **last** line may be incomplete (no trailing newline, and it doesn't parse). It is ignored when reading and truncated before appending. An invalid line anywhere else rejects the file |

## Derived when reading (never written)

- **Current status** = the last `status` line. It is reported as **interrupted** if it's `running` and the run isn't active in this app.
- **Conversation score**, **run score** and **criterion outcomes** are recomputed from the `rubrics`, using healthbench.md §5.
- **Done set** = the `promptId`s that have conversation lines. Continuing evaluates every selected conversation not in this set.

## Never in the file

The API key. Any folder path. (A base URL that passes R9 contains no secrets.)
