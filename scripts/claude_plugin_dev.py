#!/usr/bin/env python3
"""claude-plugin-dev: run Claude Code on the working copies of a repository's plugins.

It starts `claude` with one `--plugin-dir` per local plugin in the repository's
`.claude-plugin/marketplace.json`, followed by its own arguments. Claude Code
ignores a `--plugin-dir` plugin when managed settings name a plugin of the same
name, so it first reads the managed settings and stops, naming the plugin, if
any of them does.

Environment:
    CLAUDE_PLUGIN_DEV_MANAGED_SETTINGS  the folder holding managed-settings.json
        and managed-settings.d/ (default: Claude Code's system folder)
    CLAUDE_PLUGIN_DEV_MARKETPLACE  the nix-darwin module's marketplaceName, whose
        drop-in entries services.agent-plugins.unmanaged removes (default:
        nix-pinned)
    CLAUDE_PLUGIN_DEV_GIT  the git to find the repository root with (default:
        git from PATH); removed before `claude` starts
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path

MANAGED_SETTINGS_ENV = "CLAUDE_PLUGIN_DEV_MANAGED_SETTINGS"
MARKETPLACE_ENV = "CLAUDE_PLUGIN_DEV_MARKETPLACE"
GIT_ENV = "CLAUDE_PLUGIN_DEV_GIT"
MODULE_MARKETPLACE = "nix-pinned"
DROP_IN_FOLDER = "managed-settings.d"
JSON_KINDS = {dict: "object", list: "array", str: "string"}
SYSTEM_FOLDERS = {
    "darwin": Path("/Library/Application Support/ClaudeCode"),
    "linux": Path("/etc/claude-code"),
}


class UsageError(Exception):
    """A repository or managed setting that the command can't work with."""


@dataclass(frozen=True)
class Plugin:
    """A plugin's manifest name and the directory Claude Code loads it from."""

    name: str
    path: Path


@dataclass(frozen=True)
class ManagedEntry:
    """One `enabledPlugins` entry in a managed settings file."""

    plugin_id: str
    enabled: bool
    file: Path

    @property
    def name(self) -> str:
        """The plugin name: the id before its last `@`."""
        return self.plugin_id.rpartition("@")[0]

    @property
    def marketplace(self) -> str:
        """The marketplace name: the id after its last `@`."""
        return self.plugin_id.rpartition("@")[2]


def name_key(name: str) -> str:
    """A plugin name as Claude Code compares it: NFC-normalized and lower-cased."""
    return unicodedata.normalize("NFC", name).lower()


def read_json(path: Path) -> object:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as e:
        raise UsageError(f"can't read {path}: {e}") from e


def expect(value: object, kind: type, what: str, file: Path) -> object:
    """VALUE, if it's a KIND; otherwise a UsageError naming WHAT and FILE."""
    if not isinstance(value, kind):
        raise UsageError(
            f"{file}: {what} is {json.dumps(value)}, not a JSON {JSON_KINDS[kind]}"
        )
    return value


def manifest_name(path: Path) -> str:
    """The name in a plugin's .claude-plugin/plugin.json, which Claude Code compares by,
    or the directory's name when it has none."""
    manifest = path / ".claude-plugin" / "plugin.json"
    if not manifest.is_file():
        return path.name
    data = expect(read_json(manifest), dict, "the manifest", manifest)
    return expect(data.get("name", path.name), str, "its name", manifest)


def marketplace_plugins(root: Path, marketplace: object) -> list[Plugin]:
    """The local plugins a parsed .claude-plugin/marketplace.json lists, resolved against root.

    A `./` source resolves against the root, and a bare name under
    `metadata.pluginRoot`. Sources that aren't paths (GitHub, git, npm) are
    skipped, since `--plugin-dir` loads only a directory.
    """
    file = root / ".claude-plugin" / "marketplace.json"
    market = expect(marketplace, dict, "the marketplace", file)
    metadata = expect(market.get("metadata", {}), dict, "metadata", file)
    plugin_root = metadata.get("pluginRoot")
    if plugin_root is not None:
        expect(plugin_root, str, "metadata.pluginRoot", file)
    plugins = []
    for entry in expect(market.get("plugins", []), list, "plugins", file):
        expect(entry, dict, "a plugins entry", file)
        source = entry.get("source")
        if not isinstance(source, str):
            print(
                f"claude-plugin-dev: skipping {entry.get('name')}, whose source isn't a local path",
                file=sys.stderr,
            )
            continue
        base = root / plugin_root if plugin_root and "/" not in source else root
        path = Path(os.path.normpath(base / source))
        if not path.is_dir():
            raise UsageError(
                f"{file} lists {entry.get('name')} at {source}, but {path} isn't a directory"
            )
        plugins.append(Plugin(manifest_name(path), path))
    return plugins


def managed_settings_files(folder: Path) -> list[Path]:
    """managed-settings.json, then every *.json in managed-settings.d/ in name order.

    Hidden files are left out, as Claude Code leaves them out.
    """
    main = folder / "managed-settings.json"
    drop_ins = folder / "managed-settings.d"
    found = [main] if main.is_file() else []
    if drop_ins.is_dir():
        found += sorted(
            p
            for p in drop_ins.glob("*.json")
            if p.is_file() and not p.name.startswith(".")
        )
    return found


def read_managed_settings(files: list[Path]) -> list[tuple[Path, object]]:
    """Each file paired with its parsed settings."""
    return [(f, read_json(f)) for f in files]


def managed_entries(settings: list[tuple[Path, object]]) -> list[ManagedEntry]:
    """The `enabledPlugins` entries across the managed settings files that Claude Code
    counts: a boolean value on an id holding an `@`."""
    entries = []
    for f, s in settings:
        s = expect(s, dict, "the settings", f)
        enabled = expect(s.get("enabledPlugins", {}), dict, "enabledPlugins", f)
        entries += [
            ManagedEntry(plugin_id, value, f)
            for plugin_id, value in enabled.items()
            if "@" in plugin_id and isinstance(value, bool)
        ]
    return entries


def locks(
    plugins: list[Plugin], entries: list[ManagedEntry]
) -> list[tuple[Plugin, ManagedEntry]]:
    """Each plugin a managed entry locks: one of the same name, `true` or `false`.

    Claude Code ignores the `--plugin-dir` copy of such a plugin.
    """
    return [
        (p, e) for p in plugins for e in entries if name_key(e.name) == name_key(p.name)
    ]


def from_module(entry: ManagedEntry, marketplace: str) -> bool:
    """Whether the nix-darwin module wrote ENTRY: a drop-in entry in its marketplace,
    which services.agent-plugins.unmanaged removes."""
    return entry.file.parent.name == DROP_IN_FOLDER and entry.marketplace == marketplace


def lock_message(found: list[tuple[Plugin, ManagedEntry]], marketplace: str) -> str:
    """Why the command stopped, and what lets it start: the unmanaged line for the
    module's entries, and removing each other entry from its file."""
    lines = [
        "managed settings lock these plugins, so claude would ignore their --plugin-dir:"
    ]
    for p, e in found:
        verb = "enables" if e.enabled else "disables"
        lines.append(f"  {p.name}: {e.file} {verb} {e.plugin_id}")
    module = list(
        dict.fromkeys(e.name for _, e in found if from_module(e, marketplace))
    )
    if module:
        quoted = " ".join(json.dumps(n) for n in module)
        lines += [
            "Add this to the nix-darwin configuration, switch, and run claude-plugin-dev again:",
            f"  services.agent-plugins.unmanaged = [ {quoted} ];",
        ]
    lines += [
        f"Remove `{e.plugin_id}` from {e.file}."
        for _, e in found
        if not from_module(e, marketplace)
    ]
    return "\n".join(lines)


def claude_command(plugins: list[Plugin], extra: list[str]) -> list[str]:
    dirs = [arg for p in plugins for arg in ("--plugin-dir", str(p.path))]
    return ["claude", *dirs, *extra]


def repo_root(git: str, cwd: Path | None = None) -> Path:
    try:
        done = subprocess.run(
            [git, "rev-parse", "--show-toplevel"],
            cwd=cwd,
            capture_output=True,
            text=True,
        )
    except OSError as e:
        raise UsageError(f"can't run {git} to find the repository root: {e}") from e
    if done.returncode != 0:
        raise UsageError(
            f"run it inside a git repository; {git} rev-parse said: {done.stderr.strip()}"
        )
    return Path(done.stdout.strip())


def managed_folder() -> Path:
    override = os.environ.get(MANAGED_SETTINGS_ENV)
    if override:
        return Path(override)
    return SYSTEM_FOLDERS.get(sys.platform, SYSTEM_FOLDERS["linux"])


def plan(extra: list[str], git: str, cwd: Path | None = None) -> list[str]:
    """The claude command line to run, or a UsageError saying why not."""
    root = repo_root(git, cwd)
    manifest = root / ".claude-plugin" / "marketplace.json"
    if not manifest.is_file():
        raise UsageError(f"{manifest} doesn't exist")
    plugins = marketplace_plugins(root, read_json(manifest))
    if not plugins:
        raise UsageError(f"{manifest} lists no local plugin")
    files = managed_settings_files(managed_folder())
    found = locks(plugins, managed_entries(read_managed_settings(files)))
    if found:
        marketplace = os.environ.get(MARKETPLACE_ENV) or MODULE_MARKETPLACE
        raise UsageError(lock_message(found, marketplace))
    return claude_command(plugins, extra)


def main(argv: list[str] | None = None) -> int:
    git = os.environ.pop(GIT_ENV, "git")
    try:
        command = plan(sys.argv[1:] if argv is None else argv, git)
    except UsageError as e:
        print(f"claude-plugin-dev: {e}", file=sys.stderr)
        return 1
    try:
        os.execvp(command[0], command)
    except OSError as e:
        print(f"claude-plugin-dev: can't run claude: {e}", file=sys.stderr)
        return 127


if __name__ == "__main__":
    sys.exit(main())
