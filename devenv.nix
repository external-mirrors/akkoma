{ pkgs, lib, config, inputs, ... }:

{
  env.GREET = "devenv";

  packages = [
    pkgs.git
    pkgs.imagemagick
    pkgs.coreutils
    pkgs.libossp_uuid
    pkgs.file
    pkgs.cmake
    pkgs.exiftool
    pkgs.ffmpeg
  ];
  languages = {
    elixir = {
      enable = true;
      lsp = {
        enable = true;
      };
    };
  };

  services.postgres = {
    enable = true;
    listen_addresses = "0.0.0.0";
    extensions = extensions: [];

    initialDatabases = [
      {
        name = "akkoma_dev";
        user = "akkoma";
      }
      {
        name = "akkoma_test";
        user = "akkoma";
      }
    ];

    initialScript = ''
      CREATE ROLE IF NOT EXISTS akkoma WITH SUPERUSER;
      ALTER ROLE akkoma WITH PASSWORD 'akkoma';
      CREATE EXTENSION IF NOT EXISTS citext;
      CREATE EXTENSION IF NOT EXISTS pg_trgm;
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    '';
  };
}
