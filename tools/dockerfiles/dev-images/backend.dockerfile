# ! Image
FROM php:8.0.6-fpm-alpine3.12

# ? Set Working Directory
WORKDIR /var/www/html

# ? Install Mysql Extensions
RUN docker-php-ext-install pdo pdo_mysql

# ? Install and enable PHP Redis extension
# ? Redis extension is not provided with the PHP Source
# ? pecl install will download and compile redis
# ? docker-php-ext-enable will enable it
# ? finally apk del to maintain a small image size
RUN apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
 && pecl install redis-5.3.4 \
 && docker-php-ext-enable redis \
 && apk del .build-deps

# ? Install & Configure gd
RUN apk add --no-cache freetype libpng libjpeg-turbo freetype-dev libpng-dev libjpeg-turbo-dev && \
  docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg \
  NPROC=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || 1) && \
  docker-php-ext-install -j$(nproc) gd && \
  apk del --no-cache freetype-dev libpng-dev libjpeg-turbo-dev

# ? Install git (required by Composer)
RUN apk add git

# *** Install Composer
RUN php -r "readfile('http://getcomposer.org/installer');" | php -- --install-dir=/usr/bin/ --filename=composer