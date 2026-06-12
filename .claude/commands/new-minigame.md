Scaffold a new mini-game module named "$ARGUMENTS", conforming to the project's
module-per-game architecture (see CLAUDE.md and docs/ARCHITECTURE.md).

Do this:
1. Create `lib/games/$ARGUMENTS/$ARGUMENTS_descriptor.dart` implementing
   `MiniGameDescriptor` (id `$ARGUMENTS`, a readable title, correct multiplayer
   capability and player counts, a `build()` returning a placeholder widget).
2. Register it in `lib/main.dart` with a single `register(...)` line — do not
   modify any other game.
3. Add `test/games/$ARGUMENTS/` with a starter test file.
4. Note the new game under Unreleased in `CHANGELOG.md`.
Keep `flutter analyze` clean. Then summarize what you created.
