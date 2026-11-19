# The agent-plugins tool: its unit tests pass, its --help lists every command token, and a dry run
# prints the nix command a token stands for, validating input names against flake.lock.
{
  self,
  pkgs,
  agent-plugins,
}:
pkgs.runCommand "check-agent-plugins-cli"
  {
    nativeBuildInputs = [
      pkgs.python3
      agent-plugins
    ];
  }
  ''
    PYTHONPATH=${../scripts} python3 -m unittest discover -s ${./.} -p 'test_agent_plugins.py' -v

    cp ${self}/flake.lock .
    help=$(agent-plugins --help)
    for token in build check fmt list update skills; do
      grep -qw "$token" <<<"$help" || { echo "--help lacks $token"; exit 1; }
    done

    printed=$(agent-plugins --dry-run update cc-safety-net-src 2>&1)
    [[ $printed == "+ nix flake update cc-safety-net-src" ]] || { echo "dry run printed: $printed"; exit 1; }
    if agent-plugins --dry-run update no-such-src 2>/dev/null; then
      echo "update accepted an input flake.lock lacks"; exit 1
    fi

    touch $out
  ''
