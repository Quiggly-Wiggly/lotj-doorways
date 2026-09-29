# LotJ Doorways

**Quiggly-Wiggly Edition**

Save the commands for a door once, then use its direction to walk through it.
Works with typed directions and standard LotJ movement keys. Map walking also
uses your saved doors when the standard LotJ UI is installed.

## Install

1. Download [LotJ Doorways.mpackage](https://github.com/Quiggly-Wiggly/lotj-doorways/releases/latest/download/LotJ.Doorways.mpackage).
2. Install it through Mudlet's **Package Manager → Install New Package**.
3. Type `doorway ui` to open the editor, or `doorway help` for command help.

Requires **Mudlet 4.20+** and LotJ's GMCP room information.
**No custom LotJ UI or mapper edits are required.** The standard UI is optional
for manual doorways. Installing sends no commands and creates no sample rules.

## Save a door

Stand on the side of the door you want to configure. For a voice door:

```text
setdoorway east say enter
```

Now `e` sends exactly `say enter`, with no extra movement command.

For a door that must be opened before crossing, enter these as **separate lines**:

```text
setdoorway ne open ne
doorway append ne ne
```

Now `ne` sends `open ne`, then `ne`. Set up the other side separately.

In the editor, select **Use current room**, choose a direction, and enter
`open ne;;ne` or `say enter`. **Save rule** and Enter both save without executing.
The example follows your selected direction. Select an existing rule to edit or
delete it; use **Current room** or **All rooms** to filter the list.

The editing room stays fixed while you walk, and room updates preserve your
unfinished draft. **Use current room** explicitly changes the editing room.
The footer shows whether map walking is connected; **Help** prints command help.

**Use `;;` only in the editor.** Mudlet splits its main input before aliases run,
so typing `setdoorway ne open ne;;ne` would execute the last `ne` immediately.

## Commands

| Command | Action |
| --- | --- |
| `setdoorway <dir> <command>` | Save or replace a rule in your current GMCP room |
| `doorway append <dir> <command>` | Add a step to that rule |
| `doorway remove <dir>` | Delete that room's rule |
| `doorway list [all]` | List current-room rules, or every saved rule |
| `doorway ui` | Open the editor |
| `doorway raw <dir>` | Move once without a replacement |
| `doorway on` / `doorway off` | Enable or disable replacements |
| `doorway stop` | Cancel an unsent map stack or clear arrival tracking |
| `doorway help` | Show command help |

Short and full names work for north, northeast, east, southeast, south,
southwest, west, northwest, up, and down. The game's `door` / DOORBASH command
is never intercepted.

## Walking and mapping

A rule replaces the entire movement command. Include the direction yourself if
needed; a bare direction must match the selected direction and be the final,
only movement step. Commands are game text, without Lua or alias expansion.
There are no automatic retries or delays.

Choose a mapped destination as usual. Doorways uses each route room's rule to
build and send the complete command stack. The map must already have the exits
and destination; saving a rule does not create a route.

**Map walks send all steps at once. A failed door or `doorway stop` cannot recall
commands already sent.** Room updates track arrival and support map recording;
they never send more commands. Failure, darkness, unexpected movement, another
command, or five seconds without progress clears tracking.

Ordinary in/out exits and unlocked single-command special exits are supported.
Multi-command special exits are rejected. Directions without saved rules work
normally. During unresolved manual movement, additional directions pass through
without a replacement. Wait for fresh room information after darkness or a
disconnect. Saving a rule reads the current GMCP room, even if it is unmapped.

Custom Lua movement can opt in with `lotjDoorways.move("n")`. Direct `send("n")`
bypasses Doorways. Other packages aliasing the same directions can conflict.
Doorways protects its own managed mapper crossings; it does not replace the
mapper or fix unrelated stock-mapper behavior. Disabling restores normal map
walking, and uninstalling restores mapper functions still owned by Doorways.

## Saved rules

Rules save immediately to `lotj-doorways.json` in the Mudlet profile.
**All characters in that profile share the rules.** Uninstalling retains them.
Room vnums can change after a world reset, so review your library then.

Rules also copy into map userdata and travel with map saves/exports that retain
it. A profile without a Doorways JSON file can recover rules from that map when
Doorways loads. Existing JSON takes precedence, including an empty library.
Reload Doorways after importing a local map to recover into a fresh profile.
Invalid saved data is preserved and blocks edits until repaired or moved aside.

<details>
<summary>Development and verification</summary>

The repository contains the installable package, `src/`, `scripts/`, and `tests/`.
The package contains one ordered Lua bootstrap, metadata, and this README.
Builds use Python's standard library and are reproducible.

```sh
python3 scripts/build.py
python3 -m unittest discover -s tests -v
```

Tests need LuaJIT or Lua 5.1 (set `LUA` to choose a runtime). They use temporary
storage and fake game data, without touching a playing profile. Installed Geyser
sources are used for layout constraints when available; otherwise widgets are
simulated.

To also check an actual trusted LotJ mapper checkout:

```sh
LOTJ_MAPPER_SOURCE=/path/to/lotj-mudlet-ui/src/scripts/mapper/mapper.lua \
  python3 -m unittest discover -s tests -v
```

This executes the supplied mapper source with simulated Mudlet APIs. CI checks
public revision `dc6ae9c471c6aa8e4dcfdb4814b79a4cc0c3753c`. Coverage includes manual
voice/opening doors, room placement, same-room refreshes, one-way and repeated
routes, both listener orders, disabling, and uninstall restoration. Without the
environment variable, that integration check is explicitly skipped.

Native visual and live gameplay verification remain pending. In a clean test
profile, check installation in both orders with the standard UI, editor save and
Enter behavior, pinned drafts, movement keys, voice/opening doors, map-click
walking, disable/re-enable, and reload/uninstall. Test short harmless routes;
sent commands cannot be recalled.

Source references: [LotJ mapper](https://github.com/LotJ/lotj-mudlet-ui/blob/dc6ae9c471c6aa8e4dcfdb4814b79a4cc0c3753c/src/scripts/mapper/mapper.lua),
[Mudlet package format](https://wiki.mudlet.org/w/Manual:Package_Manager).

</details>

## Public release data

Packages start without character settings or saved game data. Examples and test
fixtures are fictional; substitute your own locally learned names and commands.
Profile files, room rules, ship names, landing pads, and map exports stay local.
