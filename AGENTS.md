# Agents Guide

## Project Overview

This repository publishes the OpenAPI reference for Dart Health's Data Nexus API. `openapi.json` is copied from production's live spec; nothing here is hand-edited API code.

## Structure

- `openapi.json` - The published spec. Change it only with `scripts/refresh-spec.sh`
- `README.md` - The public landing page
- `docs/when-to-use.md` - The fit guide
- `scripts/refresh-spec.sh` - Fetches the live spec and reports what changed
- `scripts/check-spec.sh` - Checks `openapi.json`, `README.md` and `docs/` before anything is published
- `scripts/test/` - Fixtures and the test runner for both scripts
- `.github/workflows/` - CI

## Development

- Run `scripts/test/run.sh` to test the scripts
- Run `scripts/check-spec.sh` before pushing; CI runs both

## GitHub Actions scanning

zizmor (security) and actionlint (correctness) run on every pull request and fail on any finding. Before pushing a workflow change, run both locally:

- `GH_TOKEN=$(gh auth token) zizmor .` (without a token, zizmor skips its online audits)
- `actionlint`

Pin every action to a full commit SHA, with the exact version in a comment.

## Pull requests

Every pull request needs an approving review from a code owner listed in `.github/CODEOWNERS` before it can merge. An automated review, such as CodeRabbit's, doesn't count, and a push after the approval needs a fresh one. Never mark a pull request ready to merge on a bot's approval alone; ask a code owner to review it.

This repository is public. Never name a Dart Health client in a commit, pull request, issue or doc; write "a client".
