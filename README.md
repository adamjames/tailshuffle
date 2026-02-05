# Tailshuffle.sh
Some nice wrapping to help you use [Tailwind Pro](https://tailwindcss.com) with [Shuffle.dev](https://shuffle.dev). Released under MIT — see [LICENSE](LICENSE).

[tailwindui-crawler](https://github.com/kiliman/tailwindui-crawler) downloads the components and [shuffle-package-maker](https://www.npmjs.com/package/shuffle-package-maker) packs up the HTML into Shuffle's custom library format. At the risk of stating the obvious, this tool requires an active [Tailwind Plus](https://tailwindcss.com/plus) subscription. In particular, it should go without saying that you are responsible for complying with the Tailwind Plus [terms of service](https://tailwindcss.com/plus/license).

The manual steps are straightforward enough, I've just tied it all together with some script glue, fixes and polish, running the whole lot inside of Docker or Podman to keep your machine clean. Built on NixOS, but should work on macOS, Linux or Windows via WSL2 as long as you've Docker or Podman installed. Many thanks of course to [@tailwindlabs](https://github.com/tailwindlabs) for their years of love poured into Tailwind (go buy it!), [@kiliman](https://github.com/kiliman) and [@shuffle-dev](https://github.com/nickytonline/shuffle-dev) for the code that does 90% of the heavy lifting here.

## Usage
```bash
./tailshuffle.sh              # show help, offer to run full pipeline
./tailshuffle.sh all          # full interactive pipeline

## Or, run individual steps
./tailshuffle.sh build        # build the Docker image
./tailshuffle.sh download     # download components
./tailshuffle.sh convert      # convert to shuffle format
./tailshuffle.sh catalog      # generate components-catalog.json (LLM context)
./tailshuffle.sh package      # zip + validate
./tailshuffle.sh clean        # remove build artefacts
```

The final output is `tailwind-shuffle-components.zip`, ready to upload. Components are cached in `cache/` for inspection and subsequent runs.

Once you're done, you can build using the Pro components inside of Shuffle as you please.

<img alt="An example page using the Tailwind Pro components" src="https://github.com/user-attachments/assets/06df903c-746e-4b3a-8b94-3ebf4dd936e4" />

## Manual Steps
If you already have node/npx ready to go, you can replicate most of what the pipeline does by hand:

**Step 1** — Set up your credentials:
```bash
# .env.example
EMAIL=your-tailwindui-email@example.com
PASSWORD=your-tailwindui-password
OUTPUT=/app/output
LANGUAGES=html
COMPONENTS=all
BUILDINDEX=0
TEMPLATES=0
```

**Step 2** — Clone and patch tailwindui-crawler:

```bash
git clone https://github.com/kiliman/tailwindui-crawler.git
cd tailwindui-crawler
patch -p1 < /path/to/fix-crawler-deps.patch
npm install
```

The patch modifies `package.json`:

1. **Removes unused dependencies** — `cookie`, `form-urlencoded`, and `glob` aren't actually used at runtime
2. **Adds an npm override for `tmp`** — forces version `^0.2.4` instead of the vulnerable `^0.0.33`

The vulnerability ([GHSA-52f5-9888-hmc6](https://github.com/advisories/GHSA-52f5-9888-hmc6)) is a symlink-based arbitrary file write in `tmp`. It comes in through a deep dependency chain:

```
all-contributors-cli → inquirer → external-editor → tmp@^0.0.33
```

`external-editor` pins `tmp` to `^0.0.33`, which semver locks it to `<0.1.0` — so it can never reach the patched `0.2.x` line without an override.

**Step 3** — Download components:

```bash
npm start
```

This gives you files in `./output/html/ui-blocks/{marketing,application-ui,ecommerce}/...`

**Step 4** — Convert with shuffle-package-maker:
```bash
npx shuffle-package-maker /path/to/tailwindui-crawler/output/html/ui-blocks --preset=tailwindui
```

Note that the crawler outputs to `html/ui-blocks/`, not `html/components/` as the shuffle-package-maker docs suggest.

**Step 5** — Brand the library metadata (optional):
```bash
unzip output.zip shuffle.config.json

# shuffle reads this to display the library name/description in their UI
sed -i \
  -e 's|Tailwind UI all components|you@example.com|' \
  -e 's|Tailwind UI All|Tailwind UI Pro|' \
  shuffle.config.json

# delete and re-add to avoid stored vs deflated warnings
zip -d output.zip shuffle.config.json
zip output.zip shuffle.config.json
```

**Step 6** — Generate a component catalog for LLMs (optional, but useful for LLM's):
```bash
node catalog.mjs
```

**Step 7** — [Upload to Shuffle.dev](https://shuffle.dev/dashboard#/libraries/uploaded) and make pages.

<img alt="The Shuffle dashboard showing an uploaded component pack" src="https://github.com/user-attachments/assets/93c08fda-afa6-4e0f-aded-00074a8cd35f" />

## Debugging
I've tested this fairly extensively, at least in Docker, though Podman should work wihout issue. That said, if you do run into anything...

- **Login fails** — check your [subscription](https://tailwindcss.com/plus); escape special characters in your password (e.g. `\$`)
- **Empty output** — check `cache/` for downloaded files; try `DEBUG=1` in `.env`
- **Missing components** — set `COMPONENTS=all` and `FORCE_UPDATE=1` in `.env`
