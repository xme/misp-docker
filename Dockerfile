#
# Dockerfile to build a MISP (https://github.com/MISP/MISP) container
#
# Original docker file by eg5846 (https://github.com/eg5846)
#
# 2016/03/03 - First release
# 
# To build your container:
#
# # git clone https://github.com/xme/misp-docker
# # docker build -t <tag> --build-arg MYSQL_ROOT_PASSWORD=<mysql_root_pw> .

# We are based on Ubuntu:latest
FROM ubuntu
MAINTAINER Xavier Mertens <xavier@rootshell.be>

# Set environment variables
ENV DEBIAN_FRONTEND noninteractive
ARG MYSQL_ROOT_PASSWORD

# Upgrade Ubuntu
RUN \
  apt-get update && \
  apt-get dist-upgrade -y && \
  apt-get autoremove -y && \
  apt-get clean

# Install Supervisor to manage processes required by MISP
RUN \
  apt-get install -y cron logrotate supervisor syslog-ng-core && \
  apt-get clean

# Modify syslog configuration
RUN \
  sed -i -E 's/^(\s*)system\(\);/\1unix-stream("\/dev\/log");/' /etc/syslog-ng/syslog-ng.conf

# Create default supervisor.conf
ADD supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Preconfigure setting for packages
RUN echo "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
RUN echo "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD" | debconf-set-selections
# Don't forget to reconfigure your postfix to match your env!
#RUN echo "postfix postfix/main_mailer_type string Local only" | debconf-set-selections 
#RUN echo "postfix postfix/mailname string localhost.localdomain" | debconf-set-selections
RUN echo 'postfix postfix/relayhost string smart.relay.tld.com' | debconf-set-selections
RUN echo 'postfix postfix/mynetworks string "127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128 192.168.0.0/16 172.16.0.0/12 10.0.0.0/8"' | debconf-set-selections

# Install packages
RUN \ 
  apt-get install -y apache2 curl git less libapache2-mod-php5 make mysql-client mysql-server php5-gd \
                     php5-mysql php5-dev php-pear postfix redis-server sudo tree vim zip openssl gnupg gnupg-agent && \
  apt-get clean

# -----------
# MySQL Setup
# -----------
VOLUME /var/lib/mysql

# -----------
# Redis Setup
# -----------
RUN sed -i 's/^\(daemonize\s*\)yes\s*$/\1no/g' /etc/redis/redis.conf

# Install PEAR packages
RUN \
  pear install Crypt_GPG && \
  pear install Net_GeoIP

# ---------------
# MISP Core Setup
# ---------------
RUN \
  cd /var/www && \
  git clone https://github.com/MISP/MISP.git

# Make git ignore filesystem permission differences
RUN \
  cd /var/www/MISP && \
  git config core.filemode false

# Install Mitre's STIX and its dependencies by running the following commands:
RUN \
  apt-get install -y python-dev python-pip libxml2-dev libxslt-dev zlib1g-dev && \
  cd /var/www/MISP/app/files/scripts && \
  git clone https://github.com/CybOXProject/python-cybox.git && \
  git clone https://github.com/STIXProject/python-stix.git && \
  cd /var/www/MISP/app/files/scripts/python-cybox && \
  git checkout v2.1.0.12 && \
  python setup.py install && \
  cd /var/www/MISP/app/files/scripts/python-stix && \
  git checkout v1.1.1.4 && \
  python setup.py install

# CakePHP is now included as a submodule of MISP, execute the following commands to let git fetch it
RUN \
  cd /var/www/MISP && \
  git submodule init && \
  git submodule update

# Once done, install the dependencies of CakeResque if you intend to use the built in background jobs
RUN \
  cd /var/www/MISP/app && \
  curl -s https://getcomposer.org/installer | php && \
  php composer.phar require kamisama/cake-resque:4.1.2 && \
  php composer.phar config vendor-dir Vendor && \
  php composer.phar install

# CakeResque normally uses phpredis to connect to redis, but it has a (buggy) fallback connector through Redisent. 
# It is highly advised to install phpredis
RUN pecl install redis
RUN apt-get install -y php5-redis

# After installing it, enable it in your php.ini file
# add the following line
# DISABLED: Module already enabled by the package php5-redis (generates crontab errors)
#RUN echo "extension=redis.so" >> /etc/php5/apache2/php.ini

# Set the recommended PHP defaults for MISP
RUN \
  sed -i -E "s/^max_execution_time.*$/max_execution_time = 300/" /etc/php5/apache2/php.ini && \
  sed -i -E "s/^memory_limit.*$/memory_limit = 512M/" /etc/php5/apache2/php.ini && \
  sed -i -E "s/^upload_max_filesize.*$/upload_max_filesize = 50M/" /etc/php5/apache2/php.ini && \
  sed -i -E "s/^post_max_size.*$/post_max_size = 50M/" /etc/php5/apache2/php.ini 

# To use the scheduler worker for scheduled tasks, do the following
RUN cp -fa /var/www/MISP/INSTALL/setup/config.php /var/www/MISP/app/Plugin/CakeResque/Config/config.php

# Check if the permissions are set correctly using the following commands as root
RUN \
  chown -R www-data:www-data /var/www/MISP && \
  chmod -R 750 /var/www/MISP && \
  cd /var/www/MISP/app && \
  chmod -R g+ws tmp && \
  chmod -R g+ws files && \
  chmod -R g+ws files/scripts/tmp

# ------------
# Apache Setup
# ------------

RUN cp /var/www/MISP/INSTALL/apache.misp.ubuntu /etc/apache2/sites-available/misp.conf
RUN a2dissite 000-default
RUN a2ensite misp

# Enable modules
RUN a2enmod rewrite
RUN a2enmod ssl

# Generate a self-signed certificate 
# Replace it asap by your own!
RUN \
  mkdir -p /etc/apache2/ssl && \
  cd /etc/apache2/ssl && \
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout misp.key -out misp.crt -batch

# Enable SSL on the vhost
RUN \
  sed -i -E "s/\VirtualHost\s\*:80/VirtualHost *:443/" /etc/apache2/sites-enabled/misp.conf && \
  sed -i -E "s/ServerSignature\sOff/ServerSignature Off\n\tSSLEngine On\n\tSSLCertificateFile \/etc\/apache2\/ssl\/misp.crt\n\tSSLCertificateKeyFile \/etc\/apache2\/ssl\/misp.key/" /etc/apache2/sites-enabled/misp.conf

# ------------------
# MISP Configuration
# ------------------
ADD gpg/.gnupg /var/www/MISP/.gnupg
RUN \
  chown -R www-data:www-data /var/www/MISP/.gnupg && \
  chmod 700 /var/www/MISP/.gnupg && \
  chmod 0600 /var/www/MISP/.gnupg/*

ADD gpg/gpg.asc /var/www/MISP/app/webroot/gpg.asc

RUN \
  chown -R www-data:www-data /var/www/MISP/app/webroot/gpg.asc && \
  chmod 0644 /var/www/MISP/app/webroot/gpg.asc

# Create boostrap.php
RUN \
  cp /var/www/MISP/app/Config/bootstrap.default.php /var/www/MISP/app/Config/bootstrap.php && \
  chown www-data:www-data /var/www/MISP/app/Config/bootstrap.default.php && \
  chmod 0750 /var/www/MISP/app/Config/bootstrap.default.php

# Create a config.php
RUN \
  cp /var/www/MISP/app/Config/config.default.php /var/www/MISP/app/Config/config.php && \
  chown www-data:www-data /var/www/MISP/app/Config/config.php && \
  chmod 0750 /var/www/MISP/app/Config/config.php

# Replace the default salt
RUN \
  cd /var/www/MISP/app/Config && \
  sed -i -E "s/'salt'\s=>\s'(\S+)'/'salt' => '`openssl rand -base64 32|tr "/" "-"`'/" config.php

# -----------------
# Supervisord Setup
# -----------------
RUN \
  echo '' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo '[program:mysql]' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'process_name = mysqld_safe' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'directory = /var/lib/mysql' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'command = /usr/bin/mysqld_safe' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'startsecs = 0' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'autorestart = false' >> /etc/supervisor/conf.d/supervisord.conf

RUN \
  echo '' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo '[program:postfix]' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'process_name = master' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'directory = /etc/postfix' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'command = /usr/sbin/postfix -c /etc/postfix start' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'startsecs = 0' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'autorestart = false' >> /etc/supervisor/conf.d/supervisord.conf

RUN \
  echo '' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo '[program:redis-server]' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'command=redis-server /etc/redis/redis.conf' >> /etc/supervisor/conf.d/supervisord.conf

RUN \
  echo '' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo '[program:apache2]' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'command=/bin/bash -c "source /etc/apache2/envvars && exec /usr/sbin/apache2 -D FOREGROUND"' >> /etc/supervisor/conf.d/supervisord.conf

RUN \
  echo '' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo '[program:resque]' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'command=/bin/bash /var/www/MISP/app/Console/worker/start.sh' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'user = www-data' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'startsecs = 0' >> /etc/supervisor/conf.d/supervisord.conf && \
  echo 'autorestart = false' >> /etc/supervisor/conf.d/supervisord.conf

# Add run script
ADD run.sh /run.sh
RUN chmod 0755 /run.sh

# Trigger to perform first boot operations
RUN touch /.firstboot.tmp

EXPOSE 443
CMD ["/run.sh"]
