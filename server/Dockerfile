# Multi-stage Dockerfile for running any stbange/engine game as a dedicated cross-play WebSocket server
FROM ubuntu:24.04 AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git ca-certificates pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .

RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --target engine -j"$(nproc)"

FROM ubuntu:24.04 AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 libegl1 ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/sh engsrv

WORKDIR /app
COPY --from=build /src/build/engine /app/engine
COPY lua /app/lua
COPY shaders /app/shaders
COPY assets /app/assets
COPY games /app/games

ENV GAME_DIR=games/102_portal_arena_mp
ENV SERVER_PORT=7777
ENV TICK_RATE=30
ENV SDL_VIDEODRIVER=dummy
ENV SDL_AUDIODRIVER=dummy

USER engsrv
EXPOSE 7777

ENTRYPOINT ["/bin/sh", "-c", "exec /app/engine --server --repo-root /app --game \"$GAME_DIR\" --bind 0.0.0.0 --port \"$SERVER_PORT\" --tick-rate \"$TICK_RATE\""]
