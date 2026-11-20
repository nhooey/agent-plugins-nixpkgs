# A flake-parts module for a repository that is, or holds, a Claude Code plugin: it builds the
# plugin folder with lib.mkClaudePlugin as packages.<packageName>, and, when the consumer also
# imports numtide devshell's flake module, adds a `plugin-build` command that builds it into
# result-plugin.
{ self }:
{ flake-parts-lib, lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      options,
      pkgs,
      ...
    }:
    let
      cfg = config.agent-plugins.claudePlugin;
    in
    {
      options.agent-plugins.claudePlugin = {
        enable = mkEnableOption "building the repository's Claude Code plugin as a package";
        src = mkOption {
          type = types.path;
          description = "The plugin's root, holding .claude-plugin/plugin.json, as a path such as ./.";
        };
        include = mkOption {
          type = types.listOf types.str;
          default = [
            ".claude-plugin/plugin.json"
            "defaults"
            "hooks"
            "src"
            "types"
          ];
          description = "Paths relative to `src` copied into the plugin; one that doesn't exist is skipped.";
        };
        postPatch = mkOption {
          type = types.lines;
          default = "";
          example = lib.literalExpression ''"cp ''${pluginVendor}/* vendor/"'';
          description = ''
            Shell run in the plugin's copy, after the hook-mode helper is added, to add or change
            files, such as bundles built by another derivation.
          '';
        };
        packageName = mkOption {
          type = types.str;
          default = "plugin";
          description = "The name of the package the plugin is built as.";
        };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            packages.${cfg.packageName} = self.lib.mkClaudePlugin pkgs {
              inherit (cfg) src include postPatch;
            };
          }
          # Only with devshell's flake module imported, so a consumer without it still evaluates.
          (lib.optionalAttrs (options ? devshells) {
            devshells.default.commands = [
              {
                category = "build";
                name = "plugin-build";
                help = "build the Claude Code plugin (${cfg.packageName}) into result-plugin";
                command = ''nix build "$PRJ_ROOT#${cfg.packageName}" --out-link "$PRJ_ROOT/result-plugin"'';
              }
            ];
          })
        ]
      );
    }
  );
}
