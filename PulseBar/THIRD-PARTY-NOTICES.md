# Third-party notices

## Stats

NetworkReader.counter is adapted from getBytesInfo() in Modules/Net/readers.swift.
Source: https://github.com/exelban/stats/blob/4addbcd3f7057781aa63e813d91b7f2af7859c58/Modules/Net/readers.swift

Changes: return UInt64 counters, validate message boundaries and interface state,
use unaligned loads, and integrate with an elapsed-time tracker.

MIT License

Copyright (c) 2019 Serhiy Mytrovtsiy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Omarchy

Palette values from themes/{tokyo-night,gruvbox,everforest,catppuccin}/colors.toml,
https://github.com/omacom/omarchy/tree/quattro/themes (accessed 2026-10-31).
Foreground and secondary colors are chosen for contrast. Panel typography, square
borders, spacing and interaction layout follow shell/Commons/Style.qml and the
first-party panel source at commit bda3aaf6955404712dbd46541e6c8a75a2b16b7c.
No Omarchy logo or wordmark is used.

Copyright (c) David Heinemeier Hansson

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## JetBrains Mono Nerd Font

Unmodified Regular and Bold fonts from Nerd Fonts v3.4.0,
https://github.com/ryanoasis/nerd-fonts/tree/v3.4.0/patched-fonts/JetBrainsMono/Ligatures.
Original typeface by JetBrains; Nerd Fonts patches by Ryan L McIntyre and contributors.
Loaded with CoreText process scope, never installed in system or user font directories.
Full SIL Open Font License and Nerd Fonts licensing notices are in Assets/Fonts/
in the source and Contents/Resources/Fonts/ in the app bundle.

## Weather data

Weather data is requested from Open-Meteo only after the user's city query.
Attribution: Weather data by Open-Meteo.com (https://open-meteo.com/), CC BY 4.0
(https://creativecommons.org/licenses/by/4.0/). No Open-Meteo server code is included.
