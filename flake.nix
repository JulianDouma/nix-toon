{
  description = "TOON (Token-Oriented Object Notation) encoder in pure Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    toon-spec = {
      url = "github:toon-format/spec/v4.1.1";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, toon-spec }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      convertFixtures = pkgs: "${pkgs.jq}/bin/jq -s -f ${./tests/convert.jq} ${toon-spec}/tests/fixtures/encode/*.json";
    in
    {
      lib = import ./lib.nix;

      checks = forAllSystems (pkgs: {
        fixtures = import ./tests/fixtures.nix { inherit pkgs; toon = self.lib; };
        fixtures-fresh = pkgs.runCommand "toon-fixtures-fresh" { } ''
          ${convertFixtures pkgs} > generated.json
          diff -u ${./tests/fixtures.json} generated.json
          touch $out
        '';
        nix = import ./tests/nix.nix { inherit pkgs; toon = self.lib; };
      });

      apps = forAllSystems (pkgs: {
        update-fixtures = {
          type = "app";
          program = "${pkgs.writeShellScript "update-fixtures" "${convertFixtures pkgs} > tests/fixtures.json"}";
          meta.description = "Regenerate tests/fixtures.json from the pinned TOON spec";
        };
      });

      formatter = forAllSystems (pkgs: pkgs.writeShellScriptBin "nixpkgs-fmt" ''
        exec ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt "''${@:-.}"
      '');
    };
}
