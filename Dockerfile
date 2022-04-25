# From https://github.com/juliushaertl/nextcloud-docker-dev/blob/master/docker/Dockerfile.php74
FROM ghcr.io/juliushaertl/nextcloud-dev-php74:latest

# Get other dependencies
RUN apt-get update; \
    apt-get install -y --no-install-recommends \
        openssl \
        vim \
        openssh-client \
        jq \
        rsync \
    ; \
    rm -rf /var/lib/apt/lists/*

# Install composer
COPY --from=composer:1 /usr/bin/composer /usr/local/bin/composer

# Generate self signed certificate
RUN mkdir -p /certs && \
    cd /certs && \
    openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 -subj "/C=DE/ST=BE/L=Local/O=Dev/CN=localhost" -keyout ./ssl.key -out ./ssl.crt && \
    chmod -R +r ./

# Remove default ports
RUN rm /etc/apache2/ports.conf; \
    sed -s -i -e "s/Include ports.conf//" /etc/apache2/apache2.conf; \
    sed -i "/^Listen /d" /etc/apache2/apache2.conf

# Enable apache mods
RUN a2enmod rewrite \
    headers \
    proxy \
    proxy_fcgi \
    setenvif \
    env \
    mime \
    dir \
    authz_core \
    alias \
    ssl

# Copy apache conf
COPY apache.conf /etc/apache2/sites-available/nextcloud.conf

# Adjust apache sites
RUN a2dissite 000-default && a2dissite default-ssl && a2ensite nextcloud.conf

# Copy start script
COPY start.sh /usr/bin/
RUN chmod +x /usr/bin/start.sh

# Prepare nvm dir
ENV NVM_DIR=/opt/nvm
RUN mkdir -p "$NVM_DIR"

# Correctly set rights
RUN chown www-data:www-data -R /var/www "$NVM_DIR"

# Install NVM and node lts (including latest npm)
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash \
    && . "$NVM_DIR/nvm.sh" \
    && nvm install --lts --latest-npm

# Set entrypoint
ENTRYPOINT ["start.sh"]

# Set CMD
CMD ["apache2-foreground"]
