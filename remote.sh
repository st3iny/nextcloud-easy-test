#!/bin/bash

# Function to show text in green
print_green() {
    local TEXT="$1"
    printf "%b%s%b\n" "\e[0;92m" "$TEXT" "\e[0m"
}

# Show how to reach the server
show_startup_info() {
    if [ -z "$TRUSTED_DOMAIN" ]; then
        print_green "The server should now be reachable via https://localhost:8443/"
    else
        print_green "The server should now be reachable via https://$TRUSTED_DOMAIN:8443/"
    fi
}

# Shortcut to occ
occ () {
    sudo -u www-data php -f /var/www/html/occ "$@"
}

# Skip if already installed
[ -f /var/www/html/installed ] && exit 0

# Handle empty or partial server branch variable
if [ -z "$SERVER_BRANCH" ]; then
    export SERVER_BRANCH=nextcloud:master
elif ! echo "$SERVER_BRANCH" | grep -q ':'; then
    export SERVER_BRANCH=nextcloud:"$SERVER_BRANCH"
fi

# Get NVM code
. "$NVM_DIR/nvm.sh"

# Fix git config
git config --global pull.rebase true

# Extract server branch name and fork owner
FORK_OWNER="${SERVER_BRANCH%%:*}"
FORK_BRANCH="${SERVER_BRANCH#*:}"

# Clone server repository
if ! git clone https://github.com/"$FORK_OWNER"/server.git \
    --branch "$FORK_BRANCH" \
    --single-branch \
    --recurse-submodules \
    --shallow-submodules \
    --depth=1 \
    /tmp/html
then
    echo "Could not clone the requested server branch '$FORK_BRANCH' of '$FORK_OWNER'. Does it exist?"
    exit 1
fi

# Move server repository into place
rsync -arh /tmp/html/ /var/www/html/
rm -rf /tmp/html

# Fix permissions
chown -R www-data:www-data /var/www/html

# Install Nextcloud
if ! occ \
        maintenance:install \
        --database=sqlite \
        --admin-user=admin \
        --admin-pass=nextcloud; then
    echo "Failed to create the instance."
    exit 1
fi

# Set logging configuration
[ -n "$LOG_FILE" ] && occ config:system:set logfile --value="$LOG_FILE"
[ -n "$LOG_LEVEL" ] && occ config:system:set loglevel --value="$LOG_LEVEL" --type=integer

# Set trusted domain if needed
if [ -n "$TRUSTED_DOMAIN" ]; then
    index=1
    for domain in $TRUSTED_DOMAIN; do
        if ! occ config:system:set trusted_domains "$index" --value="$domain"; then
            echo "Could not set the trusted domain '$domain'"
            exit 1
        fi
        index=$((index + 1))
    done
fi

# Set instance name
if [ -n "$INSTANCE_NAME" ]; then
    occ theming:config name "$INSTANCE_NAME"
fi

# Set reverse proxy configs
[ -n "$OVERWRITE_CLI_URL" ] && occ config:system:set overwrite.cli.url --value="$OVERWRITE_CLI_URL"
[ -n "$OVERWRITE_PROTOCOL" ] && occ config:system:set overwriteprotocol --value="$OVERWRITE_PROTOCOL"
[ -n "$OVERWRITE_HOST" ] && occ config:system:set overwritehost --value="$OVERWRITE_HOST"
[ -n "$OVERWRITE_WEB_ROOT" ] && occ config:system:set overwritewebroot --value="$OVERWRITE_WEB_ROOT"

# Configure pretty urls
if [ "$ENABLE_PRETTY_URLS" = true ]; then
    occ config:system:set htaccess.RewriteBase --value=/
    occ maintenance:update:htaccess
fi

# Install and enable apps
install_enable_app() {
    # Variables
    local BRANCH="$1"
    local APPID="$2"

    # Logic
    if [ -n "$BRANCH" ]; then
        # Fix partial branch
        if ! echo "$BRANCH" | grep -q ':'; then
            BRANCH=nextcloud:"$BRANCH"
        fi

        # Go into apps directory
        cd /var/www/html/apps

        # Remove app directory
        if [ -d ./"$APPID" ]; then
            occ app:disable "$APPID"
            rm -r ./"$APPID"
        fi

        local APP_OWNER="${BRANCH%%:*}"
        local APP_BRANCH="${BRANCH#*:}"

        # Clone repo
        if ! git clone https://github.com/"$APP_OWNER"/"$APPID".git \
            --branch "$APP_BRANCH" \
            --single-branch \
            --depth=1
        then
            echo "Could not clone the requested branch '$APP_BRANCH' of the $APPID app of '$APP_OWNER'. Does it exist?"
            exit 1
        fi

        # Go into app directory
        cd ./"$APPID"

        # Handle node versions
        nvm use --lts

        # Install composer dependencies
        if [ -f composer.json ]; then
            if ! composer install --no-dev; then
                echo "Could not install composer dependencies of the $APPID app."
                exit 1
            fi
        fi

        # Compile apps
        if [ -f package.json ]; then
            npm_cmd=build

            # Try to create a dev build
            if [ "$(jq -r .scripts.dev < package.json)" != null ]; then
                npm_cmd=dev
            fi

            if ! npm install || ! npm run "$npm_cmd" --if-present; then
                echo "Could not compile the $APPID app."
                exit 1
            fi
        fi

        # Enable app
        if ! occ app:enable "$APPID"; then
            echo "Could not enable the $APPID app."
            exit 1
        fi
    fi
}

# Compatible apps
install_enable_app "$ACTIVITY_BRANCH" activity
install_enable_app "$APPROVAL_BRANCH" approval
install_enable_app "$BOOKMARKS_BRANCH" bookmarks
install_enable_app "$CALENDAR_BRANCH" calendar
install_enable_app "$CIRCLES_BRANCH" circles
install_enable_app "$CONTACTS_BRANCH" contacts
install_enable_app "$DECK_BRANCH" deck
install_enable_app "$DOWNLOADLIMIT_BRANCH" files_downloadlimit
install_enable_app "$E2EE_BRANCH" end_to_end_encryption
install_enable_app "$FIRSTRUNWIZARD_BRANCH" firstrunwizard
install_enable_app "$FORMS_BRANCH" forms
install_enable_app "$GROUPFOLDERS_BRANCH" groupfolders
install_enable_app "$GUESTS_BRANCH" guests
install_enable_app "$IMPERSONATE_BRANCH" impersonate
# install_enable_app "$ISSUTEMPLATE_BRANCH" issuetemplate
install_enable_app "$LOGREADER_BRANCH" logreader
install_enable_app "$MAIL_BRANCH" mail
install_enable_app "$MAPS_BRANCH" maps
install_enable_app "$NEWS_BRANCH" news
install_enable_app "$NOTES_BRANCH" notes
install_enable_app "$NOTIFICATIONS_BRANCH" notifications
install_enable_app "$PDFVIEWER_BRANCH" files_pdfviewer
install_enable_app "$PHOTOS_BRANCH" photos
install_enable_app "$POLLS_BRANCH" polls
install_enable_app "$RECOMMENDATIONS_BRANCH" recommendations
install_enable_app "$SERVERINFO_BRANCH" serverinfo
install_enable_app "$TALK_BRANCH" spreed
install_enable_app "$TASKS_BRANCH" tasks
install_enable_app "$TEXT_BRANCH" text
install_enable_app "$VIEWER_BRANCH" viewer
install_enable_app "$ZIPPER_BRANCH" files_zip

# Free some disk space
shopt -s globstar
rm -rf /var/www/html/**/node_modules /var/www/html/**/.git

# Clear cache
cd /var/www/html
if ! occ maintenance:repair; then
    echo "Could not clear the cache"
    exit 1
fi

# Mark instance as installed
touch /var/www/html/installed

# Show how to reach the server
show_startup_info
print_green "You can log in with the user 'admin' and its password 'nextcloud'"
