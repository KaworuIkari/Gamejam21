# Game Jam Team Playbook

Three people, 21 days, one finished game: aim for a playable build by day 7, feature freeze on day 16, and submit a day early.

## Roles

Each person owns one area and has final say there; everyone still helps everywhere. Owning an area means you unblock it, not that you do all of it.

| Role | Owns | Also covers |
| --- | --- | --- |
| Lead / gameplay programmer | Core loop, player controls, build and repo health, final call on scope | Integrating everyone's work into the main branch |
| Systems / tools programmer | UI, menus, audio hookup, save/restart, level loading, bug triage | Level scripting, performance |
| Art / design / audio | Visual style guide, sprites or models, animation, sound and music, level layouts | Tuning numbers, writing, store page art |

If you have two programmers and no artist, pick one strong, cheap art style on day 1 (flat colours, pixel art at low resolution, or free asset packs the jam allows) and let the third person own design, levels and audio instead.

One person is the **producer** for the whole jam: runs check-ins, keeps the task board honest and calls the cuts. Usually the lead; it can rotate weekly.

## 21-day plan

Three gates matter more than any feature: a playable build on day 7, feature freeze on day 16, and submission on day 20.

| Phase | Days | Focus | Gate at the end |
| --- | --- | --- | --- |
| Kickoff | 1–2 | Unpack theme, pick 1 idea, 1-page design, set up repo | |
| Prototype | 3–7 | Core loop only, placeholder art, playtest daily, lock art style | **Playable build** (end of day 7) |
| Production | 8–16 | Levels and content, real art and audio, menus and restart, weekly playtest | **Feature freeze** (end of day 16) |
| Polish | 17–19 | Fix bugs only, juice and feedback, tutorial and UX, outside testers | |
| Ship | 20–21 | Final builds, game page and screenshots, submit on day 20, day 21 is buffer | **Submitted** (end of day 20) |

If a gate slips by more than a day, cut scope rather than move the next gate. Anything not in the build at freeze waits for a post-jam update.

## Working rhythm

Online teams fail on silence, not on skill: post progress daily in writing and meet live only when it saves time.

| When | What | Length |
| --- | --- | --- |
| Every day, by a set hour | Written check-in in the team channel: done yesterday, doing today, blocked by | 3 lines |
| Every 2–3 days | Short voice call: play the latest build together, re-sort the task board | 20–30 min |
| Every Sunday | Weekly review: are we on track for the next gate? What do we cut? | 45 min |
| Days 7, 12, 16, 19 | Playtest by someone outside the team, watched on a screen share without helping | 15 min each |

- **Share your hours up front.** Each person posts their availability and time zone on day 1, including days they are away.
- **Overlap window.** Agree 1–2 hours a day when all three are usually online; save questions and calls for it.
- **Blocked for 30 minutes? Ask.** Post the question with a screenshot or clip rather than waiting for the next call.
- **Show, don't describe.** GIFs and short clips of new features in the channel keep morale up and catch misunderstandings early.
- **Disagreements.** The area owner decides within their area; the producer decides anything else. Decide in minutes, not days.
- **Protect sleep.** No all-nighters before day 19. A rested team fixes bugs faster than a tired one writes features.

## Tools and setup

Use tools everyone already knows; day 1 is the wrong time to learn a new engine or version-control system.

| Need | Suggested tool | Notes |
| --- | --- | --- |
| Chat and calls | Discord server with channels: #general, #daily, #builds, #bugs, #assets | One place for everything; pin key links in #general |
| Task board | Trello, GitHub Projects or Notion | Columns: Backlog · This week · Doing · Review · Done. Max 2 cards in Doing per person |
| Code and project | Git on GitHub or GitLab, with Git LFS for large binaries | Add the engine's .gitignore on day 1 |
| Engine | Whatever the programmers are fastest in (Godot, Unity, Unreal, GameMaker, etc.) | Check the jam's rules on engines and platforms first |
| Art and audio | Shared drive folder for source files; only exported files go in the repo | Agree sizes, palette and naming before drawing anything |
| Builds | One shared build page (itch.io draft page works well) | Upload a build at every gate so anyone can play the latest |

**Avoid merge pain**

- Work on short-lived branches and merge to main at least daily.
- Two people never edit the same scene or level file at once. Split work into separate scenes or prefabs and say in #daily which file you are in.
- main must always open and run. If you break it, fixing it is your first task.

**Naming convention** (agree on day 1): lowercase with underscores, type first, e.g. `spr_player_run.png`, `sfx_jump_01.wav`, `lvl_02_cave`.

## Scope rules

Plan a game you could finish in 10 days; the other 11 go to bugs, polish, surprises and real life.

1. **Sort every feature into three buckets on day 2.** Must (the game is broken without it), Should (clearly better with it), Could (nice if time allows). Build all Musts before touching a Should.
2. **One core mechanic, done well.** A small game that feels good beats a large one that feels unfinished. Judges often play for only a few minutes.
3. **The first 60 seconds matter most.** Clear goal, obvious controls, something fun right away.
4. **New idea after day 7?** Write it in the Could column. It only gets built if all Musts and Shoulds are done.
5. **Cut early, cut calmly.** At each weekly review, if a gate is at risk, drop the lowest Should. Nobody's work being cut is personal.
6. **Feature freeze is real.** After day 16: bug fixes, tuning, sound, juice and text only. No new systems.
7. **Always have a submittable build.** From day 7 on, main should be something you could upload if the jam ended tonight.

## Day 1 kickoff checklist

Run this as one 60–90 minute call right after the theme is announced.

- [ ] Read the jam rules together: engines, pre-made assets, AI use, platforms, team size, submission format and exact deadline time zone
- [ ] Everyone shares skills, what they want to learn, and weekly availability
- [ ] Agree roles and who is producer
- [ ] 20 minutes of solo brainstorming on the theme, then share and vote on the top 3 ideas
- [ ] Pick one idea; write a one-sentence pitch and the core loop (what the player does every 10 seconds)
- [ ] Write a one-page design doc: pitch, controls, win/lose, art style reference images, Must/Should/Could list
- [ ] Create Discord channels, task board, repo and shared drive; everyone clones and runs the empty project
- [ ] Agree daily check-in time and the overlap window
- [ ] Put the three gate dates in everyone's calendar

## Submission checklist

Start on day 19 and finish on day 20; the jam site will be slow in the final hours.

- [ ] Final build exported for every target platform, and web build if allowed (browser games get played far more)
- [ ] Tested on a machine that is not the developer's, from a clean download
- [ ] Title screen, how-to-play or on-screen control hints, and a working restart
- [ ] Volume is sane, and there is a mute or volume option
- [ ] Game page: title, short pitch, 3–5 screenshots, a GIF, controls, credits for all three members
- [ ] Credits and licences for any third-party assets, fonts or music
- [ ] Submitted with all team members linked, then played once more from the jam page
- [ ] Post-jam: play and rate other entries (many jams reward this), then hold a 30-minute retro on what to keep and change
