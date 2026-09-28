"""Packaging checks and the Lua behavior suite (Python standard library only)."""

import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("build_package", ROOT / "scripts" / "build.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def find_lua():
    """Prefer LuaJIT/5.1 (Mudlet), but accept compatible Lua for contributors."""
    explicit = os.environ.get("LUA")
    if explicit:
        return [explicit] + (["--luaonly"] if "tex" in Path(explicit).name else [])
    for name in ("luajit", "lua5.1", "lua", "texluajit", "luajittex", "texlua"):
        executable = shutil.which(name)
        if executable:
            return [executable] + (["--luaonly"] if name in ("luajittex",) else [])
    for path in sorted(Path("/usr/local/texlive").glob("*/bin/*/luajittex"), reverse=True):
        return [str(path), "--luaonly"]
    return None


class PackageTests(unittest.TestCase):
    def test_command_aliases_preserve_game_door_and_doorbash(self):
        source = (ROOT / "src" / "runtime.lua").read_text()
        # These particular PCRE alias patterns use Python-compatible constructs.
        patterns = [re.compile(pattern) for pattern in re.findall(
            r"tempAlias\(\s*\[\[(.*?)\]\]", source, flags=re.DOTALL)]
        self.assertEqual(len(patterns), 3)
        for command in ("door", "door east", "doorbash", "doorbash east", "doorwayx", "setdoorwayx e say enter"):
            self.assertFalse(any(pattern.fullmatch(command) for pattern in patterns), command)
        for command in ("doorway", "doorway help", "doorway set e say enter", "setdoorway e say enter", "SETDOORWAY NE open ne", "ne"):
            self.assertEqual(sum(bool(pattern.fullmatch(command)) for pattern in patterns), 1, command)

    def test_valid_package_and_ordered_bootstrap(self):
        with tempfile.TemporaryDirectory() as folder:
            package = builder.build(Path(folder) / "doors.mpackage")
            with zipfile.ZipFile(package) as archive:
                self.assertEqual(archive.namelist(), ["lotj-doorways.xml", "config.lua", "README.md"])
                document = ET.fromstring(archive.read("lotj-doorways.xml"))
                self.assertEqual(document.tag, "MudletPackage")
                scripts = document.findall("./ScriptPackage/Script")
                self.assertEqual(len(scripts), 1)
                self.assertEqual(scripts[0].get("isActive"), "yes")
                source = scripts[0].findtext("script")
                offsets = [source.index("-- BEGIN " + item) for item in builder.SOURCES]
                self.assertEqual(offsets, sorted(offsets))
                for name in builder.SOURCES:
                    self.assertIn((ROOT / "src" / name).read_text(), source)
                self.assertIn(b"mpackage = [[lotj-doorways]]", archive.read("config.lua"))
                self.assertEqual(archive.read("README.md"), (ROOT / "README.md").read_bytes())
                self.assertIn(f'version = "{builder.VERSION}"', source)
                self.assertIn(f'version = [[{builder.VERSION}]]'.encode(), archive.read("config.lua"))

    def test_reproducible_archive(self):
        with tempfile.TemporaryDirectory() as folder:
            first = builder.build(Path(folder) / "first.mpackage").read_bytes()
            second = builder.build(Path(folder) / "second.mpackage").read_bytes()
            self.assertEqual(first, second)

    def test_lua_behaviors(self):
        runtime = find_lua()
        if runtime is None:
            self.fail("No Lua interpreter found. Install LuaJIT or Lua 5.1, or set LUA to its path.")
        with tempfile.TemporaryDirectory(prefix="lotj-doorways-tests-") as folder:
            bootstrap = Path(folder) / "bootstrap.lua"
            document = ET.fromstring(builder.package_files()["lotj-doorways.xml"])
            bootstrap.write_text(document.findtext("./ScriptPackage/Script/script"))
            env = dict(os.environ, DOOR_TEST_HOME=folder, DOOR_TEST_BOOTSTRAP=str(bootstrap))
            result = subprocess.run(runtime + [str(ROOT / "tests" / "run.lua")],
                                    cwd=ROOT, env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            print("\n" + result.stdout.strip())

    def test_editor_widget_contracts(self):
        runtime = find_lua()
        if runtime is None:
            self.fail("No Lua interpreter found. Install LuaJIT or Lua 5.1, or set LUA to its path.")
        result = subprocess.run(runtime + [str(ROOT / "tests" / "ui_spec.lua")],
                                cwd=ROOT, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        print("\n" + result.stdout.strip())

    @unittest.skipUnless(os.environ.get("LOTJ_MAPPER_SOURCE"),
                         "Set LOTJ_MAPPER_SOURCE to run against an actual LotJ mapper checkout")
    def test_real_mapper_integration(self):
        runtime = find_lua()
        self.assertIsNotNone(runtime, "A Lua interpreter is required")
        source = Path(os.environ["LOTJ_MAPPER_SOURCE"]).resolve(strict=True)
        with tempfile.TemporaryDirectory(prefix="lotj-doorways-mapper-tests-") as folder:
            env = dict(os.environ, DOOR_TEST_HOME=folder, LOTJ_MAPPER_SOURCE=str(source))
            result = subprocess.run(runtime + [str(ROOT / "tests" / "real_mapper_spec.lua")],
                                    cwd=ROOT, env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            print("\n" + result.stdout.strip())


if __name__ == "__main__":
    unittest.main()
