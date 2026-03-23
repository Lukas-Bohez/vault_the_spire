# Contributing to Vault The Spire

Thank you for contributing! This project is open source and welcomes improvements, bug fixes, and documentation updates.

## Getting started

1. Fork the repository.
2. Create a feature branch: `git checkout -b feature/<short-name>`.
3. Run tests locally:
   - `flutter pub get`
   - `flutter analyze --no-fatal-infos`
   - `flutter test`

## Coding conventions

- Use `dart format .` before committing.
- Keep commits small and focused.
- Add tests for new features/behavior.
- Document behavior in README or code comments as needed.

## Pull request process

1. Push your branch to your fork.
2. Open a Pull Request against `main`.
3. Reference related issue(s) in the PR description.
4. Wait for CI to pass.

## Issue triage

- Use existing issue templates for bug reports and enhancements.
- Prefer smaller, incremental feature PRs over monolithic changes.

## Style

- Prefer null-safety-safe Dart APIs.
- Keep UI text localizable where appropriate.
- Avoid adding new nonfree dependencies.
