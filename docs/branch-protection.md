# Branch protection (recommended)

`renovate.json` uses `internalChecksFilter: "flexible"` together with
`minimumReleaseAge: "15 days"`. This combination means:

- If a **matured older version** (≥ 15 days old) exists, Renovate opens a PR
  for that version and waits for the newest release to mature.
- If **no matured version** exists (e.g. a brand-new major that skipped
  patch releases), Renovate still opens a PR for the latest version, but
  posts a **`renovate/stability-days`** commit status of **`pending`** until
  the release ages past the window.

The "pending" status only *blocks merges* if branch protection is configured
to require it. Otherwise a maintainer could click "Merge" on a not-yet-matured
PR by mistake. To enforce the stability window:

1. Go to **Settings → Branches → Branch protection rules → Add rule**
   (or edit the existing rule for `main`).
2. Set **Branch name pattern** to `main`.
3. Enable **Require a pull request before merging**.
4. Enable **Require status checks to pass before merging** and then
   **Require branches to be up to date before merging**.
5. In the status-check search box, add (each appears in the list after it has
   run on at least one PR):
   - `Lint (hadolint)`
   - `Test`
   - `Govulncheck (Go vulnerability reachability)`
   - `Verify base image signatures`
   - `Trivy CVE scan`
   - `renovate/stability-days`  ← **this is what enforces `minimumReleaseAge`**
6. (Optional, recommended) Enable **Require signed commits** and
   **Do not allow bypassing the above settings**.
7. Click **Create** / **Save changes**.

Once `renovate/stability-days` is a required check, any Renovate PR whose
release has not yet matured will be un-mergeable (even by a human clicking
the button) until the age window elapses and Renovate flips the status to
`success` on its next run.

> Tip: status checks only appear in the search box after they have run at
> least once on a PR targeting `main`. If you can't find one, open a
> throwaway PR that touches the relevant workflow, let CI run, then come
> back and add it.
