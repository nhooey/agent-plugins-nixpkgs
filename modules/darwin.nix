# nix-darwin module: builds Claude Code plugins into a Nix-pinned marketplace installed through a
# root-owned managed settings drop-in. Managed plugins are enabled there too, so no session or
# user setting can turn them off; user plugins are only installed, for the user to enable.
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
    plugins = cfg.managedPlugins ++ cfg.userPlugins;
  };
  pluginNames = map (p: p.claudePluginName) (cfg.managedPlugins ++ cfg.userPlugins);
  duplicateNames = lib.unique (lib.filter (n: lib.count (m: m == n) pluginNames > 1) pluginNames);
  # User plugins that extraSettings enables or disables, which would lock them as managed ones.
  userPluginsInExtra = lib.intersectLists (map (
    p: "${p.claudePluginName}@${cfg.marketplaceName}"
  ) cfg.userPlugins) (lib.attrNames (cfg.extraSettings.enabledPlugins or { }));
  safetyNetHome = pluginLib.mkSafetyNetHome pkgs {
    inherit (cfg.ccSafetyNet) rulebooks transparentWrappers;
  };
  # Written even when empty, so every hook finds the file and reads `remind` for itself.
  hookModesFile = pkgs.writeText "hook-modes.json" (builtins.toJSON cfg.hookModes);
  settings = lib.recursiveUpdate {
    extraKnownMarketplaces.${cfg.marketplaceName}.source = {
      source = "directory";
      path = "${marketplace}";
    };
    enabledPlugins = lib.listToAttrs (
      map (p: lib.nameValuePair "${p.claudePluginName}@${cfg.marketplaceName}" true) cfg.managedPlugins
    );
    env = {
      AGENT_HOOK_MODES = "${hookModesFile}";
    }
    // lib.optionalAttrs (cfg.ccSafetyNet.rulebooks != [ ]) {
      CC_SAFETY_NET_HOME = "${safetyNetHome}";
    };
  } cfg.extraSettings;
in
{
  imports = [
    (lib.mkRenamedOptionModule
      [ "services" "agent-plugins" "plugins" ]
      [ "services" "agent-plugins" "managedPlugins" ]
    )
  ];

  options.services.agent-plugins = {
    enable = lib.mkEnableOption "Claude Code plugins installed from a Nix-built marketplace";

    managedPlugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ inputs.agent-plugins-nixpkgs.packages.\${system}.cc-safety-net ]";
      description = ''
        Plugins to install and enable. They're enabled in the root-owned managed drop-in, so no
        session or user setting can turn them off. Each needs passthru.claudePluginName
        (mkClaudePlugin sets it).
      '';
    };

    userPlugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ inputs.my-plugin.packages.\${system}.plugin ]";
      description = ''
        Plugins to install in the same marketplace without enabling them. The user enables each in
        their own settings as <claudePluginName>@<marketplaceName>, so `claude --plugin-dir` can
        override it, which a managed enabledPlugins entry would lock out. Each needs
        passthru.claudePluginName (mkClaudePlugin sets it).
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

    ccSafetyNet.transparentWrappers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "nix" ];
      description = ''
        Commands written into rule.json's `transparent_wrappers`: the rulebooks' rules also apply
        to a protected command found among such a command's arguments, so with "nix" a rule on
        `op` blocks `nix develop --command op ...` too. Once Safety Net finds a command inside a
        wrapper, the wrapper's own rules no longer apply to that call. Only takes effect with
        rulebooks set.
      '';
    };

    hookModes = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.enum [
          "off"
          "remind"
          "deny"
        ]
      );
      default = { };
      example = {
        scratchpad-guard = "deny";
        reply-lint = "off";
      };
      description = ''
        Each hook's mode, by hook name: `deny` denies the action, `remind` adds context saying
        what it would have denied and lets it run, `off` does nothing. Written to a store file
        whose path is env.AGENT_HOOK_MODES in the drop-in; a hook reads it through the
        lib/hook-mode.sh helper mkClaudePlugin copies into its plugin. A hook not named here
        is at `remind`, so a new hook ships at `remind` and moves to `deny` only by a change here.
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
    assertions = [
      {
        assertion = duplicateNames == [ ];
        message = "services.agent-plugins: managedPlugins and userPlugins list these plugin names more than once; list each once, in one of them: ${lib.concatStringsSep ", " duplicateNames}";
      }
      {
        assertion = userPluginsInExtra == [ ];
        message = "services.agent-plugins: extraSettings.enabledPlugins sets these userPlugins, which would lock them in managed settings; enable them in user settings, or move them to managedPlugins: ${lib.concatStringsSep ", " userPluginsInExtra}";
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
