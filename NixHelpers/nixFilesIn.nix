inputs: dir:
let lib = inputs.nixpkgs.lib;
in map (name: dir + "/${name}") (lib.attrNames
  (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name)
    (builtins.readDir dir)))
