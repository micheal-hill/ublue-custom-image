# Keeping the signing key to the main branch (2026-11-25)

## Problem

The `protect-main` ruleset requires a reviewed pull request before anything reaches `main`.
`SIGNING_SECRET` was a repository secret, though, and GitHub runs a workflow from the copy of
`build.yml` on the branch the run is for. Two kinds of run in this repo got the key:
- a manual run (`workflow_dispatch`) started on any branch;
- a pull request from a branch in this repo.

So a branch whose `build.yml` dropped the "publish only from main" checks could push and sign a
`latest` image without being reviewed. Laptops trust that key for updates. Pull requests from forks
were never a risk: they get no secrets and a read-only token.

## GitHub environments (docs.github.com, read 2026-11-25)

- **Branch rules:** "The deployment branch or tag rule is matched against the `GITHUB_REF` of the
  workflow run". A pull request run has the ref `refs/pull/N/merge`, so a rule for `main` doesn't
  let it in. A manual run on another branch is checked against that branch's ref.
  (deployments-and-environments)
- **Secrets:** "Secrets stored in an environment are only available to workflow jobs that reference
  the environment". An environment secret wins over a repository secret of the same name. Both are
  read through `secrets.NAME`. (secrets reference)
- **Job setting:** `jobs.<id>.environment` names the environment for a whole job, not for a step.
  Its name can be an expression, using the contexts github, inputs, vars, needs, strategy and
  matrix. The docs don't say what an empty name does. Community use treats it as "no environment".
- **Deployments:** every job that references an environment creates a deployment. Matrix jobs
  create one each.
  - `deployment: false` turns that off and keeps the environment's secrets.
  - The docs list "restrict which branches can use certain secrets … without deployment tracking"
    as a use for it, but the rule table on the control-deployments page doesn't mention branch rules.
- **Plans:** branch rules and environment secrets work on public repositories on GitHub Free.

## Change

- The `build_push` job sets
  `environment: ${{ (<same check as the push and sign steps>) && 'publish' || '' }}`.
- It doesn't set `deployment: false`. The deployment list then doubles as a log of what was
  published, and branch rules are certainly enforced.
- The scheduled run on 2026-11-25 (45534392536) pushed and signed. So the check
  `github.event_name != 'pull_request' && github.ref == format('refs/heads/{0}',
  github.event.repository.default_branch)` holds for scheduled runs too: their event payload has
  `repository.default_branch`.

**The security doesn't depend on the empty name.** The key is only in `publish`, and GitHub enforces
the rule that only `main` may use `publish`. A branch that edits the expression to ask for `publish`
anyway gets refused. Only pull request builds depend on the empty name, and the first pull request
after this change shows whether it works.

**Settings, done by the user:** create the `publish` environment, limit its deployment branches to
`main`, and move `SIGNING_SECRET` into it from the repository secrets.

**What a branch can still do:** push an *unsigned* image over `latest`, since `GITHUB_TOKEN` has
`packages: write`. A laptop that switched with `--enforce-container-sigpolicy` refuses to update to
it, so updates stall until the next run on `main`. Unreviewed code still can't be installed.
