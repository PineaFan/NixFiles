{ pkgs, helpers, config, lib, ... }: {
  clicks.nginx.services = with helpers.nginx; [
    (Host "dev.clicks.cards" (ReverseProxy "generic:3001"))
  ];
}
