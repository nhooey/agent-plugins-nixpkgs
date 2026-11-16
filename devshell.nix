# The dev shell, a numtide/devshell: `menu` lists its commands, and entering it installs the agent
# skills in `.agents/skills/` from the `skills-devshell/` sub-flake, run by path so its skill
# inputs stay out of this flake's lock.
{
  pkgs,
  mkShell,
  agent-plugins,
}:
mkShell {
  name = "agent-plugins-nixpkgs";
  motd = ''
    {bold}{14}🚀 Entering agent-plugins-nixpkgs dev shell{reset}
    Run {bold}menu{reset} to list available commands.
  '';
  packages = [ pkgs.nixfmt ];
  commands = [
    # flake
    {
      category = "flake";
      package = agent-plugins;
      help = "build, check, fmt, list, update or skills; --help for each";
    }
  ];
  devshell.startup.agent-skills.text = "agent-plugins skills";
}
