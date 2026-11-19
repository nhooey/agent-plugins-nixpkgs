# `agent-plugins`, the command-line tool in scripts/agent_plugins.py, told the system it was built
# for so it needn't evaluate `builtins.currentSystem`. It runs the caller's `nix`.
{
  writeShellApplication,
  python3,
  git,
  stdenv,
}:
writeShellApplication {
  name = "agent-plugins";
  runtimeInputs = [
    python3
    git
  ];
  text = ''
    export AGENT_PLUGINS_SYSTEM=${stdenv.hostPlatform.system}
    exec python3 -I ${./agent_plugins.py} "$@"
  '';
}
