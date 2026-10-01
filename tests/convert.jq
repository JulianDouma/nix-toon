[ .[] as $f | $f.tests[] | {
  file: $f.description,
  name,
  expected,
  options: (.options // {}),
  input: (.input | walk(
    if type == "object"
    then { _type: "toon-ordered", entries: (to_entries | map({ name: .key, value })) }
    else . end))
} ]
