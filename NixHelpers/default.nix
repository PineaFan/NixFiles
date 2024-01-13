inputs: {
  nginx = import ./nginx.nix inputs;
  nixFilesIn = import ./nixFilesIn.nix inputs;
}
