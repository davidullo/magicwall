# Third-party notices

MagicWall is distributed under the MIT license (see [`LICENSE`](LICENSE)).

## Swift package dependencies

### Sparkle

- Source: https://github.com/sparkle-project/Sparkle
- License: MIT (the bundled binary also carries the notices listed in
  [Sparkle's LICENSE file](https://github.com/sparkle-project/Sparkle/blob/2.x/LICENSE):
  bspatch/bsdiff, sais-lite, Ed25519 by Orson Peters, SUSignatureVerifier)
- Copyright (c) 2006-2013 Andy Matuschak; 2009-2013 Elgato Systems GmbH;
  2011-2014 Kornel Lesiński; 2015-2017 Mayur Pawashe; 2014 C.W. Betts;
  2014 Petroules Corporation; 2014 Big Nerd Ranch.

```
Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

### GRDB.swift

- Source: https://github.com/groue/GRDB.swift
- License: MIT
- Copyright (C) 2015-2025 Gwendal Roué

```
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
```

## Media assets

- **Starter wallpapers** — the app offers five optional 4K wallpapers
  ("Dreamscape", "Clover Rainbow", "Aurora Forest", "Cherry Blossom Spring",
  "Colorful Underwater Scene"). Each one is published in two quality tiers
  (`high`, re-encoded from the source masters with x265, and `compact`, encoded
  with VideoToolbox HEVC), is downloaded on request from the `starter-v2` GitHub
  release, is not bundled with the app and is not committed to this repository.
  The MIT license of this repository does **not** cover them.
- Demo/test media is generated locally and is not part of the distributed app.
- The marketing site (`site/`) ships derivative stills and clips; the source
  files are not committed (see `site/README.md` for the derivations).
