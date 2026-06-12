# Setup — run this once

This scaffold is the **overlay** (config, docs, agents, hooks, CI, starter
architecture). You create the Flutter project first, then drop these files on
top. Commands assume macOS/Linux and that the Flutter SDK and `git` are
installed. `gh` (GitHub CLI) is optional but used below.

Throughout, the package is `bluetooth_connected_gaming` — used for the
`pubspec.yaml` `name:` and every `package:bluetooth_connected_gaming/...` import.
The product itself is referred to by its display name, `<DISPLAY NAME>`.

## 1. Create the Flutter project
```bash
flutter create --org com.YOURNAME --project-name bluetooth_connected_gaming bluetooth_connected_gaming
cd bluetooth_connected_gaming
```

## 2. Overlay this scaffold
Unzip the scaffold somewhere, then copy it in (the trailing `/.` copies dotfiles
and preserves the hook scripts' executable bit):
```bash
cp -a /path/to/bluetooth_connected_gaming-scaffold/. .
```
This overwrites the default `lib/main.dart` with the arcade shell — expected.

## 3. Add dependencies
```bash
flutter pub add flame flame_forge2d flutter_nearby_connections
flutter pub add dev:very_good_analysis dev:mocktail
flutter pub get
```
(`flutter pub add` fetches current versions, so nothing here is pinned to a
stale number.)

## 4. Make the hooks executable (safety step)
```bash
chmod +x .claude/hooks/*.sh
```

## 5. Sanity check
```bash
dart format .
flutter analyze
flutter test
```
All three should pass. `peer_message_test.dart` proves the never-trust-the-peer
validation works.

## 6. First commit
```bash
git init
git add .
git commit -m "chore: scaffold <DISPLAY NAME> (architecture, CI, agents, hooks, ADRs)"
```

## 7. Create the GitHub repo and push
```bash
# with GitHub CLI:
gh repo create BluetoothConnectedGaming --private --source=. --remote=origin --push
# or create it in the web UI, then:
# git remote add origin git@github.com:Vedat-Esendag/BluetoothConnectedGaming.git
# git push -u origin main
```
The README badges already point at `Vedat-Esendag/BluetoothConnectedGaming`.

## 8. Turn on the GitHub guardrails
- **Branch protection** (Settings → Branches → add rule for `main`): require a PR
  and require the **CI** status checks to pass before merging.
- **Dependabot**: already configured by `.github/dependabot.yml` (enable
  Dependabot alerts under Settings → Security if not on).
- **Git LFS** (for assets later): `git lfs install` once on your machine; the
  `.gitattributes` rules then route images/audio/fonts through LFS automatically.
- Add a description + topics (flutter, game, bluetooth, multiplayer).

## 9. Open in Claude Code — this becomes your single surface
```bash
claude
```
On launch the SessionStart hook prints the working agreement + branch. Then:
- `/agents` — confirm `security-reviewer`, `code-reviewer`, `maintenance` loaded.
- `/hooks` — confirm the four hooks are registered.
- Try `/new-minigame tictactoe`, `/adr "Use X"`, `/review`.

From now on, plan, discuss, and build here. The repo (CLAUDE.md + ADRs + code)
is the memory — so context never depends on a chat log.

> Heads-up: you have **Superpowers** installed at user scope. It brings its own
> workflow and agents that may overlap with this leaner project setup. If it
> feels heavy or conflicts here, scope it off for this repo (`/plugin`).
>
> The Stop hook runs `flutter analyze` every time the agent finishes. If that's
> too aggressive during early prototyping, set `"disableAllHooks": true` in
> `.claude/settings.json` temporarily, or remove the `Stop` block.

## 10. Add the council (your "challenge my ideas" layer)
The three subagents above are your codebase-maintenance team. The **council** is
the separate layer that debates decisions before you commit to them:
```bash
# PolyClaude — lighter, dialectical decision document:
claude plugin marketplace add Riley-Coyote/polyclaude
claude plugin install polyclaude@polyclaude
```
Or, for a full 11-seat boardroom with the invoking Claude as CEO, add
`sjsyrek/design-council` and install it via `/plugin` (see its README for the
exact install string). Restart Claude Code after installing, then convene the
council at real forks — and record the outcome with `/adr`.

---

That's the whole environment. The loop is live: **decide (council) → build →
review (subagents) → gate (hooks + CI) → ship**, all inside Claude Code, all
backed by the repo.
