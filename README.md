# Shuffle.dev Tailwind UI Package Builder

The two upstream tools — `tailwindui-crawler` and `shuffle-package-maker` — each do their own job well. The [crawler](https://github.com/kiliman/tailwindui-crawler) downloads Tailwind UI components; [shuffle-package-maker](https://www.npmjs.com/package/shuffle-package-maker) packs up the HTML into shuffle.dev's custom library format.

The manual steps are straightforward enough - this repository ties it all together with some script glue, fixes and polish, running the whole lot inside of Docker or Podman to keep your machine clean.

## Usage

```bash
./build.sh              # show help, offer to run full pipeline
./build.sh all          # full interactive pipeline

## Or, run individual steps
./build.sh build        # build the Docker image
./build.sh download     # download components
./build.sh convert      # convert to shuffle format
./build.sh catalog      # generate components-catalog.json (LLM context)
./build.sh package      # zip + validate
./build.sh clean        # remove build artefacts
```

Downloaded components are cached in `cache/` so subsequent builds skip the download.

## Debugging

- **Login fails** — check your subscription at tailwindcss.com/plus; escape special characters in password (e.g. `\$`)
- **Empty output** — check `cache/` for downloaded files; try `DEBUG=1` in `.env`
- **Missing components** — set `COMPONENTS=all` and `FORCE_UPDATE=1` in `.env`

## Manual Steps

**Step 1** — Download components with tailwindui-crawler:

```bash
git clone https://github.com/kiliman/tailwindui-crawler.git
cd tailwindui-crawler
npm install
# create .env with EMAIL, PASSWORD, LANGUAGES=html, etc.
# .env.example can be used as a starting point.
npm start
```

This gives you files in `./output/html/ui-blocks/{marketing,application-ui,ecommerce}/...`

**Step 2** — Convert with shuffle-package-maker:

```bash
npm install shuffle-package-maker
npx shuffle-package-maker /path/to/tailwindui-crawler/output/html/components --preset=tailwindui
```

Note that the crawler outputs to `html/ui-blocks/`, not `html/components/` as the shuffle-package-maker docs suggest.

**Step 3** — Zip the output and upload to shuffle.dev → Settings → Libraries.