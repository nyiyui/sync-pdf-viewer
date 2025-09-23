{
  description = "Synchronized PDF viewer with presenter and viewer clients";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # Package definition
      mkSyncPdfViewer = { lib, buildNpmPackage, bash, nodejs }:
        buildNpmPackage rec {
          pname = "sync-pdf-viewer";
          version = "1.0.0";

          src = ./.;

          npmDepsHash = "sha256-LOzLQ7yj4amcQwGr6HGh9OqQhibDTkAPdr5ANf01sZ8=";

          # Don't run tests during build
          dontNpmBuild = true;

          installPhase = ''
            runHook preInstall
            
            # Copy everything to output
            mkdir -p $out
            cp -r . $out/
            
            # Create bin directory and executable
            mkdir -p $out/bin
            cat > $out/bin/sync-pdf-viewer << EOF
            #!${bash}/bin/bash
            cd $out
            exec ${nodejs}/bin/node server.js "\$@"
            EOF
            chmod +x $out/bin/sync-pdf-viewer
            
            runHook postInstall
          '';

          meta = with lib; {
            description = "Synchronized PDF viewer with presenter and viewer clients";
            homepage = "https://github.com/example/sync-pdf-viewer";
            license = licenses.mit;
            maintainers = [ ];
            platforms = platforms.linux ++ platforms.darwin;
            mainProgram = "sync-pdf-viewer";
          };
        };

      # NixOS Module definition
      nixosModule = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.services.sync-pdf-viewer;
          sync-pdf-viewer = pkgs.callPackage mkSyncPdfViewer { };
        in
        {
          options.services.sync-pdf-viewer = {
            enable = mkEnableOption "Sync PDF Viewer service";

            port = mkOption {
              type = types.int;
              default = 3000;
              description = "Port to run the sync PDF viewer server on";
            };

            host = mkOption {
              type = types.str;
              default = "0.0.0.0";
              description = "Host to bind the server to";
            };

            user = mkOption {
              type = types.str;
              default = "sync-pdf-viewer";
              description = "User to run the service as";
            };

            group = mkOption {
              type = types.str;
              default = "sync-pdf-viewer";
              description = "Group to run the service as";
            };

            dataDir = mkOption {
              type = types.str;
              default = "/var/lib/sync-pdf-viewer";
              description = "Directory to store uploaded PDF files";
            };

            extraEnvironment = mkOption {
              type = types.attrsOf types.str;
              default = { };
              description = "Extra environment variables to set";
              example = {
                NODE_ENV = "production";
              };
            };
          };

          config = mkIf cfg.enable {
            users.users.${cfg.user} = {
              isSystemUser = true;
              group = cfg.group;
              home = cfg.dataDir;
              createHome = true;
            };

            users.groups.${cfg.group} = { };

            systemd.services.sync-pdf-viewer = {
              description = "Sync PDF Viewer Server";
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];

              environment = cfg.extraEnvironment // {
                PORT = toString cfg.port;
                HOST = cfg.host;
                NODE_ENV = cfg.extraEnvironment.NODE_ENV or "production";
              };

              serviceConfig = {
                Type = "simple";
                User = cfg.user;
                Group = cfg.group;
                WorkingDirectory = cfg.dataDir;
                ExecStart = "${sync-pdf-viewer}/bin/sync-pdf-viewer";
                Restart = "always";
                RestartSec = 10;

                # Security settings
                NoNewPrivileges = true;
                PrivateTmp = true;
                ProtectSystem = "strict";
                ProtectHome = true;
                ReadWritePaths = [ cfg.dataDir ];
                ProtectKernelTunables = true;
                ProtectKernelModules = true;
                ProtectControlGroups = true;
                RestrictRealtime = true;
                RestrictSUIDSGID = true;
                RemoveIPC = true;
                PrivateMounts = true;
              };

              preStart = ''
                # Ensure data directory exists and has correct permissions
                mkdir -p ${cfg.dataDir}/uploads
                chown -R ${cfg.user}:${cfg.group} ${cfg.dataDir}
                chmod 755 ${cfg.dataDir}
                chmod 755 ${cfg.dataDir}/uploads
              '';
            };
          };
        };
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        sync-pdf-viewer = pkgs.callPackage mkSyncPdfViewer { };
      in
      {
        packages = {
          default = sync-pdf-viewer;
        };

        apps = {
          default = {
            type = "app";
            program = "${sync-pdf-viewer}/bin/sync-pdf-viewer";
            meta = {
              description = "Synchronized PDF viewer with presenter and viewer clients";
              mainProgram = "sync-pdf-viewer";
            };
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nodejs
            nodePackages.npm
          ];
        };
      }
    ) // {
      nixosModules = {
        default = nixosModule;
        sync-pdf-viewer = nixosModule;
      };

      # Overlay for adding the package to nixpkgs
      overlays.default = final: prev: {
        sync-pdf-viewer = final.callPackage mkSyncPdfViewer { };
      };

    };
}
