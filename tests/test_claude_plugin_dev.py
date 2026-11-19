"""The core of scripts/claude_plugin_dev.py: plugins from a marketplace, locks from managed settings.

Run with the script's directory on sys.path:
    PYTHONPATH=scripts python3 -m unittest discover -s tests -p 'test_claude_plugin_dev.py'
"""

from __future__ import annotations

import contextlib
import io
import json
import subprocess
import tempfile
import unicodedata
import unittest
from pathlib import Path

import claude_plugin_dev as cpd


def write_json(path: Path, value) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value))
    return path


class TempDirTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)

    def plugin(self, rel: str, manifest=None) -> Path:
        """A plugin directory; a str manifest is its name, anything else its plugin.json."""
        d = self.root / rel
        d.mkdir(parents=True)
        if isinstance(manifest, str):
            write_json(d / ".claude-plugin" / "plugin.json", {"name": manifest})
        elif manifest is not None:
            write_json(d / ".claude-plugin" / "plugin.json", manifest)
        return d

    def plugins(self, market):
        with contextlib.redirect_stderr(io.StringIO()):
            return cpd.marketplace_plugins(self.root, market)


class MarketplacePlugins(TempDirTest):
    def test_relative_sources_resolve_against_the_root(self):
        alpha = self.plugin("plugins/alpha", "alpha")
        beta = self.plugin("beta", "beta")
        market = {
            "plugins": [
                {"name": "alpha", "source": "./plugins/alpha"},
                {"name": "beta", "source": "./beta"},
            ]
        }
        self.assertEqual(
            self.plugins(market),
            [cpd.Plugin("alpha", alpha), cpd.Plugin("beta", beta)],
        )

    def test_bare_names_resolve_under_plugin_root_and_dot_slash_against_the_root(self):
        beta = self.plugin("beta", "beta")
        gamma = self.plugin("plugins/gamma", "gamma")
        market = {
            "metadata": {"pluginRoot": "./plugins"},
            "plugins": [
                {"name": "beta", "source": "./beta"},
                {"name": "gamma", "source": "gamma"},
            ],
        }
        self.assertEqual(
            self.plugins(market),
            [cpd.Plugin("beta", beta), cpd.Plugin("gamma", gamma)],
        )

    def test_the_manifest_name_wins_over_the_entry_name(self):
        d = self.plugin("mod", "manifest-name")
        market = {"plugins": [{"name": "entry-name", "source": "./mod"}]}
        self.assertEqual(self.plugins(market), [cpd.Plugin("manifest-name", d)])

    def test_a_plugin_without_a_manifest_takes_its_directory_name(self):
        d = self.plugin("mod")
        market = {"plugins": [{"name": "entry-name", "source": "./mod"}]}
        self.assertEqual(self.plugins(market), [cpd.Plugin("mod", d)])

    def test_remote_sources_are_skipped(self):
        d = self.plugin("local", "local")
        market = {
            "plugins": [
                {"name": "remote", "source": {"source": "github", "repo": "o/r"}},
                {"name": "local", "source": "./local"},
            ]
        }
        with contextlib.redirect_stderr(io.StringIO()) as err:
            found = cpd.marketplace_plugins(self.root, market)
        self.assertEqual(found, [cpd.Plugin("local", d)])
        self.assertIn("remote", err.getvalue())

    def test_a_missing_directory_is_an_error(self):
        market = {"plugins": [{"name": "gone", "source": "./gone"}]}
        with self.assertRaisesRegex(cpd.UsageError, "gone"):
            self.plugins(market)

    def test_unexpected_shapes_name_the_marketplace_file(self):
        self.plugin("ok", "ok")
        for market in (
            [],
            {"metadata": None, "plugins": []},
            {"metadata": {"pluginRoot": 3}, "plugins": []},
            {"plugins": None},
            {"plugins": ["./ok"]},
        ):
            with self.subTest(market=market):
                with self.assertRaisesRegex(cpd.UsageError, "marketplace.json"):
                    self.plugins(market)

    def test_a_plugin_json_that_isnt_an_object_is_an_error(self):
        for i, manifest in enumerate(([], {"name": 3})):
            with self.subTest(manifest=manifest):
                rel = f"p{i}"
                self.plugin(rel, manifest)
                market = {"plugins": [{"name": rel, "source": f"./{rel}"}]}
                with self.assertRaisesRegex(cpd.UsageError, "plugin.json"):
                    self.plugins(market)


class ManagedSettings(TempDirTest):
    def test_files_are_the_main_file_then_drop_ins_in_order(self):
        main = write_json(self.root / "managed-settings.json", {})
        d = self.root / "managed-settings.d"
        b = write_json(d / "20-b.json", {})
        a = write_json(d / "10-a.json", {})
        write_json(d / ".hidden.json", {})
        (d / "notes.txt").write_text("not settings")
        self.assertEqual(cpd.managed_settings_files(self.root), [main, a, b])

    def test_a_missing_folder_has_no_files(self):
        self.assertEqual(cpd.managed_settings_files(self.root / "absent"), [])

    def test_entries_name_the_plugin_and_marketplace_of_each_id(self):
        f = Path("40-agent-plugins.json")
        settings = {"enabledPlugins": {"alpha@nix-pinned": True, "beta@other": False}}
        self.assertEqual(
            cpd.managed_entries([(f, settings), (Path("x.json"), {"env": {}})]),
            [
                cpd.ManagedEntry("alpha@nix-pinned", True, f),
                cpd.ManagedEntry("beta@other", False, f),
            ],
        )
        entry = cpd.ManagedEntry("alpha@nix-pinned", True, f)
        self.assertEqual((entry.name, entry.marketplace), ("alpha", "nix-pinned"))

    def test_only_boolean_values_on_ids_with_an_at_count(self):
        f = Path("m.json")
        settings = {
            "enabledPlugins": {
                "alpha": True,
                "beta@m": "yes",
                "gamma@m": ["x"],
                "delta@m": None,
                "epsilon@m": 1,
                "zeta@m": False,
            }
        }
        self.assertEqual(
            cpd.managed_entries([(f, settings)]),
            [cpd.ManagedEntry("zeta@m", False, f)],
        )

    def test_unexpected_shapes_name_the_managed_file(self):
        for settings in ([], {"enabledPlugins": None}, {"enabledPlugins": []}):
            with self.subTest(settings=settings):
                f = Path("/managed/managed-settings.d/50-odd.json")
                with self.assertRaisesRegex(cpd.UsageError, "50-odd.json"):
                    cpd.managed_entries([(f, settings)])

    def test_a_top_level_array_in_a_file_names_it(self):
        f = write_json(self.root / "managed-settings.json", [1])
        with self.assertRaisesRegex(cpd.UsageError, "managed-settings.json"):
            cpd.managed_entries(cpd.read_managed_settings([f]))

    def test_invalid_json_is_an_error(self):
        bad = self.root / "managed-settings.json"
        bad.write_text("{")
        with self.assertRaisesRegex(cpd.UsageError, "managed-settings.json"):
            cpd.read_managed_settings([bad])


class Locks(unittest.TestCase):
    alpha = cpd.Plugin("alpha", Path("/repo/alpha"))
    beta = cpd.Plugin("beta", Path("/repo/beta"))
    drop_in = Path("/managed/managed-settings.d/40-agent-plugins.json")
    other_drop_in = Path("/managed/managed-settings.d/50-command-guards.json")
    main_file = Path("/managed/managed-settings.json")

    def test_a_managed_entry_of_the_same_name_locks_the_plugin(self):
        entry = cpd.ManagedEntry("alpha@nix-pinned", True, self.drop_in)
        other = cpd.ManagedEntry("gamma@nix-pinned", True, self.drop_in)
        self.assertEqual(
            cpd.locks([self.alpha, self.beta], [entry, other]), [(self.alpha, entry)]
        )

    def test_no_managed_entry_of_the_same_name_locks_nothing(self):
        other = cpd.ManagedEntry("gamma@nix-pinned", True, self.drop_in)
        self.assertEqual(cpd.locks([self.alpha, self.beta], [other]), [])

    def test_names_match_ignoring_case(self):
        entry = cpd.ManagedEntry("ALPHA@nix-pinned", True, self.drop_in)
        self.assertEqual(cpd.locks([self.alpha], [entry]), [(self.alpha, entry)])

    def test_names_match_across_unicode_normal_forms(self):
        composed = unicodedata.normalize("NFC", "café")
        decomposed = unicodedata.normalize("NFD", "café")
        self.assertNotEqual(composed, decomposed)
        plugin = cpd.Plugin(decomposed, Path("/repo/cafe"))
        entry = cpd.ManagedEntry(f"{composed}@nix-pinned", True, self.drop_in)
        self.assertEqual(cpd.locks([plugin], [entry]), [(plugin, entry)])

    def test_a_module_drop_in_entry_gets_the_line_to_add(self):
        entry = cpd.ManagedEntry("alpha@nix-pinned", True, self.drop_in)
        message = cpd.lock_message([(self.alpha, entry)], "nix-pinned")
        self.assertIn("alpha@nix-pinned", message)
        self.assertIn(str(self.drop_in), message)
        self.assertIn('services.agent-plugins.unmanaged = [ "alpha" ];', message)
        self.assertNotIn("Remove", message)

    def test_the_line_lists_every_module_lock(self):
        entries = [
            cpd.ManagedEntry("alpha@nix-pinned", True, self.drop_in),
            cpd.ManagedEntry("beta@nix-pinned", False, self.drop_in),
        ]
        message = cpd.lock_message(
            list(zip([self.alpha, self.beta], entries)), "nix-pinned"
        )
        self.assertIn('services.agent-plugins.unmanaged = [ "alpha" "beta" ];', message)
        self.assertIn("disables beta@nix-pinned", message)

    def test_the_line_takes_the_name_from_the_managed_entry(self):
        entry = cpd.ManagedEntry("Alpha@nix-pinned", True, self.drop_in)
        message = cpd.lock_message([(self.alpha, entry)], "nix-pinned")
        self.assertIn('services.agent-plugins.unmanaged = [ "Alpha" ];', message)

    def test_other_entries_are_to_be_removed_from_their_file(self):
        cases = [
            cpd.ManagedEntry("alpha@nix-pinned", True, self.main_file),
            cpd.ManagedEntry("alpha@company", True, self.drop_in),
            cpd.ManagedEntry("alpha@company", False, self.other_drop_in),
        ]
        for entry in cases:
            with self.subTest(entry=entry):
                message = cpd.lock_message([(self.alpha, entry)], "nix-pinned")
                self.assertIn(f"Remove `{entry.plugin_id}` from {entry.file}", message)
                self.assertNotIn("services.agent-plugins.unmanaged", message)

    def test_the_module_marketplace_name_is_a_parameter(self):
        entry = cpd.ManagedEntry("alpha@my-market", True, self.drop_in)
        message = cpd.lock_message([(self.alpha, entry)], "my-market")
        self.assertIn('services.agent-plugins.unmanaged = [ "alpha" ];', message)


class ClaudeCommand(unittest.TestCase):
    def test_one_plugin_dir_per_plugin_then_the_extra_arguments(self):
        plugins = [
            cpd.Plugin("alpha", Path("/repo/alpha")),
            cpd.Plugin("beta", Path("/repo/b e t a")),
        ]
        self.assertEqual(
            cpd.claude_command(plugins, ["--model", "opus", "fix it"]),
            [
                "claude",
                "--plugin-dir",
                "/repo/alpha",
                "--plugin-dir",
                "/repo/b e t a",
                "--model",
                "opus",
                "fix it",
            ],
        )


class Plan(TempDirTest):
    def git_init(self):
        subprocess.run(
            ["git", "init", "--quiet", str(self.root)], check=True, capture_output=True
        )

    def plan(self):
        with contextlib.redirect_stderr(io.StringIO()):
            return cpd.plan([], "git", cwd=self.root)

    def test_outside_a_git_repository_names_gits_complaint(self):
        with self.assertRaisesRegex(cpd.UsageError, "(?i)not a git repository"):
            self.plan()

    def test_a_missing_git_names_the_error(self):
        with self.assertRaisesRegex(cpd.UsageError, "no-such-git"):
            cpd.plan([], str(self.root / "no-such-git"), cwd=self.root)

    def test_a_repository_without_a_marketplace_is_an_error(self):
        self.git_init()
        with self.assertRaisesRegex(cpd.UsageError, "marketplace.json doesn't exist"):
            self.plan()

    def test_a_marketplace_of_only_remote_plugins_is_an_error(self):
        self.git_init()
        write_json(
            self.root / ".claude-plugin" / "marketplace.json",
            {"plugins": [{"name": "r", "source": {"source": "github", "repo": "o/r"}}]},
        )
        with self.assertRaisesRegex(cpd.UsageError, "lists no local plugin"):
            self.plan()


if __name__ == "__main__":
    unittest.main()
