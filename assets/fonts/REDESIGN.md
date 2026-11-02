# Redesign fonts

The mockup uses Space Grotesk for interface text and JetBrains Mono for data.
Its CSS requests weights 400, 500, 600 and 700, including inherited bold text.
Both families are bundled with the wallet. Space Grotesk lacked a declared
600 face; the new SemiBold fills that weight.

## Space Grotesk SemiBold

- Source: the Space Grotesk `@font-face` in `mockups/home/index.html`.
- Input: the embedded WOFF2, Space Grotesk 2.000, weight axis 300 to 700.
- Input SHA-256: `0640890476fc1198ab4de571fb658de443c4d85b66466ec09534a8737ab1ce9d`.
- Coordinate: `wght=600`.
- Output: `assets/fonts/SpaceGrotesk-SemiBold.ttf`.
- Output SHA-256: `a3722af6513254c9bc8a745236f85d6e4df4082fb804f5afec05a4332aea854c`.
- Converter: fontTools 4.67.0; Brotli 1.2.0.
- Tool: `tool/redesign_fonts.py`.

The redesign page inlines the same WOFF2 bytes. The converter pins that input
hash, fixes the weight, writes an unwrapped static TrueType font and retains
the source's creation and modification timestamps. It preserves the source
copyright and license URL and records OFL 1.1 in the font's name table.

The typographic family is Space Grotesk and the style is SemiBold. The legacy
family is Space Grotesk SemiBold with Regular style, following the bundled
Medium face's naming convention. The PostScript name is
`SpaceGrotesk-SemiBold`; the weight class is 600. Variation tables and unused
axis names are removed.

The converter runs as a private build tool with pinned fontTools and Brotli.
It adds no application dependency. Its output directory is supplied by the
caller under approved task storage; it never replaces different existing
bytes. Managed conversion produced a 32,028-byte asset. A second derivation
with Python 3.12.14 produced identical bytes. After promotion, its read-only
`--check` verifies the asset's metadata and the input and output hashes above.
This does not establish native font rendering or screenshot parity.

## Coverage and fallbacks

The embedded Space Grotesk is a subset with 291 glyphs and 230 mapped
characters. It omits characters present in the existing full fonts, including
the approximation sign. Deriving weight 600 keeps that subset; it does not
add glyphs.

Keep the full Space Grotesk 400, 500 and 700 faces and all existing JetBrains
Mono faces. The mono files are version 2.305; the mockup's inline mono subset
is 2.211. This records their provenance without claiming pixel parity.

The retained full Space Grotesk faces provide coverage for characters missing
from the new 600 subset. Their coverage alias belongs after the bundled Noto
Sans Arabic and Noto Sans Devanagari fallbacks, before the system Han faces.
The bundled script fallbacks and Simplified Chinese system-face order stay
in force. The 600 Latin face does not replace a locale fallback.

## Licenses

Space Grotesk is copyright 2020 The Space Grotesk Project Authors. JetBrains
Mono is copyright 2020 The JetBrains Mono Project Authors. Both use the SIL
Open Font License 1.1. Their notices are `OFL-SpaceGrotesk.txt` and
`OFL-JetBrainsMono.txt`; `OFL-NotoSans.txt` covers the bundled script fallbacks.
Keep these notices with the distributed fonts, including the derived face.
