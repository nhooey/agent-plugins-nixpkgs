# The nix-darwin module, evaluated with the nix-darwin options it sets declared here:
# - evalConfig CFG: the configuration for services.agent-plugins = CFG;
# - activationText CFG: the activation script the module writes for it.
{ self, pkgs }:
let
  inherit (pkgs) lib;
in
rec {
  evalConfig =
    cfg:
    (lib.evalModules {
      modules = [
        self.darwinModules.default
        {
          options = {
            system.activationScripts.postActivation.text = lib.mkOption {
              type = lib.types.lines;
              default = "";
            };
            warnings = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
            assertions = lib.mkOption {
              type = lib.types.listOf lib.types.unspecified;
              default = [ ];
            };
          };
          config = {
            _module.args.pkgs = pkgs;
            services.agent-plugins = cfg;
          };
        }
      ];
    }).config;
  activationText = cfg: (evalConfig cfg).system.activationScripts.postActivation.text;
}
