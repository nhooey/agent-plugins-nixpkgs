# nix-darwin module: installs and enables Claude Code plugins through a root-owned managed
# settings drop-in, so they're pinned by Nix and no session or user setting can turn them off.
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.agent-plugins;
  pluginLib = self.lib;
  dropIns = "/Library/Application Support/ClaudeCode/managed-settings.d";
  marketplace = pluginLib.mkMarketplace pkgs {
    name = cfg.marketplaceName;
    owner = cfg.marketplaceOwner;
    inherit (cfg) plugins;
  };
  safetyNetHome = pluginLib.mkSafetyNetHome pkgs cfg.ccSafetyNet.rulebooks;
  merged = lib.recursiveUpdate {
    extraKnownMarketplaces.${cfg.marketplaceName}.source = {
      source = "directory";
      path = "${marketplace}";
    };
    enabledPlugins = lib.listToAttrs (
      map (p: lib.nameValuePair "${p.claudePluginName}@${cfg.marketplaceName}" true) cfg.plugins
    );
    env = lib.optionalAttrs (cfg.ccSafetyNet.rulebooks != [ ]) {
      CC_SAFETY_NET_HOME = "${safetyNetHome}";
    };
  } cfg.extraSettings;
  # The name part of a plugin id (before its last `@`), lower-cased as Claude Code compares it.
  idName =
    id:
    let
      parts = lib.splitString "@" id;
    in
    lib.toLower (lib.concatStringsSep "@" (lib.init parts));
  unmanagedNames = map lib.toLower cfg.unmanaged;
  # Any entry naming an unmanaged plugin locks it, under any marketplace and with either value,
  # so none is left, including those extraSettings adds.
  settings = merged // {
    enabledPlugins = lib.filterAttrs (id: _: !lib.elem (idName id) unmanagedNames) (
      merged.enabledPlugins
    );
  };
in
{
  options.services.agent-plugins = {
    enable = lib.mkEnableOption "Claude Code plugins installed from a Nix-built marketplace";

    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ inputs.agent-plugins-nixpkgs.packages.\${system}.cc-safety-net ]";
      description = "Plugins to install and enable. Each needs passthru.claudePluginName (mkClaudePlugin sets it).";
    };

    unmanaged = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "coding-agent-kanban-turns" ];
      description = ''
        Names (claudePluginName) of plugins in `plugins` to leave out of the managed
        `enabledPlugins`, while they stay in the marketplace. A managed entry locks every plugin
        of its name, so `claude --plugin-dir` can load a working copy of these only once they're
        listed here. Every `enabledPlugins` entry of these names is dropped, under any
        marketplace, including those `extraSettings` adds. A name that matches no plugin fails
        an assertion.
      '';
    };

    marketplaceName = lib.mkOption {
      type = lib.types.str;
      default = "nix-pinned";
      description = "Name of the generated marketplace; plugins are enabled as <plugin>@<this>.";
    };

    marketplaceOwner = lib.mkOption {
      type = lib.types.str;
      default = "nix";
      description = "Owner name written into the marketplace manifest.";
    };

    ccSafetyNet.rulebooks = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = ''
        CC Safety Net rulebooks (rulebook.json contents). When set, they're built into a read-only
        store folder and CC_SAFETY_NET_HOME points the plugin at it, so no session can edit them.
        Safety Net still writes its audit log to ~/.cc-safety-net/logs.
      '';
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "More managed settings merged into the drop-in.";
    };

    dropInName = lib.mkOption {
      type = lib.types.str;
      default = "40-agent-plugins.json";
      description = "File name of the drop-in under ${dropIns}.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      let
        names = map (p: p.claudePluginName) cfg.plugins;
        unknown = lib.filter (n: !lib.elem n names) cfg.unmanaged;
      in
      [
        {
          assertion = unknown == [ ];
          message = "services.agent-plugins.unmanaged names ${builtins.toJSON unknown}, which match no plugin in services.agent-plugins.plugins: ${builtins.toJSON names}.";
        }
      ];

    # Nix doesn't track the installed file: disabling the module leaves it in place, so remove it
    # by hand (with sudo) afterwards.
    system.activationScripts.postActivation.text = ''
      install -d -m u=rwx,go=rx "${dropIns}"
      install -m u=rw,go=r ${pkgs.writeText "claude-agent-plugins.json" (builtins.toJSON settings)} "${dropIns}/${cfg.dropInName}"
    '';
  };
}
