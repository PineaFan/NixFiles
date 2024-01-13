{
  description = "Clicks helpers for writing boilerplatey nix";

  outputs = { self, nixpkgs }: { helpers = import ./default.nix; };
}
