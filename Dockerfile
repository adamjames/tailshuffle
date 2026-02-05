FROM node:22-alpine

WORKDIR /app

RUN apk update && apk upgrade --no-cache && apk add --no-cache git zip

ARG CRAWLER_REV=dbb837885a56e3b39dd01835c258016c4ded3e4b
RUN git clone https://github.com/kiliman/tailwindui-crawler.git \
    && cd tailwindui-crawler && git checkout "$CRAWLER_REV"

COPY --chmod=644 fix-crawler-deps.patch ./

RUN npm install -g npm@latest shuffle-package-maker

WORKDIR /app/tailwindui-crawler
RUN git apply /app/fix-crawler-deps.patch \
    && npm install \
    && npm audit fix

WORKDIR /app
