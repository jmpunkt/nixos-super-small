{
  description = "Minimal read-only squashfs images";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.zst";
  };

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      mkImage =
        {
          extraModules ? [ ],
        }:
        import (nixpkgs + "/nixos/lib/eval-config.nix") {
          inherit system;
          modules = [
            ({ ... }: {
              nixpkgs.buildPlatform = system;
            })
            ./modules
            ./boards/rpi2/default.nix
          ]
          ++ extraModules;
        };

      pkgs = import nixpkgs { inherit system; };

      rpi2Pkgs = import nixpkgs {
        localSystem = system;
        crossSystem = {
          config = "armv7l-unknown-linux-gnueabihf";
        };
      };

      image = mkImage { };
    in
    {
      packages."${system}" = {
        rpi2-sd-card = image.config.system.build.images.sd-card;
        rpi2-swu = image.config.system.build.images.swu;
      };
    };
}
