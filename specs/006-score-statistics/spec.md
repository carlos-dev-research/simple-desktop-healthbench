# Feature: Score statistics

**Status:** Approved · **Date:** 2026-10-18 · **Constitution:** v1.2.0

## Summary

A run's summary shows, next to the run score:
- the **median** conversation score;
- the **standard deviation** of the conversation scores, which says how spread out they are;
- a **bootstrap standard deviation** of the run score, which says how much it would move with a different sample of conversations.

OpenAI reports the bootstrap figure for HealthBench (`bootstrap_std` in
simple-evals). Every figure is computed from the run file alone.

Reference: [healthbench.md §5](../../docs/reference/healthbench.md) (scoring, `bootstrap_std`).

## User stories

### US1 (P1): See the centre and spread of the scores

As an **evaluator**, I want the median and standard deviation of the
conversation scores, so that I know whether the run score hides very uneven
results.

Acceptance scenarios:
1. **Given** a run, **when** its summary shows, **then** it includes **Median score** and **Std dev (conversations)**. Both are computed over the conversations that have a score, using the unclipped conversation scores (healthbench.md §5).
2. **Given** an even number of scored conversations, **when** the median is computed, **then** it is the mean of the two middle values.
3. **Given** fewer than 2 scored conversations, **when** the summary shows, **then** the standard deviation shows "–".

### US2 (P1): See how certain the run score is

As an **evaluator**, I want the bootstrap standard deviation of the run
score, so that I can tell whether two runs really differ.

Acceptance scenarios:
1. **Given** a run, **when** its summary shows, **then** it includes **Bootstrap std (run score)**: the standard deviation of the run score over 1,000 resamples of its conversations, drawn with replacement. Each resample's score is clipped to 0–1, exactly like the run score (simple-evals `bootstrap_std`).
2. **Given** the same run, **when** it is opened again, on any machine, **then** the bootstrap figure is identical, because the resampling uses a fixed seed.
3. **Given** fewer than 2 scored conversations, **when** the summary shows, **then** the bootstrap figure shows "–".
4. **Given** the run score, **when** it is shown, **then** it is followed by "± bootstrap std".

## Functional requirements

- **FR-001** Median: of the non-null, unclipped conversation scores. For an even count, the mean of the two middle values.
- **FR-002** Standard deviation (conversations): the sample standard deviation (n − 1) of the same values. Undefined for fewer than 2.
- **FR-003** Bootstrap std: 1,000 resamples with replacement of the scored conversations. Each resample score is `clip(mean, 0, 1)`. The result is the population standard deviation of those 1,000 values, as numpy's `np.std` computes it in simple-evals. The random generator is seeded with a fixed value, so the result is deterministic. Undefined for fewer than 2.
- **FR-004** The three figures MUST appear in the run summary tiles, with explanations on hover, and the run score MUST show "± bootstrap std".
- **FR-005** Computing them MUST NOT freeze the interface for the largest run (5,000 conversations).

## Non-functional requirements

- **NFR-001** Pure-Dart core, unit-tested with hand-computed values. The median and standard deviation are checked against numpy on the reference golden scores.

## Out of scope

- Per-theme and per-axis breakdowns (a later feature).
- Comparing two runs statistically.

## Clarifications

### 2026-10-18 (owner)
- **Q:** Which standard deviation? → **A:** Both: the spread of the conversation scores, and the bootstrap uncertainty of the run score.
