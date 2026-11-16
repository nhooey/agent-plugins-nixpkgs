"""Argument parsing and command planning of scripts/agent_plugins.py.

Run with the script's directory on sys.path:
    PYTHONPATH=scripts python3 -m unittest discover -s tests -p 'test_*.py'
"""

import contextlib
import io
import unittest

import agent_plugins as ap

SYSTEM = "aarch64-darwin"
LOCK = {
    "root": "root",
    "nodes": {
        "root": {
            "inputs": {
                "nixpkgs": "nixpkgs",
                "superpowers-src": "superpowers-src",
                "cc-safety-net-src": "cc-safety-net-src",
                "treefmt-nix": "treefmt-nix",
            }
        }
    },
}


def plan(*argv):
    return ap.plan(ap.parse(list(argv)), SYSTEM, LOCK)


def parse_fails(*argv):
    """The exit status argparse gives a bad command line."""
    try:
        with contextlib.redirect_stderr(io.StringIO()):
            ap.parse(list(argv))
    except SystemExit as e:
        return e.code
    raise AssertionError(f"parse accepted {argv}")


class Inputs(unittest.TestCase):
    def test_root_inputs_sorted(self):
        self.assertEqual(
            ap.root_inputs(LOCK),
            ["cc-safety-net-src", "nixpkgs", "superpowers-src", "treefmt-nix"],
        )

    def test_vendored_inputs_are_the_src_ones(self):
        self.assertEqual(
            ap.vendored_inputs(LOCK), ["cc-safety-net-src", "superpowers-src"]
        )


class Parse(unittest.TestCase):
    def test_a_command_is_required(self):
        self.assertEqual(parse_fails(), 2)

    def test_unknown_command_fails(self):
        self.assertEqual(parse_fails("deploy"), 2)

    def test_build_needs_packages_or_all(self):
        self.assertEqual(parse_fails("build"), 2)

    def test_build_rejects_packages_with_all(self):
        self.assertEqual(parse_fails("build", "--all", "superpowers"), 2)

    def test_dry_run_is_global(self):
        self.assertTrue(ap.parse(["--dry-run", "fmt"]).dry_run)
        self.assertTrue(ap.parse(["-n", "check"]).dry_run)

    def test_help_lists_every_command_token(self):
        text = ap.parser().format_help()
        for token in ("build", "check", "fmt", "list", "update", "skills"):
            self.assertIn(token, text)


class Plan(unittest.TestCase):
    def test_build_named_packages(self):
        self.assertEqual(
            plan("build", "cc-safety-net", "superpowers"),
            [["nix", "build", "--no-link", ".#cc-safety-net", ".#superpowers"]],
        )

    def test_build_all_and_list_evaluate_package_names(self):
        expected = [
            [
                "nix",
                "eval",
                "--json",
                f".#packages.{SYSTEM}",
                "--apply",
                "builtins.attrNames",
            ]
        ]
        self.assertEqual(plan("build", "--all"), expected)
        self.assertEqual(plan("list"), expected)

    def test_check_without_names_runs_flake_check(self):
        self.assertEqual(plan("check"), [["nix", "flake", "check"]])

    def test_check_with_names_builds_those_checks(self):
        self.assertEqual(
            plan("check", "marketplace", "darwin-module"),
            [
                [
                    "nix",
                    "build",
                    "--no-link",
                    f".#checks.{SYSTEM}.marketplace",
                    f".#checks.{SYSTEM}.darwin-module",
                ]
            ],
        )

    def test_fmt_and_fmt_check(self):
        self.assertEqual(plan("fmt"), [["nix", "fmt"]])
        self.assertEqual(
            plan("fmt", "--check"),
            [["nix", "build", "--no-link", f".#checks.{SYSTEM}.formatting"]],
        )

    def test_update_defaults_to_vendored_sources(self):
        self.assertEqual(
            plan("update"),
            [["nix", "flake", "update", "cc-safety-net-src", "superpowers-src"]],
        )

    def test_update_named_input(self):
        self.assertEqual(
            plan("update", "nixpkgs"), [["nix", "flake", "update", "nixpkgs"]]
        )

    def test_update_unknown_input_is_a_usage_error(self):
        with self.assertRaisesRegex(ap.UsageError, "unknown input no-such-src"):
            plan("update", "no-such-src")

    def test_skills_runs_the_sub_flake_reconcile(self):
        self.assertEqual(
            plan("skills"),
            [["nix", "run", "./skills-devshell#reconcile", "--", "--scope=project"]],
        )


if __name__ == "__main__":
    unittest.main()
