# activationText CFG: the activation script the nix-darwin module writes for
# services.agent-plugins = CFG, evaluated with the one nix-darwin option it sets declared here.
{ self, pkgs }:
cfg:
let
  inherit (pkgs) lib;
in
(lib.evalModules {
  modules = [
    self.darwinModules.default
    {
      options.system.activationScripts.postActivation.text = lib.mkOption {
        type = lib.types.lines;
        default = "";
      };
      config = {
        _module.args.pkgs = pkgs;
        services.agent-plugins = cfg;
      };
    }
  ];
}).config.system.activationScripts.postActivation.text
