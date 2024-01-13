{ config, lib, pkgs, helpers, base, ... }:
lib.recursiveUpdate {
  options.clicks = {
    nginx = {
      services = lib.mkOption {
        type = with lib.types;
          listOf (submodule {
            options = {
              host = lib.mkOption { type = str; };
              extraHosts = lib.mkOption { type = listOf str; };
              secure = lib.mkOption { type = bool; };
              service = lib.mkOption {
                type = let
                  validServiceTypes = {
                    "redirect" = {
                      to = [ "string" str ];
                      permanent = [ "bool" bool ];
                    };
                    "reverseproxy" = { to = [ "string" str ]; };
                    "php" = {
                      root = [ "string" str ];
                      socket = [ "string" str ];
                    };
                    "directory" = {
                      private = [ "bool" bool ];
                      root = [ "string" str ];
                    };
                    "file" = { path = [ "string" str ]; };
                    "path" = {
                      path = [ "string" str ];
                      service = [ "set" serviceType ];
                    };
                    "compose" = { services = [ "list" (listOf serviceType) ]; };
                    "status" = { statusCode = [ "int" int ]; };
                  };

                  serviceType = mkOptionType {
                    name = "Service";

                    description = "clicks Nginx service";
                    descriptionClass = "noun";

                    check = (x:
                      if (builtins.typeOf x) != "set" then
                        lib.warn
                        "clicks nginx services must be sets but ${x} is not a set"
                        false
                      else if !(builtins.hasAttr "type" x) then
                        lib.warn
                        "clicks nginx services must have a type attribute but ${x} does not"
                        false
                      else if !(builtins.hasAttr x.type validServiceTypes) then
                        lib.warn
                        "clicks nginx services must have a valid type, but ${x.type} is not one"
                        false
                      else
                        (let
                          optionTypes =
                            (builtins.mapAttrs (n: o: builtins.elemAt o 0)
                              validServiceTypes.${x.type}) // {
                                type = "string";
                              };
                        in (lib.pipe x [
                          (builtins.mapAttrs (n: o:
                            (builtins.hasAttr n optionTypes) && optionTypes.${n}
                            == (builtins.typeOf o)))
                          lib.attrValues
                          (builtins.all (x: x))
                        ]) && (lib.pipe optionTypes [
                          (builtins.mapAttrs (n: _: builtins.hasAttr n x))
                          lib.attrValues
                          (builtins.all (x: x))
                        ])));
                  };
                in serviceType;
              };
              type = lib.mkOption { type = strMatching "hosts"; };
            };
          });
        example = lib.literalExpression ''
          with helpers.nginx; [
            (Host "example.clicks.codes" (ReverseProxy "generic:1001"))
          ]'';
        description = lib.mdDoc ''
          Connects hostnames to services for your nginx server. We recommend using the Clicks helper to generate these
        '';
        default = [ ];
      };
      serviceAliases = lib.mkOption {
        type = with lib.types;
          listOf (submodule {
            options = {
              host = lib.mkOption {
                type = str;
                example = "example.clicks.codes";
                description = ''
                  The ServerName of the server. If you override this in the nginx server block, you still need to put in the name of the attribute
                '';
              };
              aliases = lib.mkOption {
                type = listOf str;
                example = [ "example2.clicks.codes" "example.coded.codes" ];
                description = ''
                  A list of servers to add as aliases
                '';
              };
              type = lib.mkOption { type = strMatching "aliases"; };
            };
          });
        example = lib.literalExpression ''
          with helpers.nginx; [
            (Host "example.clicks.codes" (ReverseProxy "generic:1001"))
          ]'';
        description = lib.mdDoc ''
          Adds additional host names to your nginx server. If you're using `clicks.nginx.services`
          you should generally use a Hosts block instead
        '';
        default = [ ];
      };
      streams = lib.mkOption {
        type = with lib.types;
          listOf (submodule {
            options = {
              internal = lib.mkOption { type = str; };
              external = lib.mkOption { type = port; };
              protocol = lib.mkOption { type = strMatching "^(tcp|udp)$"; };
              haproxy = lib.mkOption { type = bool; };
            };
          });
        example = lib.literalExpression ''
          with helpers.nginx; [
            (Stream 1001 "generic:1002" "tcp")
          ]'';
        description = lib.mdDoc ''
          A list of servers to be placed in the nginx streams block. We recommend using the Clicks helper to generate these
        '';
        default = [ ];
      };
    };
  };
  config = {
    services.nginx = {
      enable = true;
      enableReload = true;

      serverNamesHashMaxSize = 4096;

      virtualHosts = lib.recursiveUpdate (helpers.nginx.Merge
        config.clicks.nginx.services) # clicks.nginx.services
        (lib.pipe config.clicks.nginx.serviceAliases [
          (map (alias: {
            name = alias.host;
            value.serverAliases = alias.aliases;
          }))
          builtins.listToAttrs
        ]); # clicks.nginx.serviceAliases

      streamConfig = builtins.concatStringsSep "\n" (map (stream: ''
        server {
            listen ${builtins.toString stream.external}${
              lib.optionalString (stream.protocol == "udp") " udp"
            };
            proxy_pass ${stream.internal};
            ${if stream.haproxy then "proxy_protocol on;" else ""}
        }
      '') config.clicks.nginx.streams);
    };

    networking.firewall.allowedTCPPorts = lib.pipe config.clicks.nginx.streams [
      (builtins.filter (stream: stream.protocol == "tcp"))
      (map (stream: stream.external))
    ];
    networking.firewall.allowedUDPPorts = lib.pipe config.clicks.nginx.streams [
      (builtins.filter (stream: stream.protocol == "udp"))
      (map (stream: stream.external))
    ];

    security.acme.defaults = {
      email = "admin@clicks.codes";
      environmentFile = config.sops.secrets.cloudflare_cert__api_token.path;
    };
    security.acme.acceptTerms = true;

    sops.secrets.cloudflare_cert__api_token = {
      mode = "0660";
      owner = config.users.users.nginx.name;
      group = config.users.users.acme.group;
      sopsFile = ../../secrets/cloudflare-cert.env.bin;
      format = "binary";
    };

    users.users.nginx.extraGroups = [ config.users.users.acme.group ];
  };
} (if base != null then {
  config.security.acme.certs = lib.mkForce (builtins.mapAttrs (_: v:
    (lib.filterAttrs (n: _: n != "directory" && n != "credentialsFile") v) // {
      webroot = null;
      dnsProvider = "cloudflare";
    }) base.config.security.acme.certs);
} else
  { })
