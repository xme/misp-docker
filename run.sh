#!/bin/bash

set -e

if [ -r /.firstboot.tmp ]; then

	echo "Initial docker configuration, please be patient ..."

	# Set MYSQL_ROOT_PASSWORD
	if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
		echo "MYSQL_ROOT_PASSWORD is not set, use default value 'root'"
		MYSQL_ROOT_PASSWORD=root
	else
		echo "MYSQL_ROOT_PASSWORD is set to '$MYSQL_ROOT_PASSWORD'" 
	fi

	# Set MYSQL_MISP_PASSWORD
	if [ -z "$MYSQL_MISP_PASSWORD" ]; then
		echo "MYSQL_MISP_PASSWORD is not set, use default value 'misp'"
		MYSQL_MISP_PASSWORD=misp
	else
		echo "MYSQL_MISP_PASSWORD is set to '$MYSQL_MISP_PASSWORD'"
	fi

	# Create a database and user  
	echo "Connecting to database ..."

	# Ugly but we need MySQL temporary up for the setup phase...
	service mysql start >/dev/null 2>&1
	sleep 5

	ret=`echo 'SHOW DATABASES;' | mysql -u root --password="$MYSQL_ROOT_PASSWORD" -h 127.0.0.1 -P 3306 # 2>&1`

	if [ $? -eq 0 ]; then
		echo "Connected to database successfully!"
		found=0
		for db in $ret; do
			if [ "$db" == "misp" ]; then
				found=1
			fi    
		done
		if [ $found -eq 1 ]; then
			echo "Database misp found"
		else
			echo "Database misp not found, creating now one ..."
			cat > /tmp/create_misp_database.sql <<-EOSQL
create database misp;
grant usage on *.* to misp identified by "$MYSQL_MISP_PASSWORD";
grant all privileges on misp.* to misp;
EOSQL
			ret=`mysql -u root --password="$MYSQL_ROOT_PASSWORD" -h 127.0.0.1 -P 3306 2>&1 < /tmp/create_misp_database.sql`
			if [ $? -eq 0 ]; then
				echo "Created database misp successfully!"

				echo "Importing /var/www/MISP/INSTALL/MYSQL.sql ..."
				ret=`mysql -u misp --password="$MYSQL_MISP_PASSWORD" misp -h 127.0.0.1 -P 3306 2>&1 < /var/www/MISP/INSTALL/MYSQL.sql`
				if [ $? -eq 0 ]; then
					echo "Imported /var/www/MISP/INSTALL/MYSQL.sql successfully"
				else
					echo "ERROR: Importing /var/www/MISP/INSTALL/MYSQL.sql failed:"
					echo $ret
				fi
				service mysql stop >/dev/null 2>&1
			else
				echo "ERROR: Creating database misp failed:"
				echo $ret
			fi    
		fi
	else
		echo "ERROR: Connecting to database failed:"
		echo $ret
	fi

	# MISP configuration
	echo "Creating MISP configuration files ..."
	cd /var/www/MISP/app/Config
	cp -a database.default.php database.php
	sed -i "s/localhost/127.0.0.1/" database.php
	sed -i "s/db\s*login/misp/" database.php
	sed -i "s/8889/3306/" database.php
	sed -i "s/db\s*password/$MYSQL_MISP_PASSWORD/" database.php

	cp -a core.default.php core.php

	chown -R www-data:www-data /var/www/MISP/app/Config
	chmod -R 750 /var/www/MISP/app/Config

	# Fix the base url
	if [ -z "$MISP_BASEURL" ]; then
		echo "No base URL defined, don't forget to define it manually!"
	else
		echo "Fixing the MISP base URL ($MISP_BASEURL) ..."
		sed -i "s/'baseurl' => '',/'baseurl' => '$MISP_BASEURL',/" /var/www/MISP/app/Config/config.php
	fi

	# Fix php.ini with recommended settings
	echo "Optimizing php.ini (based on MISP recommendations) ..."
	sed -i "s/max_execution_time = 30/max_execution_time = 300/" /etc/php/7.0/apache2/php.ini
	sed -i "s/memory_limit = 128M/memory_limit = 512M/" /etc/php/7.0/apache2/php.ini
	sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 50M/" /etc/php/7.0/apache2/php.ini
	sed -i "s/post_max_size = 8M/post_max_size = 50M/" /etc/php/7.0/apache2/php.ini

	# Generate the admin user PGP key
	if [ -z "$MISP_ADMIN_EMAIL" -o -z "$MISP_ADMIN_PASSPHRASE" ]; then
		echo "No admin details provided, don't forget to generate the PGP key manually!"
	else
		echo "Generating admin PGP key ... (please be patient, we need some entropy)"
		cat >/tmp/gpg.tmp <<GPGEOF
%echo Generating a basic OpenPGP key
Key-Type: RSA
Key-Length: 2048
Name-Real: MISP Admin
Name-Email: $MISP_ADMIN_EMAIL
Expire-Date: 0
Passphrase: $MISP_ADMIN_PASSPHRASE
%commit
%echo Done
GPGEOF
		sudo -u www-data gpg --homedir /var/www/MISP/.gnupg --gen-key --batch /tmp/gpg.tmp >/dev/null 2>&1
		rm -f /tmp/gpg.tmp
	fi

	# Display tips
	cat <<__WELCOME__
Congratulations!
Your MISP docker has been successfully booted for the first time.
Don't forget:
- Reconfigure postfix to match your environment
- Change the MISP admin email address to $MISP_ADMIN_EMAIL

__WELCOME__
	rm -f /.firstboot.tmp
fi

# Start supervisord 
echo "Starting supervisord..."
cd /
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
