{
  description = "dimgui development shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      forEachSystem = function: nixpkgs.lib.genAttrs systems
        (system: function nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forEachSystem (pkgs:
        let
          # bindbc loads these with dlopen at runtime, so they must be on the library path.
          # OpenGL comes from nixGL on Linux and from the system framework on macOS.
          runtimeLibraries = [ pkgs.glfw ] ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.libx11;
          libraryPathVariable = if pkgs.stdenv.hostPlatform.isDarwin then "DYLD_LIBRARY_PATH" else "LD_LIBRARY_PATH";
        in
        {
          default = pkgs.mkShell {
            packages = [ pkgs.dub pkgs.ldc ] ++ runtimeLibraries;
            ${libraryPathVariable} = pkgs.lib.makeLibraryPath runtimeLibraries;
          };
        });
    };
}
