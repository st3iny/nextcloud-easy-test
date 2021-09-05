#!/bin/bash

# Handle empty server branch variable
if [ -z "$SERVER_BRANCH" ]; then
    export SERVER_BRANCH=master
fi

# Get NVM code
export NVM_DIR="/var/www/.nvm"
. "$NVM_DIR/nvm.sh"

# Get latest changes
if ! [ -f /var/www/server-completed ]; then
    cd /var/www/html
    git pull
    if ! git checkout "$SERVER_BRANCH"; then
        echo "Could not get the '$SERVER_BRANCH' server branch. Doesn't seem to exist."
        exit 1
    fi
    git pull
    git submodule update --init

    # Install Nextcloud
    if ! php -f occ \
            maintenance:install \
            --database=sqlite \
            --admin-user=admin \
            --admin-pass=nextcloud; then
        echo "Failed to create the instance."
        exit 1
    fi

    # Set trusted domain if needed 
    if [ -n "$TRUSTED_DOMAIN" ]; then
        if ! php -f occ config:system:set trusted_domains 1 --value="$TRUSTED_DOMAIN"; then
            echo "Could not set the trusted domain '$TRUSTED_DOMAIN'"
            exit 1
        fi
    fi
    touch /var/www/server-completed
fi

# Install and enable apps
install_enable_app() {

# Variables
local BRANCH="$1"
local APPID="$2"
local NODE_VERSION="$3"

# Logic
if [ -n "$BRANCH" ] && ! [ -f "/var/www/$APPID-completed" ]; then

    # Go into apps directory
    cd /var/www/html/apps

    # Remove app directory
    if [ -d ./"$APPID" ]; then
        php -f ../occ app:disable "$APPID"
        rm -r ./"$APPID"
    fi

    # Clone repo
    if ! git clone https://github.com/nextcloud/"$APPID".git --branch "$BRANCH"; then
        echo "Could not clone the requested branch '$BRANCH' of the $APPID app. Does it exist?"
        exit 1
    fi
    
    # Go into app directory
    cd ./"$APPID"
    
    # Handle node versions
    if [ "$NODE_VERSION" = 14 ]; then
        nvm use --lts
    elif [ "$NODE_VERSION" = 16 ]; then
        nvm use 16.8.0
    else
        echo "No valid Node version provided."
        exit 1
    fi

    # Install apps
    if [ "$APPID" = logreader ]; then
        if ! make build/main.js; then
            echo "Could not compile the logreader app."
            exit 1
        fi
    elif [ "$APPID" = maps ]; then
        if ! make build; then
            echo "Could not compile the maps app."
            exit 1
        fi
    else
        if ! make dev-setup || ! make build-js-production; then
            echo "Could not compile the $APPID app."
            exit 1
        fi
    fi

    # Go into occ directory
    cd /var/www/html

    # Enable app
    if ! php -f occ app:enable "$APPID"; then
        echo "Could not enable the $APPID app."
        exit 1
    fi

    # The app was enabled
    touch "/var/www/$APPID-completed"
fi
}

# Compatible apps
install_enable_app "$CALENDAR_BRANCH" calendar 14
install_enable_app "$CONTACTS_BRANCH" contacts 14
install_enable_app "$FIRSTRUNWIZARD_BRANCH" firstrunwizard 14
install_enable_app "$LOGREADER_BRANCH" logreader 16
install_enable_app "$MAPS_BRANCH" maps 14
install_enable_app "$TALK_BRANCH" spreed 14
install_enable_app "$TASKS_BRANCH" tasks 16
install_enable_app "$TEXT_BRANCH" text 14
install_enable_app "$VIEWER_BRANCH" viewer 14

# Clear cache
cd /var/www/html
if ! php -f occ maintenance:repair; then
    echo "Could not clear the cache"
    exit 1
fi
