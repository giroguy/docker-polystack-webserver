# Pin the exact patch release so a rebuild never silently picks up an unpatched image.
# Bump this when PHP ships a security release (see https://www.php.net/releases/).
FROM php:8.2.35-fpm-alpine
RUN docker-php-ext-install mysqli pdo pdo_mysql opcache
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp
