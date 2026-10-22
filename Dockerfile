# Servidor Godot headless para Render (Docker). Contexto de build: raíz del repo.
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.2-stable

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip \
      libx11-6 libxcursor1 libxinerama1 libxrandr2 libxi6 libxext6 libxrender1 \
      libfontconfig1 libgl1 libasound2 libpulse0 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/godot.zip \
      "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
    && unzip -q /tmp/godot.zip -d /opt \
    && mv "/opt/Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm /tmp/godot.zip

WORKDIR /app
COPY arcade-stars-horizons-edition/ /app/
# La lógica autoritativa de los juegos vive en games/<id>/; se copia a server/games/<id>/.
COPY games/ /tmp/games_src/
COPY tools/sync_server_logic.sh /tmp/sync_server_logic.sh
RUN sh /tmp/sync_server_logic.sh /tmp/games_src /app/server/games && rm -rf /tmp/games_src /tmp/sync_server_logic.sh

# Importa recursos (genera .godot/) para que los scripts compartidos con el cliente carguen bien.
RUN godot --headless --path /app --import || true

# Render inyecta PORT; el servidor lo lee. SUPABASE_URL y SUPABASE_SECRET_KEY van en el panel de Render.
ENV PORT=9080
EXPOSE 9080
CMD ["godot", "--headless", "--path", "/app", "res://server/server.tscn"]
