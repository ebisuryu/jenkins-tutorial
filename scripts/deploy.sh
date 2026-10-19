#!/bin/sh
# Transactional replacement on the local Docker daemon. A short outage is expected.
set -eu

IMAGE=${1:?Usage: deploy.sh IMAGE staging|production}
ENVIRONMENT=${2:?Usage: deploy.sh IMAGE staging|production}
case "$ENVIRONMENT" in
    staging) NAME=house-price-api-staging; PORT=30002 ;;
    production) NAME=house-price-api; PORT=30001 ;;
    *) echo 'Environment must be staging or production' >&2; exit 2 ;;
esac
BACKUP="${NAME}-rollback"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

docker image inspect "$IMAGE" >/dev/null
# Do not overwrite recovery state from an interrupted deployment.
if docker container inspect "$BACKUP" >/dev/null 2>&1; then
    echo "Recovery container $BACKUP already exists; inspect it before retrying." >&2
    exit 1
fi

HAD_PREVIOUS=false
NEW_STARTED=false
restore() {
    trap - EXIT HUP INT TERM
    if [ "$NEW_STARTED" = true ]; then
        docker logs --tail 60 "$NAME" >&2 || true
        docker rm -f "$NAME" >/dev/null || true
    fi
    if [ "$HAD_PREVIOUS" = true ]; then
        docker rename "$BACKUP" "$NAME"
        docker start "$NAME" >/dev/null
        echo "Restored previous $ENVIRONMENT container." >&2
    fi
}
trap 'restore' EXIT
trap 'exit 1' HUP INT TERM

if docker container inspect "$NAME" >/dev/null 2>&1; then
    docker rename "$NAME" "$BACKUP"
    HAD_PREVIOUS=true
    docker stop "$BACKUP" >/dev/null
fi
NEW_STARTED=true
docker run -d --name "$NAME" --restart unless-stopped \
    --label "deployment.environment=$ENVIRONMENT" \
    -p "$PORT:30000" "$IMAGE"
docker exec -i "$NAME" python < "$SCRIPT_DIR/smoke_test.py"

# Commit the deployment only once the new API passes smoke tests.
trap - EXIT HUP INT TERM
if [ "$HAD_PREVIOUS" = true ]; then
    docker rm "$BACKUP" >/dev/null
fi
echo "Deployed $IMAGE to $ENVIRONMENT on port $PORT"
