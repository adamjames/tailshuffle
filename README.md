# Tailshuffle.sh
Some nice wrapping to help you use [Tailwind Pro](https://tailwindcss.com) with [Shuffle.dev](https://shuffle.dev). 

Many thanks of course to [@tailwindlabs](https://github.com/tailwindlabs) for their years of love poured into Tailwind (go buy it!) and [@kiliman](https://github.com/kiliman) and [@shuffle-dev](https://github.com/nickytonline/shuffle-dev) for the code that does 90% of the heavy lifting here. [tailwindui-crawler](https://github.com/kiliman/tailwindui-crawler) downloads the components; [shuffle-package-maker](https://www.npmjs.com/package/shuffle-package-maker) packs up the HTML into Shuffle's custom library format. The manual steps are straightforward enough, this repository ties it all together with some script glue, fixes and polish, running the whole lot inside of Docker or Podman to keep your machine clean.

## Notice
Using this tool requires an active [Tailwind Plus](https://tailwindcss.com/plus) subscription. 
In particular, you are responsible for complying with the [terms of service](https://tailwindcss.com/plus/license).

## License
MIT — see [LICENSE](LICENSE).

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

The final output is `tailwind-shuffle-components.zip`, ready to upload. Downloaded components are cached in `cache/` so subsequent builds skip the download.

## Debugging
- **Login fails** — check your [subscription](https://tailwindcss.com/plus); escape special characters in your password (e.g. `\$`)
- **Empty output** — check `cache/` for downloaded files; try `DEBUG=1` in `.env`
- **Missing components** — set `COMPONENTS=all` and `FORCE_UPDATE=1` in `.env`

## Manual Steps
If you already have node/npx ready to go, you can replicate most of what the pipeline does by hand:

**Step 1** — Download components with tailwindui-crawler:

```bash
git clone https://github.com/kiliman/tailwindui-crawler.git
cd tailwindui-crawler
patch -p1 < /path/to/fix-crawler-deps.patch  # security fix for upstream dep
npm install
# create .env based on .env.example
npm start
```

This gives you files in `./output/html/ui-blocks/{marketing,application-ui,ecommerce}/...`

**Step 2** — Convert with shuffle-package-maker:
```bash
npx shuffle-package-maker /path/to/tailwindui-crawler/output/html/ui-blocks --preset=tailwindui
```

Note that the crawler outputs to `html/ui-blocks/`, not `html/components/` as the shuffle-package-maker docs suggest.

**Step 3** — Brand the library metadata (optional):
```bash
unzip output.zip shuffle.config.json
sed -i \
  -e 's|Tailwind UI all components|you@example.com|' \
  -e 's|Tailwind UI All|Tailwind UI Pro|' \
  shuffle.config.json
zip -d output.zip shuffle.config.json
zip output.zip shuffle.config.json
```

**Step 4** — Generate a component catalog for LLMs (optional):
```bash
node catalog.mjs
```

**Step 5** — [Upload to Shuffle.dev](https://shuffle.dev/dashboard#/libraries/uploaded).

### What the pipeline adds

Beyond orchestrating the above, the script:

- **Runs everything in Docker/Podman** — no Node.js install needed, no leftover dependencies
- **Caches downloads** in `cache/` so you can rebuild without re-downloading
