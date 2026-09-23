FROM php:8.4-apache

# Without a php.ini, PHP's built-in default is display_errors=On, which prints
# warnings into responses (corrupting bencoded tracker replies)
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

# pdo_sqlite is compiled into the base image; the sqlite3 CLI is for docker-entrypoint.sh
RUN apt-get update \
	&& apt-get install -y --no-install-recommends sqlite3 \
	&& rm -rf /var/lib/apt/lists/*

# Allow .htaccess (e.g. sample.htaccess installed as .htaccess) to take effect
RUN a2enmod rewrite \
	&& sed -ri 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf

WORKDIR /var/www/html

COPY index.php COPYING.txt README.md ./
COPY static/ ./static/
COPY sample.htaccess ./.htaccess
COPY docker-entrypoint.sh /usr/local/bin/

# Store the database outside the web root (avoids relying solely on .htaccess to
# block downloads of it, per the README's security recommendation) and point
# index.php's PDO DSN at it.
RUN mkdir -p /var/www/data \
	&& sed -i 's#sqlite:ipmagnet.db3#sqlite:/var/www/data/ipmagnet.db3#' index.php \
	&& chmod +x /usr/local/bin/docker-entrypoint.sh \
	&& chown -R www-data:www-data /var/www/html /var/www/data

VOLUME ["/var/www/data"]

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
