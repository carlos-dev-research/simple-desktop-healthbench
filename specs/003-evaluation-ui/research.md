# Research: 003 evaluation UI

**Date:** 2026-10-17 · Reference: the reference repo's `webview/` (`index.html`, `app.js`, `run.js`), studied for layout and behaviour.

## R1. Packages (Constitution IX)

| Need | Package | Publisher / status | Notes |
|---|---|---|---|
| UI state | `flutter_riverpod` 3.x | dash-overflow.net, **Flutter Favorite** | `Notifier`/`NotifierProvider`, no code generation (Art. VI) |
| App storage folder | `path_provider` 2.1.x | flutter.dev, **Flutter Favorite** | `getApplicationSupportDirectory()` (flutter-desktop.md §2.1) |
| Native open dialog | `file_selector` 1.1.x | flutter.dev, first-party | Needs `files.user-selected.read-write`, which is already granted |
| Markdown parsing | `markdown` 7.3.x | tools.dart.dev, first-party | Parses to an AST. We render it ourselves (R3) |

Not used:
- `flutter_markdown`: discontinued.
- `flutter_markdown_plus` / `markdown_widget`: not Flutter Favorites.
- `fl_chart`: not needed. The histogram is a `CustomPaint` (R4).
- `shared_preferences`: the remembered form fields go in a small JSON file in the app's storage instead (R6).

Swift Package Manager: `path_provider` and `file_selector` are first-party Flutter plugins. A macOS build after adding them must not create a `Podfile`, which rule PR-6 checks.

## R2. Where things live

- **Core (pure Dart, testable):**
  - `lib/core/run_summary.dart`: counts, positive/negative criteria met, histogram bins, earned/possible per conversation, search text.
  - `lib/core/run_library.dart`: lists a folder's run files, valid and rejected.
- **UI:**
  - `lib/ui/…`: screens and widgets.
  - `lib/ui/state/…`: Riverpod notifiers.
  - Injectable seams for tests: the storage folder, the dataset picker, and the HTTP client.

## R3. Rendering Markdown safely (spec US5-1)

- Parse with `markdown`'s `Document(extensionSet: gitHubFlavored, encodeHtml: false)` **without** `InlineHtmlSyntax`. Raw HTML then stays literal text.
- Render the AST to widgets:
  - h1–h6, paragraphs, bold/italic/strikethrough;
  - inline code and code blocks;
  - ordered and unordered lists (nested);
  - block quotes and horizontal rules;
  - tables.
- Links are shown underlined but **not tappable** (nothing opens automatically). Images render as `[image: alt]` text, and nothing is fetched.
- Unknown elements fall back to their text content.
- All text is selectable (`SelectionArea`).

## R4. Histogram

Same bins as the reference: below 0, then 0.0–0.1 … 0.9–1.0, with a score of exactly 1.0 in the last bin. Drawn with `CustomPaint`, using a count label above each bar and the bin label below. The colours come from the theme, so light and dark both work.

## R5. Progress maths (as in the reference `run.js`)

- **Processed** = done + failed.
- **Fraction** = (processed + criterionDone/criterionTotal) / total, using the partial term only while running.
- **Estimated time left** = elapsed / (processed + partial) × (total − processed − partial), shown only once something has been processed.

> **Superseded 2026-10-17** (spec FR-004 amended at the owner's request): no form fields are written to disk any more. The whole form, key and dataset included, lives in a session-only Riverpod notifier (`newRunFormProvider`). A leftover `form.json` is deleted at startup. Kept below as the original decision.

## R6. Remembered form fields (spec FR-004)

`form.json` in the app's storage folder holds: base URL, both model names and efforts, and the limit. It never holds the key, and never the dataset path (sandbox access to a picked file doesn't last across launches). It's written when a run starts and read at launch. If it's corrupt, it's ignored.

## R7. Riverpod 3 notes

- Riverpod 3 **retries failed providers by default**. We set `ProviderScope(retry: (_, _) => null)`, so errors surface at once and don't repeat requests.
- Listening to the run's progress stream is done in a `Notifier` that holds the `EvaluationRun`. It cancels its subscription when the run finishes.

## R8. Testing seams

| Seam | Production | Tests |
|---|---|---|
| `runsDirectoryProvider` | `<app support>/runs` | a temp folder |
| `datasetPickerProvider` | `file_selector.openFile` (filter `.jsonl`) | returns a fixture path |
| `httpClientProvider` | the default `http.Client` | — (tests use the local fake server through the base URL) |

The integration test (`integration_test/evaluation_flow.dart`) overrides the runs folder and the dataset picker. It drives the real form against the fake server: start → progress → completed → open the run → open a conversation.
