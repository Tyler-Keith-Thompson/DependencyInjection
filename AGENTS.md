# DependencyInjection: notes for coding agents

A SwiftPM package. `README.md` is the front page; the guide and API reference are the DocC catalog
in `Sources/DependencyInjection/DependencyInjection.docc` and the doc comments.

## Commands

| Command | What it does |
|---|---|
| `swift build` | Build the package |
| `swift test` | Run the tests (CI runs them on Linux, `swift:6.1.2`) |
| `swift package generate-documentation --target DependencyInjection --warnings-as-errors` | Build the DocC docs; a link that doesn't resolve fails it |

If the `swift` on your `PATH` is a development snapshot that crashes on the manifest, use Xcode's
(`/usr/bin/swift`).

## Docs

- Describe the current API. No history ("previously", "renamed"), design debates, comparisons
  with other libraries, or benchmark numbers in doc comments or READMEs. Complexity bounds are
  fine.
- Doc comments: a one-line summary, then parameters, return value, complexity, and what traps or
  throws.
- The README is the front page: what the project is, how to install or run it, one short example,
  and links. Everything else (guides, every option, reference) goes in the DocC catalog, which
  the README links to. When a section grows past a screen, move it out rather than trim the
  README's other sections to make room.
- Run prose docs through the `humanizer` skill (`/humanizer`) before committing them: READMEs, DocC
  articles, doc comments and this file. It removes the tells of generated text (inflated claims,
  stock phrases, forced lists of three) without changing what the text says. Docs only: not code,
  `//` comments, commit messages or backlog items.
- A new concept gets a DocC article, listed in the catalog's landing page (`DependencyInjection.md`)
  and linked from the README's Guides list.

## Git

- Commit message style: `[main] - <summary> - TT`, naming the Kanban item's key when there is one.
