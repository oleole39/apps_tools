#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

update_venv() {
    if [ -d "venv" ]; then
        venv/bin/pip install -r requirements.txt >/dev/null
    fi
}

update_apps_repo() {
    if [ -d ".apps" ]; then
        git -C .apps pull
    else
        git clone https://github.com/YunoHost/apps.git .apps
    fi
    .cache/tools/app_caches.py -l .cache/apps/ -c .apps_cache -d -j20
}

update_apps_cache() {
    ./tools/app_caches.py -d -l . -c .apps_cache -j20
}

git_pull_and_restart_services() {
    commit="$(git rev-parse HEAD)"

    if ! git pull &>/dev/null; then
        sendxmpppy "[apps-tools] Couldn't pull, maybe local changes are present?"
        exit 1
    fi

    if [[ "$(git rev-parse HEAD)" == "$commit" ]]; then
        return
    fi

    # Cron
    cat cron | sed "s@__BASEDIR__@$SCRIPT_DIR@g" > /etc/cron.d/apps_tools

    pushd app_generator > /dev/null
        update_venv
        pushd assets >/dev/null
            ./tailwindcss-linux-x64 --input tailwind-local.css --output tailwind.css --minify
        popd >/dev/null
    popd > /dev/null
    systemctl restart appgenerator
    sleep 3
    systemctl --quiet is-active appgenerator || sendxmpppy "[appgenerator] Uhoh, failed to (re)start the appgenerator service?"


    update_venv

    systemctl restart webhooks
    sleep 3
    systemctl --quiet is-active webhooks || sendxmpppy "[autoreadme] Uhoh, failed to (re)start the autoreadme service?"

}

rebuild_catalog_error_msg="[list_builder] Rebuilding the application list failed miserably!"
rebuild_catalog() {
    date
    update_app_cache
    ./tools/list_builder.py -l .
}

autoupdate_app_sources_error_msg="[autoupdate_app_sources] App sources auto-update failed miserably!"
autoupdate_app_sources() {
    date
    update_app_cache
    tools/autoupdate_app_sources/venv/bin/python3 tools/autoupdate_app_sources/autoupdate_app_sources.py \
        -l . --latest-commit-weekly --edit --commit --pr --paste -j1
}

update_app_levels_error_msg="[update_app_levels] Updating apps level failed miserably!"
update_app_levels() {
    date
    update_app_cache
    python3 update_app_levels.py -l .
}

safe_run() {
    logfile="$SCRIPT_DIR/$1.log"
    error_msg_var="${1}_error_msg"
    if ! "$@" &> "$logfile"; then
        sendxmpppy "${!error_msg_var}"
    fi
}

main() {
    cd "$SCRIPT_DIR"

    # Update self, then re-exec to prevent an issue with modified bash scripts
    if [[ -z "${APPS_TOOLS_UPDATED:-}" ]]; then
        git_pull_and_restart_services
        APPS_TOOLS_UPDATED=1 exec "$0" "$@"
    fi

    safe_run "$@"
}

main "$@"
