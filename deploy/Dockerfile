# Server image: room orchestrator (Python) + headless Godot that runs one process per room.
# Built on the VPS by deploy/install.sh from a checkout of the repo (context = repo root).
FROM public.ecr.aws/docker/library/python:3.12-slim-bookworm

ARG GODOT_VERSION=4.7.2
ARG GODOT_SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
	&& rm -rf /var/lib/apt/lists/* \
	&& curl -fsSL --retry 4 -o /tmp/godot.zip \
		"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
	&& echo "${GODOT_SHA512}  /tmp/godot.zip" | sha512sum -c - \
	&& unzip -q /tmp/godot.zip -d /tmp \
	&& mv /tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
	&& chmod +x /usr/local/bin/godot && rm -f /tmp/godot.zip \
	&& useradd --create-home --uid 10001 bag \
	&& mkdir -p /var/log/bag-rooms && chown bag:bag /var/log/bag-rooms

COPY services/orchestrator/requirements.txt /opt/bag/orchestrator/requirements.txt
RUN python -m venv /opt/bag/venv && /opt/bag/venv/bin/pip install --no-cache-dir -r /opt/bag/orchestrator/requirements.txt

COPY --chown=bag:bag services/orchestrator /opt/bag/orchestrator
COPY --chown=bag:bag . /opt/bag/game
COPY deploy/entrypoint.sh /usr/local/bin/bag-entrypoint

USER bag
# Import once at build time so room processes start in about a second.
RUN godot --headless --path /opt/bag/game --import >/tmp/import.log 2>&1 || (tail -50 /tmp/import.log; exit 1)

ENV GAME_SERVER_CMD="/usr/local/bin/godot --headless --path /opt/bag/game --audio-driver Dummy --" \
	GAME_SERVER_CWD=/opt/bag/game \
	LOG_DIR=/var/log/bag-rooms \
	PYTHONUNBUFFERED=1
WORKDIR /opt/bag/orchestrator
ENTRYPOINT ["/usr/local/bin/bag-entrypoint"]
