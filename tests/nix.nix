{ pkgs, toon }:

let
  inherit (toon) toTOON ordered withKeyOrder;
  enc = toTOON { };

  cases = [
    { name = "plain attrsets emit keys sorted"; got = enc { b = 1; a = 2; }; expected = "a: 2\nb: 1"; }
    { name = "ordered keeps the given order"; got = enc (ordered [{ name = "b"; value = 1; } { name = "a"; value = 2; }]); expected = "b: 1\na: 2"; }
    { name = "withKeyOrder sets tabular field order"; got = enc { rows = map (withKeyOrder [ "name" "id" ]) [{ id = 1; name = "x"; }]; }; expected = "rows[1]{name,id}:\n  x,1"; }
    { name = "integer-valued float drops the fraction"; got = enc 1.0; expected = "1"; }
    { name = "negative zero float becomes 0"; got = enc (-0.0); expected = "0"; }
    { name = "float at 1e21 uses exponent form"; got = enc (builtins.fromJSON "1e21"); expected = "1e+21"; }
    { name = "float below 1e-6 uses exponent form"; got = enc (builtins.fromJSON "1.5e-7"); expected = "1.5e-7"; }
    { name = "float at 1e-6 stays decimal"; got = enc (builtins.fromJSON "1e-6"); expected = "0.000001"; }
    { name = "large float stays decimal"; got = enc (builtins.fromJSON "1.25e20"); expected = "125000000000000000000"; }
    { name = "paths become their string without a store copy"; got = enc { p = /tmp/x; }; expected = "p: /tmp/x"; }
    { name = "derivations become their outPath"; got = enc { d = pkgs.hello; }; expected = "d: ${pkgs.hello}"; }
    { name = "__toString is honoured"; got = enc { s = { __toString = _: "hi"; }; }; expected = "s: hi"; }
    { name = "control characters are escaped"; got = enc { s = "a\tb\nc"; }; expected = ''s: "a\tb\nc"''; }
  ];

  failures = builtins.filter (c: c.got != c.expected) cases;
  functionFails = !(builtins.tryEval (enc { f = x: x; })).success;
in
assert builtins.length failures == 0 || throw (builtins.concatStringsSep "\n" (map (c: "FAIL ${c.name}: expected ${builtins.toJSON c.expected}, got ${builtins.toJSON c.got}") failures));
assert functionFails || throw "FAIL functions should throw";
pkgs.runCommand "toon-nix-specific" { } "echo '${toString (builtins.length cases + 1)} Nix-specific tests passed' > $out"
