#!/usr/bin/env python3
"""Render text with styles that survive plannotator's markdown renderer.

plannotator strips every inline styling HTML tag (<u>, <ins>, <mark>, <kbd>,
<span style>), and markdown has no underline or small-caps. These effects only
survive as Unicode. All are verified to render in plannotator (probed 2026-07-14).

Styles:
    (default)        single underline  (combining U+0332)   key-phrase emphasis
    --double         double underline  (combining U+0333)    the ONE critical phrase
    --smallcaps      ꜱᴍᴀʟʟ ᴄᴀᴘꜱ                              labels / status tags
    --smallcaps-underline  small caps + single underline     a label that must pop

Usage:
    textstyle.py "key phrase"                 # single underline
    textstyle.py --double "critical"          # double underline
    textstyle.py --smallcaps "recommended"    # small caps
    echo "risk" | textstyle.py --smallcaps-underline

Caveat: Unicode combining marks and small-caps letters break copy/paste, Ctrl-F
search, and screen readers. Use ONLY on short KEY phrases and labels, never body
text. Reach for markdown **bold** / *italic* / `code` first.
"""
import sys

U0332 = "̲"  # COMBINING LOW LINE (single underline)
U0333 = "̳"  # COMBINING DOUBLE LOW LINE

SMALLCAPS = {
    "a": "ᴀ", "b": "ʙ", "c": "ᴄ", "d": "ᴅ", "e": "ᴇ", "f": "ꜰ", "g": "ɢ",
    "h": "ʜ", "i": "ɪ", "j": "ᴊ", "k": "ᴋ", "l": "ʟ", "m": "ᴍ", "n": "ɴ",
    "o": "ᴏ", "p": "ᴘ", "q": "ǫ", "r": "ʀ", "s": "ꜱ", "t": "ᴛ", "u": "ᴜ",
    "v": "ᴠ", "w": "ᴡ", "x": "x", "y": "ʏ", "z": "ᴢ",
}


def combine(text: str, mark: str) -> str:
    return "".join(ch + mark for ch in text)


def smallcaps(text: str) -> str:
    return "".join(SMALLCAPS.get(ch.lower(), ch) for ch in text)


def render(text: str, style: str) -> str:
    if style == "double":
        return combine(text, U0333)
    if style == "smallcaps":
        return smallcaps(text)
    if style == "smallcaps-underline":
        return combine(smallcaps(text), U0332)
    return combine(text, U0332)  # default: single underline


def main() -> int:
    args = sys.argv[1:]
    style = "underline"
    for flag in ("--double", "--smallcaps", "--smallcaps-underline"):
        if flag in args:
            style = flag[2:]
            args = [a for a in args if a != flag]
    text = " ".join(args) if args else sys.stdin.read().rstrip("\n")
    if not text:
        return 0
    sys.stdout.write(render(text, style))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
