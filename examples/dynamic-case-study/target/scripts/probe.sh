#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '{"kind":"route","name":"GET /health","path":"src/server.ts","evidence":{"source":"fixture-probe","handler":"health"}}'
printf '%s\n' '{"kind":"route","name":"POST /users","path":"src/server.ts","evidence":{"source":"fixture-probe","handler":"users"}}'
printf '%s\n' '{"kind":"di_binding","name":"UserService","path":"src/server.ts","evidence":{"source":"fixture-probe"}}'
printf '%s\n' '{"kind":"event_subscription","name":"user.created","path":"src/server.ts","evidence":{"source":"fixture-probe"}}'
