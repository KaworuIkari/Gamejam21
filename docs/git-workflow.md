# Git Workflow for the Jam

This is how the three of us work so nobody loses work, and `main` always runs.

**The one rule:** nobody commits directly to `main`. Each task gets its own short-lived branch, which is merged into `main` through a pull request (PR) on GitHub, usually within one day.

---

## 1. One-time setup (each person, once)

```bash
# Your identity (use the email linked to your GitHub account)
git config --global user.name "Your Name"
git config --global user.email "you@example.com"

# Make "git pull" refuse to create surprise merge commits on main
git config --global pull.ff only

# Make "git push" on a new branch automatically create it on GitHub
git config --global push.autoSetupRemote true

# Default branch name for new repos
git config --global init.defaultBranch main

# Large-file support (install first: macOS "brew install git-lfs", Windows: included with Git for Windows)
git lfs install
```

Clone the repo:

```bash
cd ~/Coding
git clone https://github.com/KaworuIkari/Gamejam21.git
cd Gamejam21
```

Check it worked:

```bash
git status          # should say: On branch main, up to date with 'origin/main'
git remote -v       # should show the GitHub URL
```

### Repo owner only: protect `main`

On GitHub go to **Settings → Branches → Add branch ruleset** (or "Add rule") for `main`:
- Require a pull request before merging (approvals: 0 or 1, as the team agrees)
- Block force pushes
- Restrict deletions

With this in place, a plain `git push` to `main` is rejected, so no one can break it by accident.

---

## 2. Where does `git push` go?

`git push` sends **the branch you are on** to the branch of the same name on GitHub.

- If you are on `main`, it pushes to `main`. That's why we never work on `main`.
- If you are on `feat/player-jump`, it pushes to `feat/player-jump` on GitHub, and `main` is untouched.

Always check where you are before committing:

```bash
git branch --show-current
```

Tip: turn on a prompt that shows your branch (VS Code shows it in the bottom-left corner, and most terminals can too).

---

## 3. The daily loop (The most used steps)

### Step 1: Start from an up-to-date `main`

```bash
git switch main
git pull
```

### Step 2: Create a branch for one task

Branch names: `type/short-description`, lowercase, with hyphens.

| Prefix | Use for | Example |
| --- | --- | --- |
| `feat/` | New feature | `feat/double-jump` |
| `fix/` | Bug fix | `fix/enemy-stuck-in-wall` |
| `art/` | Art or audio assets | `art/player-sprites` |
| `level/` | Level work | `level/cave-02` |
| `docs/` | Docs | `docs/update-playbook` |

```bash
git switch -c feat/double-jump
```

### Step 3: Work, then commit small and often

```bash
git status                     # see what changed
git diff                       # see the actual line changes (code)
git add path/to/file           # stage specific files (preferred)
git add -A                     # or stage everything; check git status first!
git commit -m "Add double jump with coyote time"
```

Good commit messages say what the commit does, in present tense, in under ~60 characters: "Add pause menu", "Fix player falling through platforms", "Tune enemy speed".

Commit every time something works, even a little. Small commits are easy to undo.

### Step 4: Push your branch

```bash
git push
```

The first push creates the branch on GitHub (thanks to `push.autoSetupRemote`). Push at least once a day, even if unfinished; it doubles as a backup.

### Step 5: Keep your branch up to date with `main` (optional, only if others done some work)

If your branch lives for more than a few hours, pull in teammates' work regularly:

```bash
git fetch origin
git merge origin/main
```

Fix any conflicts now (section 5), test that the game still runs, then `git push`.

### Step 6: Open a pull request

On GitHub, a yellow banner offers **"Compare & pull request"**. Click it, or use the GitHub CLI:

```bash
gh pr create --fill            # optional; install with: brew install gh
```

In the PR:
- The title says what it does.
- The description says what to test: "Press Space twice in the air."
- Add a GIF or screenshot for anything visual.
- Post the link in #builds or #daily on Discord.

### Step 7: Review and merge

- One teammate plays or skims it (5 minutes max) and approves. In crunch time, self-merging is fine if you have tested it.
- Merge with **"Squash and merge"** (it keeps `main` history clean: one commit per task).
- Click **Delete branch** on GitHub after merging.

### Step 8: Clean up locally and start the next task

```bash
git switch main
git pull
git branch -d feat/double-jump    # delete your local copy of the merged branch
git fetch --prune                  # forget branches deleted on GitHub
```

Then back to Step 2.

---

## 4. Quick reference

```bash
git switch main && git pull            # get latest main
git switch -c feat/thing               # new branch
git add -A && git commit -m "msg"      # commit everything
git push                               # upload branch
git fetch origin && git merge origin/main   # update branch with latest main
git switch other-branch                # change branch (commit or stash first)
git log --oneline --graph -15          # recent history
git branch -a                          # all branches, local and on GitHub
```

---

## 5. Merge conflicts

A conflict happens when two people changed the same lines of the same file. Git stops and asks you to choose.

```bash
git fetch origin
git merge origin/main
# CONFLICT (content): Merge conflict in scripts/player.gd
git status                              # lists files marked "both modified"
```

Open each file and look for:

```
their version
```

Edit it to the correct final code, delete the three marker lines, then:

```bash
git add scripts/player.gd
git commit                              # finishes the merge (default message is fine)
git push
```

Panic button (cancel the merge and go back to before it):

```bash
git merge --abort
```

**Scene, level and binary files (images, audio, `.tscn`, `.unity`, `.prefab`, `.uasset`) can't be merged by hand.** Pick one whole version:

```bash
git checkout --theirs path/to/level.tscn   # keep main's version
git checkout --ours   path/to/level.tscn   # keep your version
git add path/to/level.tscn
```

Then redo the lost changes by hand. **Prevent this entirely:** announce in #daily which scene or level you're editing, and never let two people edit the same one at the same time.

---

## 6. Things to watch out for

### Everyone
- **Check your branch before committing:** `git branch --show-current`. Never on `main`.
- **Pull `main` before starting a new branch**, every time.
- **Merge small and often.** A branch older than 2 days will hurt to merge.
- **Test before you push to a PR.** Open the project and run the game. A broken `main` blocks everyone.
- **Never `git push --force` on `main`**, or on a branch someone else is also using. If Git tells you to force, stop and ask in Discord.
- **Don't commit** build outputs, engine caches, personal editor settings, `.DS_Store`, API keys or passwords. The `.gitignore` handles most of this; check `git status` before `git add -A`.
- **Big files go through Git LFS.** Check with `git lfs ls-files` after adding assets. GitHub rejects single files over 100 MB.
- **Commit engine-generated companion files.** For example, Unity `.meta` files and Godot `.import` files must be committed alongside their asset, or references break for everyone else.

### The artist, or anyone less used to Git
- **GitHub Desktop** (desktop.github.com) does all of the above with buttons: Current Branch → New Branch, Commit, Push, Create Pull Request. It's fine to use it instead of the terminal.
- Only commit **exported** assets (`.png`, `.ogg`, `.wav`, `.glb`) into the repo. Working files (`.psd`, `.aseprite`, `.blend`) go in the shared Drive.
- Follow the naming convention: `spr_player_run.png`, `sfx_jump_01.wav`.

---

## 7. "Oh no" recipes

| Situation | Fix |
| --- | --- |
| I committed on `main` by accident (not pushed yet) | `git switch -c feat/my-work` (the branch keeps the commits), then `git switch main && git reset --hard origin/main` |
| I want to change my last commit message (not pushed) | `git commit --amend -m "Better message"` |
| I forgot a file in my last commit (not pushed) | `git add file && git commit --amend --no-edit` |
| I need to switch branches but have unfinished changes | `git stash`, switch, come back, then `git stash pop` |
| Discard my changes to one file | `git restore path/to/file` |
| Unstage a file I added by mistake | `git restore --staged path/to/file` |
| Undo a commit that is already pushed or merged | `git revert <commit-hash>` (makes a new commit that undoes it; safe on shared branches) |
| `git pull` on main says "Not possible to fast-forward" | You committed on main locally. Do the first recipe in this table. |
| Push rejected: "fetch first" / "non-fast-forward" | Someone pushed to your branch. `git fetch origin && git merge origin/<your-branch>`, then `git push` |
| I committed a huge file without LFS | Ask in Discord **before pushing**. It's easy to fix locally and painful once it's on GitHub. |
| Everything is weird and I'm scared | Stop. Copy your changed files somewhere safe, run `git status`, and post the output in Discord. |

---

## 8. Jam-specific timing

- **Days 1–7 (prototype):** merge to `main` several times a day. Speed matters most, and self-merge is fine.
- **Days 8–16 (production):** one quick review per PR. Upload an itch.io build from `main` at each gate.
- **Days 17–20 (polish and ship):** only `fix/` branches. Every PR gets a playtest before merging. Tag the submitted build:

```bash
git switch main && git pull
git tag -a v1.0-jam -m "Jam submission"
git push origin v1.0-jam
```

The tag marks exactly what you submitted, so you can come back to it after the jam.


## 9. Some other useful commands
```bash
git log --oneline --graph --all
```