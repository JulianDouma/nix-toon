let
  inherit (builtins)
    all
    attrNames
    concatMap
    concatStringsSep
    elem
    elemAt
    fromJSON
    genList
    head
    isBool
    isFloat
    isFunction
    isInt
    isList
    isPath
    isString
    length
    lessThan
    listToAttrs
    match
    replaceStrings
    sort
    stringLength
    substring
    tail
    toJSON
    ;

  repeat = n: s: concatStringsSep "" (genList (_: s) n);

  hexDigits = "0123456789abcdef";
  hex2 = i: substring (i / 16) 1 hexDigits + substring (i - 16 * (i / 16)) 1 hexDigits;

  controlCodes = genList (i: i + 1) 31;
  controls = map (i: fromJSON ''"\u00${hex2 i}"'') controlCodes;
  escapeControl = i:
    if i == 9 then "\\t"
    else if i == 10 then "\\n"
    else if i == 13 then "\\r"
    else "\\u00${hex2 i}";

  escape = replaceStrings
    ([ "\\" "\"" ] ++ controls)
    ([ "\\\\" "\\\"" ] ++ map escapeControl controlCodes);

  contains = needles: s: replaceStrings needles (map (_: "") needles) s != s;

  quoteTriggers = [ ":" "\"" "\\" "[" "]" "{" "}" ] ++ controls;

  parseInt = s:
    let
      m = match "([+-]?)0*([0-9]+)" s;
      v = fromJSON (elemAt m 1);
    in
    if elemAt m 0 == "-" then -v else v;

  formatFloat = f:
    let
      m = match "(-?)([0-9]+)(\\.([0-9]+))?([eE]([+-]?[0-9]+))?" (toJSON f);
      negative = elemAt m 0 == "-";
      intPart = elemAt m 1;
      fracPart = if elemAt m 3 == null then "" else elemAt m 3;
      exponent = if elemAt m 5 == null then 0 else parseInt (elemAt m 5);
      raw = intPart + fracPart;
      leadingZeros = stringLength (head (match "(0*).*" raw));
      significant = head (match "(.*[^0])?0*" (substring leadingZeros (stringLength raw) raw));
      digits = if significant == null then "" else significant;
      count = stringLength digits;
      point = stringLength intPart + exponent - leadingZeros;
      plain =
        if point <= 0 then "0." + repeat (-point) "0" + digits
        else if point >= count then digits + repeat (point - count) "0"
        else substring 0 point digits + "." + substring point count digits;
      e = point - 1;
      scientific =
        substring 0 1 digits
        + (if count > 1 then "." + substring 1 count digits else "")
        + "e" + (if e < 0 then "-" + toString (-e) else "+" + toString e);
    in
    if m == null then "null"
    else if digits == "" then "0"
    else (if negative then "-" else "") + (if point >= -5 && point <= 21 then plain else scientific);

  mkObject = entries: {
    kind = "object";
    inherit entries;
    attrs = listToAttrs entries;
    names = sort lessThan (map (e: e.name) entries);
  };

  normalize = v:
    if v == null then { kind = "null"; }
    else if isBool v then { kind = "bool"; value = v; }
    else if isInt v then { kind = "number"; text = toString v; }
    else if isFloat v then { kind = "number"; text = formatFloat v; }
    else if isString v then { kind = "string"; value = v; }
    else if isPath v then { kind = "string"; value = toString v; }
    else if isList v then { kind = "array"; items = map normalize v; }
    else if isFunction v then throw "toTOON: functions have no TOON representation"
    else if (v._type or null) == "toon-ordered" then mkObject (map (e: { inherit (e) name; value = normalize e.value; }) v.entries)
    else if v ? __toString then { kind = "string"; value = toString v; }
    else if v ? outPath then { kind = "string"; value = toString v.outPath; }
    else mkObject (map (name: { inherit name; value = normalize v.${name}; }) (attrNames v));

  isPrimitive = n: elem n.kind [ "null" "bool" "number" "string" ];
  isFilledObject = n: n.kind == "object" && n.entries != [ ];

  fieldSpec = objects:
    let
      first = head objects;
      fields = map
        (e:
          let
            column = map (o: o.attrs.${e.name}) objects;
            children = fieldSpec column;
          in
          if all isPrimitive column then { inherit (e) name; }
          else if children == null then null
          else { inherit (e) name; inherit children; })
        first.entries;
    in
    if !(all isFilledObject objects) || !(all (o: o.names == first.names) objects) || elem null fields
    then null
    else fields;

  encode = { indentSize ? 2, delimiter ? "," }:
    let
      d = delimiter;
      dsym = if d == "," then "" else d;
      pad = depth: repeat (depth * indentSize) " ";

      quoteString = s:
        let
          first = substring 0 1 s;
          last = substring (stringLength s - 1) 1 s;
        in
        if s == ""
          || elem first [ " " "\t" "-" "#" ]
          || elem last [ " " "\t" ]
          || elem s [ "true" "false" "null" ]
          || match "[+-]?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?" s != null
          || contains (quoteTriggers ++ [ d ]) s
        then "\"${escape s}\""
        else s;

      key = k: if match "[A-Za-z_][A-Za-z0-9_.]*" k != null then k else "\"${escape k}\"";

      primitive = n:
        if n.kind == "null" then "null"
        else if n.kind == "bool" then (if n.value then "true" else "false")
        else if n.kind == "number" then n.text
        else quoteString n.value;

      fieldList = spec: concatStringsSep d (map
        (f: key f.name + (if f ? children then "{${fieldList f.children}}" else ""))
        spec);

      cells = spec: o: concatMap
        (f: if f ? children then cells f.children o.attrs.${f.name} else [ o.attrs.${f.name} ])
        spec;

      row = spec: o: concatStringsSep d (map primitive (cells spec o));

      inline = items: concatStringsSep d (map primitive items);

      keyedSpec = o: if length o.entries < 2 then null else fieldSpec (map (e: e.value) o.entries);

      keyed = depth: k: spec: o:
        [ "${pad depth}${k}[${toString (length o.entries)}:${dsym}]{${fieldList spec}}:" ]
        ++ map (e: "${pad (depth + 1)}${key e.name}: ${row spec e.value}") o.entries;

      array = depth: k: a:
        let
          header = "${pad depth}${k}[${toString (length a.items)}${dsym}]";
          spec = fieldSpec a.items;
        in
        if all isPrimitive a.items then [ "${header}: ${inline a.items}" ]
        else if spec != null then [ "${header}{${fieldList spec}}:" ] ++ map (o: "${pad (depth + 1)}${row spec o}") a.items
        else [ "${header}:" ] ++ concatMap (listItem (depth + 1)) a.items;

      field = depth: k: n:
        let
          spec = keyedSpec n;
        in
        if isPrimitive n then [ "${pad depth}${k}: ${primitive n}" ]
        else if n.kind == "array" then (if n.items == [ ] then [ "${pad depth}${k}: []" ] else array depth k n)
        else if n.entries == [ ] then [ "${pad depth}${k}:" ]
        else if spec != null then keyed depth k spec n
        else [ "${pad depth}${k}:" ] ++ fields (depth + 1) n;

      fields = depth: o: concatMap (e: field depth (key e.name) e.value) o.entries;

      listItem = depth: n:
        let
          header = "${pad depth}- [${toString (length n.items)}${dsym}]:";
          first = head n.entries;
          firstLines = field (depth + 1) (key first.name) first.value;
          carried = substring ((depth + 1) * indentSize) (stringLength (head firstLines)) (head firstLines);
        in
        if isPrimitive n then [ "${pad depth}- ${primitive n}" ]
        else if n.kind == "array" then
          if n.items == [ ] then [ header ]
          else if all isPrimitive n.items then [ "${header} ${inline n.items}" ]
          else [ header ] ++ concatMap (listItem (depth + 1)) n.items
        else if n.entries == [ ] then [ "${pad depth}-" ]
        else [ "${pad depth}- ${carried}" ] ++ tail firstLines ++ concatMap (e: field (depth + 1) (key e.name) e.value) (tail n.entries);

      root = n:
        let
          spec = keyedSpec n;
        in
        if isPrimitive n then [ (primitive n) ]
        else if n.kind == "array" then (if n.items == [ ] then [ "[]" ] else array 0 "" n)
        else if spec != null then keyed 0 "" spec n
        else fields 0 n;
    in
    value: concatStringsSep "\n" (root (normalize value));
in
{
  toTOON = encode;

  ordered = entries: { _type = "toon-ordered"; inherit entries; };

  withKeyOrder = names: attrs: {
    _type = "toon-ordered";
    entries = map (name: { inherit name; value = attrs.${name}; }) names;
  };
}
