{
  description = "Copyright Skyler Grey 2023";

  inputs.helpers.url = "git+https://git.clicks.codes/Clicks/NixHelpers";
  outputs = { self, nixpkgs, ... }@inputs: 
  let helpers = inputs.helpers.helpers {inherit nixpkgs; }; in rec {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
      ]++(helpers.nixFilesIn ./Modules);
    };
  };
}
