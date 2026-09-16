# Contributing

Escape Circuit separates observed scientific data, modeled neural dynamics, and game scaffolding. Contributions must preserve that boundary in code, documentation, and user-facing copy.

## Before submitting a change

1. Run `scripts/check.ps1` on Windows.
2. Add or update tests for behavioral changes.
3. Document new biological assumptions in `docs/neuroscience.md`.
4. Do not commit downloaded connectome files, generated builds, credentials, or personal gameplay logs.
5. Retain third-party copyright and license notices.

Keep changes narrowly scoped. Prefer deterministic behavior and versioned data over implicit runtime downloads.

