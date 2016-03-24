MISP Docker
===========

The files in this repository are used to create a Docker container running a [MISP](http://www.misp-project.org) ("Malware Information Sharing Platform") instance.

All the required components (MySQL, Apache, Redis, ...) are running in a single Docker. At first run, most of the setup is automated but some small steps must be performed manually after the initial run.

The build is based on Ubuntu and will install all the required components. The following configuration steps are performed automatically:
* Reconfiguration of the base URL in `config.php`
* Generation of a new salt in `config.php`
* Generation of a self-signed certificate and reconfiguration of the vhost to offer SSL support
* Optimization of the PHP environment (php.ini) to match the MISP recommended values
* Creation of the MySQL database
* Generation of the admin PGP key

# Building the image

```
# git clone https://github.com/xme/misp-docker
# cd misp-docker
# docker build -t misp/misp --build-arg MYSQL_ROOT_PASSWORD=<mysql_root_pw> .
```
(Choose your MySQL root password at build time)

# Running the image

First, create a configuration file which will contain your MySQL passwords:
```
# cat env.txt
MYSQL_ROOT_PASSWORD=my_strong_root_pw
MYSQL_MISP_PASSWORD=my_strong_misp_pw
MISP_ADMIN_EMAIL=admin@admin.test
MISP_ADMIN_PASSPHRASE=abc123
MISP_BASEURL=http:\/\/misp\.local
``` 
This file will help to customize your MISP instance.
* `MYSQL_*_PASSWORD` are used to configured accesses to the database server
* `MISP_ADMIN_EMAIL` is used to generate the PGP key (Don't forget to change it in the web interface)
* `MISP_ADMIN_PASSPHRASE` is the passphrase associated to the PGP key
* `MISP_BASEURL` is the URL that will be used to access the web interface. Please escape any caracters that could affect a regex.

Then boot the container:
```
# docker run -d -p 443:443 -v /dev/urandom:/dev/random --env-file=env.txt --restart=always --name misp misp/misp
```

Note: the volume mapping is /dev/urandom is required to generate enough entropy to create the PGP key.

# Post-boot steps

Once the container started, connect to it:
```
# docker exec -it misp bash
```
Then, perform the following steps:
* Change the admin email address to the one specify in your env.txt file
* Reconfigure the Postfix instance

# Usage

Point your browser to `https://<your-docker-server>`. The default credentials remain the same:  `admin@admin.test` with `admin` as password.
To use MISP, refer to the official documentation: https://github.com/MISP/MISP/blob/2.4/INSTALL/documentation.pdf
