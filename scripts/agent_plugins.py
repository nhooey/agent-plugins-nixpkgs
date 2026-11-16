#!/usr/bin/env python3
"""agent-plugins: build, check, format and update this flake from the dev shell.

Each command token runs one or more `nix` commands from the repository's root;
`--dry-run` prints them instead. The dev shell sets AGENT_PLUGINS_SYSTEM to the
Nix system it was built for.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

VENDORED_SUFFIX = "-src"


def root_inputs(lock: dict) -> list[str]:
    """Names of the root flake's inputs in a parsed flake.lock, sorted."""
    root = lock["nodes"][lock.get("root", "root")]
    return sorted(root.get("inputs", {}))


def vendored_inputs(lock: dict) -> list[str]:
    """The `flake = false` plugin sources: root inputs named `*-src`."""
    return [name for name in root_inputs(lock) if name.endswith(VENDORED_SUFFIX)]


def build_command(packages: list[str]) -> list[str]:
    return ["nix", "build", "--no-link", *(f".#{p}" for p in packages)]


def plan(args: argparse.Namespace, system: str, lock: dict) -> list[list[str]]:
    """The nix commands a parsed command line runs, in order.

    Pure: it reads only its arguments. `build --all` and `list` need the
    package names from an evaluation, so they plan that evaluation alone and
    `main` runs the builds from its output.
    """
    if args.command == "list" or (args.command == "build" and args.all):
        return [
            [
                "nix",
                "eval",
                "--json",
                f".#packages.{system}",
                "--apply",
                "builtins.attrNames",
            ]
        ]
    if args.command == "build":
        return [build_command(args.packages)]
    if args.command == "check":
        if not args.checks:
            return [["nix", "flake", "check"]]
        return [
            [
                "nix",
                "build",
                "--no-link",
                *(f".#checks.{system}.{c}" for c in args.checks),
            ]
        ]
    if args.command == "fmt":
        if args.check:
            return [["nix", "build", "--no-link", f".#checks.{system}.formatting"]]
        return [["nix", "fmt"]]
    if args.command == "update":
        known = root_inputs(lock)
        names = args.inputs or vendored_inputs(lock)
        unknown = [n for n in names if n not in known]
        if unknown:
            raise UsageError(
                f"unknown input {', '.join(unknown)}; inputs are {', '.join(known)}"
            )
        return [["nix", "flake", "update", *names]]
    if args.command == "skills":
        return [["nix", "run", "./skills-devshell#reconcile", "--", "--scope=project"]]
    raise UsageError(f"no plan for command {args.command!r}")


class UsageError(Exception):
    """A command line that parses but names something that doesn't exist."""


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="agent-plugins",
        description="Build, check, format and update the agent-plugins-nixpkgs flake.",
    )
    p.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="print the nix commands instead of running them",
    )
    sub = p.add_subparsers(dest="command", required=True, metavar="COMMAND")

    build = sub.add_parser("build", help="build plugin packages")
    build.add_argument(
        "packages", nargs="*", metavar="PACKAGE", help="package to build"
    )
    build.add_argument("-a", "--all", action="store_true", help="build every package")

    check = sub.add_parser("check", help="run the flake's checks")
    check.add_argument(
        "checks",
        nargs="*",
        metavar="CHECK",
        help="run only this check, such as darwin-module (default: nix flake check)",
    )

    fmt = sub.add_parser("fmt", help="format the files with treefmt")
    fmt.add_argument(
        "--check",
        action="store_true",
        help="fail if formatting would change a file, changing nothing",
    )

    sub.add_parser("list", help="list the plugin packages")

    update = sub.add_parser("update", help="bump flake inputs in flake.lock")
    update.add_argument(
        "inputs",
        nargs="*",
        metavar="INPUT",
        help="input to bump, such as cc-safety-net-src (default: every *-src input)",
    )

    sub.add_parser(
        "skills",
        help="install the agent skills in .agents/skills/, as entering the shell does",
    )
    return p


def parse(argv: list[str]) -> argparse.Namespace:
    p = parser()
    args = p.parse_args(argv)
    if args.command == "build" and bool(args.packages) == args.all:
        p.error("build takes PACKAGE names or --all, not both or neither")
    return args


def repo_root() -> Path:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        return Path(out)
    except (OSError, subprocess.CalledProcessError):
        return Path.cwd()


def current_system() -> str:
    system = os.environ.get("AGENT_PLUGINS_SYSTEM")
    if system:
        return system
    return subprocess.run(
        ["nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def run(cmd: list[str], root: Path, dry_run: bool, capture: bool = False) -> str:
    print(f"+ {shlex.join(cmd)}", file=sys.stderr)
    if dry_run:
        return ""
    done = subprocess.run(cmd, cwd=root, check=True, capture_output=capture, text=True)
    return done.stdout if capture else ""


def main(argv: list[str] | None = None) -> int:
    args = parse(sys.argv[1:] if argv is None else argv)
    root = repo_root()
    lock = json.loads((root / "flake.lock").read_text())
    try:
        commands = plan(args, current_system(), lock)
    except UsageError as e:
        print(f"agent-plugins: {e}", file=sys.stderr)
        return 2
    try:
        if args.command == "list" or (args.command == "build" and args.all):
            out = run(commands[0], root, args.dry_run, capture=True)
            if args.command == "list":
                print("\n".join(json.loads(out)) if out else "")
                return 0
            names = json.loads(out) if out else ["<each package>"]
            commands = [build_command(names)]
        for cmd in commands:
            run(cmd, root, args.dry_run)
    except subprocess.CalledProcessError as e:
        return e.returncode or 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
