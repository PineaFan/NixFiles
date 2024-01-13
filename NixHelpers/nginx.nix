{ pkgs, ... }:
let lib = pkgs.lib;
in {
  Host = host: service: {
    inherit host service;
    extraHosts = [ ];
    secure = true;
    type = "hosts";
  };
  Hosts = hosts: service: {
    inherit service;
    host = builtins.elemAt hosts 0;
    extraHosts = builtins.tail hosts;
    secure = true;
    type = "hosts";
  };
  InsecureHost = host: service: {
    inherit host service;
    extraHosts = [ ];
    secure = false;
    type = "hosts";
  };
  InsecureHosts = hosts: service: {
    inherit service;
    host = builtins.elemAt hosts 0;
    extraHosts = builtins.tail hosts;
    secure = false;
    type = "hosts";
  };
  ReverseProxy = to: {
    inherit to;
    type = "reverseproxy";
  };
  PHP = root: socket: {
    inherit root socket;
    type = "php";
  };
  Redirect = to: {
    inherit to;
    permanent = false;
    type = "redirect";
  };
  RedirectPermanent = to: {
    inherit to;
    permanent = true;
    type = "redirect";
  };
  Directory = root: {
    inherit root;
    private = false;
    type = "directory";
  };
  PrivateDirectory = root: {
    inherit root;
    private = true;
    type = "directory";
  };
  File = path: {
    inherit path;
    type = "file";
  };
  Compose = services: {
    inherit services;
    type = "compose";
  };
  Path = path: service: {
    inherit path service;
    type = "path";
  };
  Status = statusCode: {
    inherit statusCode;
    type = "status";
  };
  Header = header: value: service: {
    inherit header value service;
    type = "header";
  };
  CrossOrigin = service: {
    inherit service;
    header = "Access-Control-Allow-Origin";
    value = "*";
    type = "header";
  };

  Merge = let
    # builtins.length and count up
    _iterateCompose = services: currentConfig: currentPath: secure: priority: i:
      if i < builtins.length services then
        _iterateCompose services
        (_merge (builtins.elemAt services i) currentConfig currentPath secure
          (priority + i)) currentPath secure priority (i + 1)
      else
        currentConfig;

    _iterateMerge = i: current: services:
      if i < builtins.length services then
        _iterateMerge (i + 1)
        (current ++ [ (_merge (builtins.elemAt services i) { } "/" true 1000) ])
        services
      else
        current;

    _merge = service: currentConfig: currentPath: secure: priority:
      if service.type == "hosts" then
        _merge service.service (lib.recursiveUpdate currentConfig {
          name = service.host;
          value = {
            serverAliases = service.extraHosts ++ [ "www.${service.host}" ]
              ++ (map (host: "www.${host}") service.extraHosts);

            enableACME = true;
            forceSSL = service.secure;
            addSSL = !service.secure;
            listenAddresses = [ "0.0.0.0" ];
          };
        }) currentPath service.secure priority
      else if service.type == "reverseproxy" then
        (lib.recursiveUpdate currentConfig {
          value.locations.${currentPath} = {
            proxyPass = if currentPath == "/" then
              "http://${service.to}"
            else
              "http://${service.to}/";
            proxyWebsockets = true;
            recommendedProxySettings = true;
          };
        })
      else if service.type == "php" then
        (lib.recursiveUpdate currentConfig {
          value.locations.${currentPath} = {
            root = service.root;
            index = "index.php index.html index.htm";
            tryFiles = "$uri $uri/ ${currentPath}index.php?$query_string =404";
          };
          value.locations."~ ^${currentPath}.*.php$" = {
            tryFiles = "$uri $uri/ ${currentPath}index.php?$query_string =404";
            extraConfig = ''
              include ${pkgs.nginx}/conf/fastcgi_params;
              fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
              fastcgi_param REDIRECT_STATUS 200;
              fastcgi_pass unix:${service.socket};
              fastcgi_intercept_errors on;
              ${lib.optionalString secure "fastcgi_param HTTPS on;"}
            '';
          };
        })
      else if service.type == "redirect" then
        (lib.recursiveUpdate currentConfig {
          value.locations.${currentPath}.return = if service.permanent then
            "308 ${service.to}"
          else
            "307 ${service.to}";
        })
      else if service.type == "directory" then
        (lib.recursiveUpdate currentConfig {
          value.locations.${currentPath} = {
            root = service.root;
            index = "index.html index.htm";
            tryFiles = "$uri $uri/ =404";
            extraConfig = lib.optionalString (!service.private) "autoindex on;";
          };
        })
      else if service.type == "file" then
        (lib.recursiveUpdate currentConfig {
          value.locations.${currentPath} = {
            root = "/";
            tryFiles = "${service.path} =404";
          };
        })
      else if service.type == "path" then
        _merge service.service currentConfig service.path service.secure
        priority
      else if service.type == "header" then
        _merge service.service
          (lib.recursiveUpdate currentConfig {
          value.locations.${currentPath} = {
            extraConfig =
              (if
                builtins.hasAttr "value" currentConfig
                && builtins.hasAttr "locations" currentConfig.value
                && builtins.hasAttr currentPath currentConfig.value.locations
                && builtins.hasAttr "extraConfig" currentConfig.value.locations.${currentPath}
              then currentConfig.value.locations.${currentPath}.extraConfig else "") +
            ''
              add_header ${service.header} "${service.value}";
            '';
          };
        }) currentPath secure priority
      else if service.type == "compose" then
        (_iterateCompose service.services currentConfig currentPath secure
          priority 0)
      else if service.type == "status" then
        (lib.recursiveUpdate currentConfig {
          value.locations.${currentPath} = {
            return = "${builtins.toString service.statusCode}";
          };
        })
      else
        throw "Unknown service type: ${service.type}";
  in (services:
    lib.pipe services [ (_iterateMerge 0 [ ]) builtins.listToAttrs ]);

  # https://www.nginx.com/resources/wiki/start/topics/examples/full/

  /* *
     Internal needs to be a string that is both a host and a port, e.g. generic:1000
     External should only be a port
     Protocol should be TCP or UDP
  */
  ProxyStream = external: internal: protocol: {
    inherit external internal protocol;
    haproxy = true;
  };
  Stream = external: internal: protocol: {
    inherit external internal protocol;
    haproxy = false;
  };

  Alias = host: alias: {
    inherit host;
    aliases = [ alias ];
    type = "aliases";
  };

  Aliases = host: aliases: {
    inherit host aliases;
    type = "aliases";
  };
}

