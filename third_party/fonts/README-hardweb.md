# Console font

`hardweb-cp437-8x16.bin` is the text console's font: 256 glyphs, 8x16, in
code page 437 order (PC box drawing at 0xB3..0xDA, blocks 0xDB..0xDF), in
the console's interlaced layout (even glyph rows at `code * 8 + row / 2`,
odd rows at `2048 + code * 8 + row / 2`).

It is a derivative of **Terminus Font** (Bold VGA 8x16), Copyright (c) 2010
Dimitar Toshkov Zhekov, licensed under the SIL Open Font License 1.1
(`OFL-1.1.txt`; "Terminus Font" is a Reserved Font Name, so this derivative
does not use it as its name). Glyphs were taken from Debian's console-setup
`Uni2-TerminusBoldVGA16.psf.gz` and rearranged by

    scripts/psf_to_cp437.py /usr/share/consolefonts/Uni2-TerminusBoldVGA16.psf.gz \
        assets/fonts/hardweb-cp437-8x16.bin

which also draws the half blocks and dark shade the font lacks. The
previous 8x8-derived font is `assets/asciifont.bin`.

Try a font on a running board without rebuilding:
`tools/send_udp_rom_update.py <board> --font-rom FONT.bin`.
