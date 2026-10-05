"""Better at Gambling Room Orchestrator: spawns one headless Godot server per room."""

from .app import create_app
from .config import Config, ConfigError

__all__ = ["Config", "ConfigError", "create_app"]
__version__ = "1.0.0"
