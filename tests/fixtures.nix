{ pkgs, toon }:

let
  inherit (builtins) concatStringsSep filter length map toJSON;

  cases = builtins.fromJSON (builtins.readFile ./fixtures.json);

  run = c:
    let
      result = builtins.tryEval (toon.toTOON c.options c.input);
    in
    c // {
      ok = result.success && result.value == c.expected;
      got = if result.success then result.value else "<evaluation error>";
    };

  results = map run cases;
  failures = filter (r: !r.ok) results;

  report = concatStringsSep "\n" (map
    (f: "FAIL [${f.file}] ${f.name}\n  expected: ${toJSON f.expected}\n  got:      ${toJSON f.got}")
    failures);
in
pkgs.runCommand "toon-encode-fixtures"
{
  inherit report;
  passAsFile = [ "report" ];
}
  (if failures == [ ]
  then "echo '${toString (length results)} encode fixtures passed' > $out"
  else ''
    cat "$reportPath"
    echo
    echo "${toString (length failures)} of ${toString (length results)} encode fixtures failed"
    exit 1
  '')
