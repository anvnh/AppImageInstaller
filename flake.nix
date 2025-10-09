{
  description = "LinuxUtils runnable on NixOS without system deps";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs";

  outputs = { self, nixpkgs }:
  let
    forAll = f: nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ]
      (system: f (import nixpkgs { inherit system; }));
    deps = pkgs: with pkgs; [
      bash coreutils gnugrep gnused gawk findutils
      curl wget git jq yq-go
      desktop-file-utils shared-mime-info imagemagick libarchive
      fzf gtk3 kdePackages.kservice
      xorg.xprop xorg.xrandr
      fuse appimage-run # hỗ trợ AppImage
    ];
  in {
    packages = forAll (pkgs: {
      lutils = pkgs.writeShellApplication {
        name = "lutils";
        runtimeInputs = deps pkgs;
        # Script đã dùng ${BASH_SOURCE[0]} nên tìm đúng subdir khi đóng gói.
        text = builtins.readFile ./lutils.sh;
      };
    });

    apps = forAll (pkgs: {
      default = {
        type = "app";
        program = "${self.packages.${pkgs.system}.lutils}/bin/lutils";
      };
      lutils = {
        type = "app";
        program = "${self.packages.${pkgs.system}.lutils}/bin/lutils";
      };
    });

    devShells = forAll (pkgs: {
      default = pkgs.mkShell { buildInputs = deps pkgs; };
    });
  };
};
