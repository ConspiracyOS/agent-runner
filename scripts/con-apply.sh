#!/bin/bash
# Apply a config profile to a running container via container exec.
# Usage: con-apply.sh <profile> <container-name>
set -euo pipefail

PROFILE="$1"
NAME="$2"
SRC="configs/${PROFILE}"

find "$SRC" -type f | while IFS= read -r f; do
    rel="${f#${SRC}/}"
    dir="$(dirname "$rel")"
    container exec "$NAME" mkdir -p "/etc/con/${dir}"

    # Write file content via heredoc (container exec stdin piping is unreliable)
    content="$(cat "$f")"
    container exec "$NAME" bash -c "cat > '/etc/con/${rel}' << 'CONEOF'
${content}
CONEOF"

    # Preserve execute bit from source
    if [ -x "$f" ]; then
        container exec "$NAME" chmod +x "/etc/con/${rel}"
    fi
    echo "  + /etc/con/${rel}"
done

echo "Running bootstrap..."
container exec "$NAME" bash -c 'set -a; . /etc/con/env 2>/dev/null; set +a; con bootstrap'
echo "Profile ${PROFILE} applied to ${NAME}."
