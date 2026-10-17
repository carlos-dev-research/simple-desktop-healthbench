# Data model: 002 evaluation core

The Dart types are in [contracts/core-api.md](contracts/core-api.md). The file format is in [contracts/run-file.md](contracts/run-file.md).

## Entities and validation

| Entity | Fields | Rules |
|---|---|---|
| **Dataset** | fileName, sha256, conversations | No blank lines are counted. `prompt_id`s must be unique. At least 1 conversation |
| **Conversation** | index, promptId, prompt, criteria, exampleTags, idealCompletionsData | `prompt` has ≥ 1 message, each with a string `role` and `content`. `criteria` has ≥ 1 entry. Missing or null tags → `[]` |
| **Criterion** | text, points, tags | `text` is a non-empty string. `points` is an integer (a whole-number float such as `5.0` is accepted). It may be encoded as a JSON string, in which case it is decoded first (healthbench.md §2) |
| **ModelSettings** | name, reasoningEffort | `name` is not empty |
| **ConnectionSettings** | baseUrl, apiKey | baseUrl is `http`/`https` with a host, and no user info, query or fragment. A trailing `/` is removed. apiKey is not empty, **memory only** |
| **Grade** | criterion, criteriaMet, explanation | `criteriaMet` comes from a boolean or `"true"`/`"false"` (research R4) |
| **GradedConversation** | conversation, completion, grades, gradedAt | `grades` has one entry per criterion, in the same order |
| **Run** | runId, header, status, file | See the state machine below |
| **RunProgress** | see core-api | Read-only snapshot, sent as an event |

## Run status

```
            start ──► running ──(all done)──────────► completed
                        │  ▲
          stop() ───────┤  └──── resume() ◄───┬──── stopped
                        ▼                     ├──── failed
                     stopped                  └──── interrupted (derived: last line says running, but the run isn't active)
                        │
   fatal error / 5 failures in a row ──► failed
```

- `resume()` is allowed whenever selected conversations are still missing: from **stopped, failed, interrupted**, and also **completed** with skipped conversations (research R17). It is refused when nothing is left to do, and while that file is already active.
- A start where nothing was graded deletes the file (FR-021). A resume where nothing new was graded keeps the file and appends the final status.

## Score rules (unchanged from healthbench.md §5)

- `conversationScore = Σ points(met) / Σ points(points > 0)`. It is not clipped, and it is `null` if the denominator is 0.
- `runScore = clip(mean(non-null conversation scores), 0, 1)`, and `0` if there are none (as in the reference's `calculate_score`).
- `outcome`:

| Points | Met | Outcome |
|---|---|---|
| > 0 | yes | earned |
| > 0 | no | missed |
| < 0 | yes | penalty |
| < 0 | no | avoided |

A criterion with 0 points is labelled **missed** or **earned**, by its met flag. It doesn't affect the score.
