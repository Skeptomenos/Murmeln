#!/bin/bash
set -euo pipefail

SOURCE_ROOT="${1:-.}"

# Match the files a fresh Git checkout can publish. Include tracked files and
# non-ignored working-tree candidates, but exclude private planning and build
# products. Ignored local worktrees and dependency caches are machine state.
git -C "$SOURCE_ROOT" ls-files --cached --others --exclude-standard -- . \
    | LC_ALL=C awk '
        {
            path = tolower($0)
            if (path ~ /^_planning\//) next
            if (path ~ /(^|\/)(\.build|build|deriveddata)\//) next
            if (path ~ /\.(wav|m4a|mp3|aac|caf|flac|aiff|aif)$/) print
        }
    ' \
    | sort
