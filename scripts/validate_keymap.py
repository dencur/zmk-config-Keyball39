#!/usr/bin/env python3
"""Pre-flight checks for config/keyball39.keymap.

Run before pushing a keymap change:

    python3 scripts/validate_keymap.py

Everything here is a failure mode that has actually bitten this repo, not a
style checker. Exits non-zero on the first category that fails, and prints
every offender rather than just the first.

Checks
  1. Every layer binds exactly 39 positions. A miscount is the single most
     common keymap error and ZMK's own message for it is unhelpful.
  2. Layer DECLARATION ORDER matches the #define indices. ZMK numbers layers
     by their order in the keymap node, NOT by the name you #define, so a
     layer inserted in the wrong place silently renumbers everything above it.
  3. BEN_SCRL is identical in the keymap and in keyball39_right.overlay. The
     overlay is preprocessed without visibility of the keymap's defines, so
     the number is necessarily duplicated; drift means the trackball's
     scroll-layers points at the wrong layer.
  4. Combo key-positions are inside 0..38 and every combo is layer-gated. An
     out-of-range position is an unchecked write in ZMK's combo table.
  5. No &trans on layers entered with &to. &to deactivates the layer beneath,
     so &trans there falls all the way through to the base layer instead of
     the profile you think is underneath.
  6. The Ben profile's two alpha layers cover the alphabet exactly once.
  7. Every Ben layer has an exit at position 38.
"""
import io, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEYMAP = os.path.join(ROOT, "config", "keyball39.keymap")
OVERLAY = os.path.join(ROOT, "config", "boards", "shields", "keyball_nano",
                       "keyball39_right.overlay")
NKEYS = 39

src = io.open(KEYMAP, encoding="utf-8").read()
km = src[src.index("keymap {"):]
defines = {k: int(v) for k, v in
           re.findall(r'^#define\s+([A-Z_0-9]+)\s+(\d+)\s*(?://.*)?$', src, re.M)}
layers = re.findall(r'^\s{8}([a-z_0-9]+)\s*\{.*?bindings = <(.*?)>;', km, re.S | re.M)
order = [n for n, _ in layers]
fails = []


def check(title, bad, fmt=str):
    print(("  %-46s " % title) + ("ok" if not bad else "FAIL"))
    for b in bad:
        print("      " + fmt(b))
    if bad:
        fails.append(title)


print("keymap: %s" % os.path.relpath(KEYMAP, ROOT))
print("  %d layers, %d defines\n" % (len(layers), len(defines)))

# 1 ─ binding counts
check("every layer binds exactly %d positions" % NKEYS,
      [(n, len(re.findall(r'&\w+', b))) for n, b in layers
       if len(re.findall(r'&\w+', b)) != NKEYS],
      lambda x: "%s has %d" % x)

# 2 ─ declaration order vs #define
mismatch = []
for name, idx in sorted(defines.items(), key=lambda kv: kv[1]):
    if idx >= len(order):
        continue
    node = order[idx]
    stem = name.lower().replace("_", "")
    alias = node.replace("_layer", "").replace("_", "")
    if stem.startswith("zmk") or name.startswith("CONFIG"):
        continue
    if stem[:3] != alias[:3] and not (stem == "default" and alias == "default"):
        mismatch.append((name, idx, node))
check("layer order matches #define indices",
      mismatch, lambda x: "#define %s = %d but slot %d is '%s'" % (x[0], x[1], x[1], x[2]))

# 3 ─ BEN_SCRL duplicated define
ov = io.open(OVERLAY, encoding="utf-8").read()
m = re.search(r'#define\s+BEN_SCRL\s+(\d+)', ov)
bad = []
if "BEN_SCRL" in defines:
    if not m:
        bad = ["keymap defines BEN_SCRL=%d but the overlay does not" % defines["BEN_SCRL"]]
    elif int(m.group(1)) != defines["BEN_SCRL"]:
        bad = ["keymap=%d overlay=%d" % (defines["BEN_SCRL"], int(m.group(1)))]
    else:
        sl = re.search(r'scroll-layers = <([^>]*)>', ov)
        if sl and "BEN_SCRL" not in sl.group(1):
            bad = ["BEN_SCRL missing from scroll-layers = <%s>" % sl.group(1)]
check("BEN_SCRL in sync: keymap <-> right overlay", bad)

# 4 ─ combos
bad = []
for m in re.finditer(r'^\s{8}(\w+)\s*\{(.*?)^\s{8}\};', src, re.S | re.M):
    name, body = m.group(1), m.group(2)
    kp = re.search(r'key-positions = <([^>]*)>', body)
    if not kp:
        continue
    pos = [int(x) for x in kp.group(1).split()]
    out = [p for p in pos if not 0 <= p < NKEYS]
    if out:
        bad.append("%s: positions out of range %s" % (name, out))
    if not re.search(r'layers = <', body):
        bad.append("%s: no layers gate (fires on EVERY layer)" % name)
check("combos in range and layer-gated", bad)

# 5 ─ &trans on &to-entered layers
to_entered = set()
for name, body in layers:
    for m in re.finditer(r'&to\s+([A-Z_0-9]+)', body):
        if m.group(1) in defines:
            idx = defines[m.group(1)]
            if idx < len(order):
                to_entered.add(order[idx])
for m in re.finditer(r'bindings = <&to ([A-Z_0-9]+)>', src):
    if m.group(1) in defines and defines[m.group(1)] < len(order):
        to_entered.add(order[defines[m.group(1)]])
to_entered.discard(order[0])
bad = [(n, b.count("&trans")) for n, b in layers if n in to_entered and "&trans" in b]
check("no &trans on &to-entered layers",
      bad, lambda x: "%s has %d &trans (leaks to the base layer)" % x)

# 6 & 7 ─ Ben profile specifics
if "BEN" in defines:
    body = dict(layers)
    a1 = set(re.findall(r'&ben_h[ml]_[lr] \S+ ([A-Z])\b', body.get("ben_layer", "")))
    a2 = set(re.findall(r'&kp ([A-Z])\b', body.get("ben_a2_layer", "")))
    alpha = set("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    bad = []
    if a1 & a2:
        bad.append("on BOTH alpha layers: %s" % "".join(sorted(a1 & a2)))
    if alpha - a1 - a2:
        bad.append("missing entirely: %s" % "".join(sorted(alpha - a1 - a2)))
    check("Ben alpha1+alpha2 cover A-Z exactly once", bad)

    bad = []
    for n, b in layers:
        if not n.startswith("ben"):
            continue
        toks = re.findall(r'&\w+(?:\s+[A-Za-z_0-9()]+)*', b)
        if len(toks) == NKEYS and not toks[38].strip().startswith("&to DEFAULT"):
            bad.append("%s: position 38 is '%s', not an exit" % (n, toks[38].strip()))
    check("every Ben layer exits at position 38", bad)

print()
if fails:
    print("FAILED: %s" % ", ".join(fails))
    sys.exit(1)
print("all pre-flight checks pass")
