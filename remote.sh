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
[ -z "$SERVER_OWNER" ] && SERVER_OWNER=nextcloud
[ -z "$SERVER_REPO" ] && SERVER_REPO=server
[ -z "$SERVER_BRANCH" ] && SERVER_BRANCH=master

# Get NVM code
. "$NVM_DIR/nvm.sh"

# Fix git config
git config --global pull.rebase true

# Clone server repository
if ! git clone https://github.com/"$SERVER_OWNER"/"$SERVER_REPO".git /tmp/html \
    --branch "$SERVER_BRANCH" \
    --single-branch \
    --recurse-submodules \
    --shallow-submodules \
    --depth=1
then
    echo "Could not clone the requested server branch '$SERVER_BRANCH' of '$SERVER_OWNER/$SERVER_REPO'. Does it exist?"
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
    local APP_PREFIX="$1"
    local APPID="$2"

    # Get values from given prefix
    local APP_OWNER_VAR="${APP_PREFIX}_OWNER"
    local APP_OWNER="${!APP_OWNER_VAR}"
    local APP_REPO_VAR="${APP_PREFIX}_REPO"
    local APP_REPO="${!APP_REPO_VAR}"
    local APP_BRANCH_VAR="${APP_PREFIX}_BRANCH"
    local APP_BRANCH="${!APP_BRANCH_VAR}"

    [ -z "$APP_OWNER" ] && APP_OWNER=nextcloud
    [ -z "$APP_REPO" ] && APP_REPO="$APPID"

    # Dev mail servers are probably not secure
    [ "$APPID" = mail ] && occ config:system:set --type=bool --value=false app.mail.verify-tls-peer

    # Logic
    if [ -n "$APP_BRANCH" ]; then
        # Go into apps directory
        cd /var/www/html/apps

        # Remove app directory
        if [ -d ./"$APPID" ]; then
            occ app:disable "$APPID"
            rm -r ./"$APPID"
        fi

        # Clone repo
        if ! git clone https://github.com/"$APP_OWNER"/"$APP_REPO".git "$APPID" \
            --branch "$APP_BRANCH" \
            --single-branch \
            --depth=1
        then
            echo "Could not clone the requested branch '$APP_BRANCH' of the $APPID app of '$APP_OWNER/$APP_REPO'. Does it exist?"
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

            if ! npm i --no-audit || ! npm run "$npm_cmd" --if-present; then
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
install_enable_app ACTIVITY activity
install_enable_app APPROVAL approval
install_enable_app BOOKMARKS bookmarks
install_enable_app CALENDAR calendar
install_enable_app CIRCLES circles
install_enable_app CONTACTS contacts
install_enable_app DECK deck
install_enable_app DOWNLOADLIMIT files_downloadlimit
install_enable_app E2EE end_to_end_encryption
install_enable_app FIRSTRUNWIZARD firstrunwizard
install_enable_app FORMS forms
install_enable_app GROUPFOLDERS groupfolders
install_enable_app GUESTS guests
install_enable_app IMPERSONATE impersonate
# install_enable_app ISSUTEMPLATE issuetemplate
install_enable_app LOGREADER logreader
install_enable_app MAIL mail
install_enable_app MAPS maps
install_enable_app NEWS news
install_enable_app NOTES notes
install_enable_app NOTIFICATIONS notifications
install_enable_app PDFVIEWER files_pdfviewer
install_enable_app PHOTOS photos
install_enable_app POLLS polls
install_enable_app RECOMMENDATIONS recommendations
install_enable_app SERVERINFO serverinfo
install_enable_app TALK spreed
install_enable_app TASKS tasks
install_enable_app TEXT text
install_enable_app VIEWER viewer
install_enable_app ZIPPER files_zip

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
