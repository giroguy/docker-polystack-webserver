FROM php:8.2-fpm-alpine
RUN docker-php-ext-install mysqli pdo pdo_mysql opcache
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp