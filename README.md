# nix-toon

A [TOON](https://github.com/toon-format/toon) (Token-Oriented Object Notation) encoder written in pure Nix, with no dependency on nixpkgs.

TOON encodes the JSON data model compactly for LLM prompts. This library turns any Nix value into TOON, so a flake can hand structured data to an agent without going through JSON.

- Targets **TOON spec v4.1** (`toon-spec: 4.1`).
- Passes all **179 encode fixtures** of the official [spec test suite](https://github.com/toon-format/spec/tree/main/tests), pinned at `v4.1.1`.
- Encode only. Nix generates data; it has no use for a TOON decoder.

## Usage

```nix
{
  inputs.nix-toon.url = "github:JulianDouma/nix-toon";

  outputs = { nix-toon, ... }:
    let
      inherit (nix-toon.lib) toTOON;
    in
    {
      example = toTOON { } {
        users = [
          { id = 1; name = "Alice"; }
          { id = 2; name = "Bob"; }
        ];
      };
    };
}
```

```
users[2]{id,name}:
  1,Alice
  2,Bob
```

`nix-toon` has a `nixpkgs` input for its own checks only. Consumers can set `inputs.nix-toon.inputs.nixpkgs.follows = "nixpkgs";` to avoid fetching a second copy.

### Options

`toTOON { indentSize ? 2, delimiter ? "," } value`

- `indentSize`: spaces per indentation level.
- `delimiter`: `","`, `"\t"` or `"|"`. Used for every header, inline array, tabular row and keyed entry row.

## Key order

TOON preserves object key order, but Nix attribute sets have none: they are always sorted by name. A plain attrset therefore encodes with its keys in sorted order. That output is valid and deterministic.

When order matters, build the object explicitly:

```nix
toTOON { } (nix-toon.lib.ordered [
  { name = "b"; value = 1; }
  { name = "a"; value = 2; }
])
# b: 1
# a: 2
```

`withKeyOrder` is a shortcut for the common tabular case, where the first row decides the header's field order:

```nix
toTOON { } {
  hosts = map (nix-toon.lib.withKeyOrder [ "name" "features" ]) rows;
}
```

## Mapping of Nix values

| Nix value | TOON |
|---|---|
| `null`, booleans | `null`, `true`, `false` |
| integers | decimal |
| floats | canonical decimal per spec §2 (`1.0` becomes `1`, `-0.0` becomes `0`, exponent form below `1e-6` and from `1e21`) |
| strings | quoted and escaped only where spec §7.2 requires it |
| paths | the path as a string; nothing is copied to the store |
| lists | inline, tabular or list form, chosen from the shape per spec §9 |
| attrsets | objects, keys sorted (see above) |
| attrsets with `__toString` | that string |
| derivations and other attrsets with `outPath` | the `outPath` string |
| functions | evaluation error |

Nix strings cannot contain U+0000, so that code point never reaches the encoder.

## Development

```bash
nix flake check
```

Runs three checks:

- `fixtures`: the official encode fixtures from `tests/fixtures.json`.
- `fixtures-fresh`: regenerates that file from the pinned spec and fails if it differs.
- `nix`: the Nix-specific mapping tests.

`tests/fixtures.json` is the spec's encode fixtures with every object rewritten into ordered form (`tests/convert.jq`), because `builtins.fromJSON` would sort the keys. It is committed so that evaluation needs no import-from-derivation. After bumping the `toon-spec` input:

```bash
nix run .#update-fixtures
```

## License

MIT
