# Claude reviews Dependabot's pull requests (2026-11-28)

`.github/workflows/dependabot-review.yml` runs `anthropics/claude-code-action` on each pull request
Dependabot opens (GitHub Actions bumps weekly, submodule bumps monthly). Claude posts one comment
with a verdict and what to check. It can't approve, push or merge.

## What GitHub allows (github/docs, read 2026-11-28)

- **Secrets:** for `pull_request` runs Dependabot triggers, "Secrets are populated from Dependabot
  secrets. GitHub Actions secrets are not available", "even if the workflow is re-run by a
  different actor". So the token is a Dependabot secret. (dependabot-on-actions reference)
- **Token:** such runs get a read-only `GITHUB_TOKEN` by default, and "You can use the
  `permissions` key in your workflow to increase the access for the token". The job asks for
  `pull-requests: write` only. (troubleshooting Dependabot on Actions)

## What the action does (claude-code-action v1.0.290 source, read 2026-11-28)

- Bots can't start it unless listed in `allowed_bots`, so it lists `dependabot[bot]`.
- Given `github_token`, it uses that token and doesn't need the Claude GitHub App or `id-token`.
  Comments come from `github-actions[bot]`.
- `restrict_untrusted_prs` (on by default) treats bot authors as untrusted and denies shells,
  interpreters, `just`, `git config` and package managers. The `gh pr view/diff/comment` commands
  the review uses aren't affected.

## Design

- **Upstream diffs are made before Claude runs.** `.github/scripts/submodule-bump-context.sh`
  fetches the old and new submodule commits (`--depth 1`, by SHA) and writes the diff of the files
  the build uses, plus Bazzite's Titanoboa pin, to `.dependabot-review/upstream.md`. Claude only
  reads files and runs three `gh pr` commands, so it has no shell or network access to misuse.
- **Upstream content is untrusted.** Release notes, commit messages and Bazzite's code could
  contain text written to steer a reviewer. The prompt says to treat them as data, and the worst
  a steered run can do is post a misleading comment.
- **Tested** against the open pull requests on 2026-11-28: the Bazzite bump `eea6eb0` → `09b2a59`
  changes nothing in `installer/`, and Titanoboa matches Bazzite's pin (`5c457c3`). A simulated
  bump from `3ba437d` shows the `installer/build.sh` and `ublue-motd` changes. The cosign-installer
  bump reports no submodule move. The Claude step itself first runs on GitHub.
