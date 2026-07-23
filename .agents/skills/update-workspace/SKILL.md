---
name: update-workspace
description: Update the current Sentinel agent workspace from sentinel-workspace-public while preserving local work. Use when the user asks to update, refresh, or sync a custom Sentinel workspace.
---

# Update Workspace

Bring the current workspace up to date from `https://github.com/ood-labs/sentinel-workspace-public.git` on the user's terms.

1. Resolve the current workspace root. Record its git status, relevant remotes, and current commit when available.
2. When it is a git clone with a remote matching `sentinel-workspace-public`, fetch that remote and fast-forward the checked-out branch with `git merge --ff-only`.
   - If the worktree is dirty, stash tracked and untracked changes first with a clearly named temporary stash, then restore them after the fast-forward.
   - Restore the temporary stash before returning when fetch or fast-forward fails.
   - Leave stash-pop conflicts unresolved, preserve the conflict state, and ask the user how to proceed.
   - Stop and ask before switching branches, rewriting history, or resolving divergence.
3. When it is not a git repository, clone the latest public workspace into a temporary directory and copy additively.
   - Copy files that are missing locally.
   - Leave byte-identical files alone.
   - Leave every locally differing file in place, list it as a conflict, and ask before overwriting it.
   - Keep every user-added file and directory. Never delete destination content.
4. Remove the temporary clone after the comparison and copy complete.
5. Report the source commit, old and new local commits when applicable, files added or updated, preserved local changes, and unresolved conflicts. Include the final git status for git workspaces.
