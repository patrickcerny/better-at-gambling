"""``python -m orchestrator``: run the orchestrator with uvicorn using env config."""

from __future__ import annotations

import sys

import uvicorn

from .app import create_app
from .config import Config, ConfigError
from .logjson import log


def main() -> int:
    """Validate config, build the app and serve it until SIGINT/SIGTERM."""
    try:
        config = Config.from_env()
        app = create_app(config)
    except ConfigError as exc:
        log("config_error", level="critical", message=str(exc))
        return 2
    uvicorn.run(app, host=config.bind_host, port=config.bind_port, access_log=False,
                proxy_headers=False, log_level="warning")
    return 0


if __name__ == "__main__":
    sys.exit(main())
