{
  description = "liminade - A Limine-Compatible UEFI Bootloader in Ada";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    inputs:
    let
      genSystems = func: builtins.mapAttrs func inputs.nixpkgs.legacyPackages;
    in
    {
      formatter = genSystems (system: pkgs: pkgs.nixfmt-tree);

      packages = genSystems (
        system: pkgs: rec {
          liminade = pkgs.stdenv.mkDerivation {
            name = "liminade";
            src = ./.;

            nativeBuildInputs = with pkgs; [
              binutils
              gnat
              python3
            ];

            #  Never let the stdenv fixup phase strip the image: `strip` treats
            #  the PE32+ UEFI application as a PE object and rewrites its
            #  headers, producing an image the firmware refuses to load.
            dontStrip = true;
            dontPatchELF = true;

            #  build.sh drives the whole pipeline: GNAT -> freestanding ELF64
            #  -> PE32+ UEFI application (tools/elf2pe.py).
            buildPhase = ''
              runHook preBuild
              patchShebangs build.sh run-qemu.sh
              ./build.sh
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin
              cp build/liminade.efi $out/bin/
              runHook postInstall
            '';
          };
          default = liminade;
        }
      );

      devShells = genSystems (
        system: pkgs: {
          default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              dosfstools
              efitools
              file
              gdb
              mtools
              opencode
              python3
              qemu
            ];
            buildInputs = with pkgs; [
              gnat
              libelf
              binutils
            ];
            shellHook = ''
              export __fish_machine='(dev:liminade)'
              export SHELL="${pkgs.fish}/bin/fish"
              exec "$SHELL"
            '';
          };
        }
      );
    };
}
