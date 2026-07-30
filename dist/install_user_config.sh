#!/bin/bash
# Install the bundled per-user mapping after the privileged system install.
set -Eeuo pipefail

PAYLOAD="${1:?payload dir required}"
MODE="${2:-public}"
SOURCE="$PAYLOAD/config.jsonc"
TARGET_DIR="$HOME/.config/siriremote"
TARGET="$TARGET_DIR/config.jsonc"

[ -f "$SOURCE" ] || { echo "missing bundled config: $SOURCE" >&2; exit 1; }
case "$MODE" in
    public|preset|personal) ;;
    *) echo "unsupported package mode: $MODE" >&2; exit 2 ;;
esac

/bin/mkdir -p "$TARGET_DIR"

if [ -f "$TARGET" ]; then
    if /usr/bin/cmp -s "$SOURCE" "$TARGET"; then
        echo "config already matches the bundled mapping"
        exit 0
    fi

    if [ "$MODE" = "public" ]; then
        echo "existing config preserved (public package)"
        exit 0
    fi

    BACKUP="$TARGET.backup.$(/bin/date +%Y%m%d-%H%M%S)"
    /bin/cp "$TARGET" "$BACKUP"
    echo "existing config backed up: $BACKUP"
fi

/bin/cp "$SOURCE" "$TARGET"
/bin/chmod 600 "$TARGET"
echo "bundled $MODE mapping installed: $TARGET"
