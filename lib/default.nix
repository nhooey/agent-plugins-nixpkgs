# Builders for Claude Code plugins. Each takes `pkgs` first, so they work for any system.
{ lib }:
{
  # A plugin directory (one holding .claude-plugin/plugin.json) copied into the store, with
  # optional patches. The name and version come from the plugin's own manifest. The result is
  # overridable, so a consumer can drop skills it doesn't want from a plugin it loads whole:
  #   packages.superpowers.override { excludeSkills = [ "diagnosing-superpowers" ]; }
  mkClaudePlugin =
    pkgs:
    lib.makeOverridable (
      {
        src,
        # Names of directories under skills/ to leave out. A name the plugin doesn't have is an
        # error, so a rename upstream can't silently bring a skill back.
        excludeSkills ? [ ],
        # Shell run in the copy, e.g. to point a hook at a store path.
        postPatch ? "",
      }:
      let
        manifest = lib.importJSON "${src}/.claude-plugin/plugin.json";
      in
      pkgs.runCommand "claude-plugin-${manifest.name}-${manifest.version}"
        {
          inherit postPatch;
          passthru = {
            claudePluginName = manifest.name;
            inherit (manifest) version;
          };
        }
        ''
          cp -r ${src} $out
          chmod -R u+w $out
          cd $out
          ${lib.concatMapStrings (name: ''
            rm -r ${lib.escapeShellArg "skills/${name}"}
          '') excludeSkills}
          runHook postPatch
        ''
    );

  # A local plugin marketplace listing `plugins` (from mkClaudePlugin, or any derivation with
  # passthru.claudePluginName) by relative path. Claude Code reads plugins straight from it,
  # so pointing managed settings at its store path installs exactly these builds.
  mkMarketplace =
    pkgs:
    {
      name,
      owner,
      plugins,
    }:
    let
      entries = map (p: {
        name = p.claudePluginName;
        source = "./${p.claudePluginName}";
        version = p.version or "0";
      }) plugins;
      manifest = pkgs.writeText "marketplace.json" (
        builtins.toJSON {
          inherit name;
          owner.name = owner;
          plugins = entries;
        }
      );
    in
    pkgs.runCommand "claude-plugin-marketplace-${name}" { } ''
      mkdir -p $out/.claude-plugin
      cp ${manifest} $out/.claude-plugin/marketplace.json
      ${lib.concatMapStrings (p: ''
        ln -s ${p} $out/${p.claudePluginName}
      '') plugins}
    '';

  # A CC Safety Net home folder (what CC_SAFETY_NET_HOME points at) holding rules/rule.json and
  # one rules/<name>/rulebook.json per rulebook, as real files: Safety Net refuses symlinked
  # config files. `rulebooks` are rulebook.json contents as attribute sets.
  mkSafetyNetHome =
    pkgs: rulebooks:
    let
      ruleConfig = pkgs.writeText "rule.json" (
        builtins.toJSON {
          version = 1;
          rules = map (r: r.name) rulebooks;
        }
      );
    in
    pkgs.runCommand "cc-safety-net-home" { } ''
      mkdir -p $out/rules
      cp ${ruleConfig} $out/rules/rule.json
      ${lib.concatMapStrings (r: ''
        mkdir -p $out/rules/${r.name}
        cp ${pkgs.writeText "rulebook.json" (builtins.toJSON r)} $out/rules/${r.name}/rulebook.json
      '') rulebooks}
    '';
}
