FROM elixir:1.18.4-otp-27-slim AS build

RUN apt-get update -y && apt-get install -y --no-install-recommends build-essential git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

RUN mkdir -p config
COPY config/config.exs config/prod.exs ./config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets
RUN mix assets.deploy
RUN mix compile

COPY config/runtime.exs config/
RUN mix release

FROM debian:bookworm-slim AS app

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends ca-certificates libstdc++6 libncurses6 libtinfo6 openssl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN mkdir -p /data/auth && chown -R nobody:root /app /data/auth

ENV MIX_ENV=prod \
    PHX_SERVER=true \
    PORT=4000 \
    STORYTELLER_AUTH_DIR=/data/auth \
    STORYTELLER_BIND_ADDRESS=0.0.0.0

COPY --from=build --chown=nobody:root /app/_build/prod/rel/storyteller ./

USER nobody

EXPOSE 4000

CMD ["/bin/sh", "-c", "./bin/storyteller eval 'Storyteller.Release.migrate()' && exec ./bin/storyteller start"]
