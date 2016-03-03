MISP Docker
===========

The file in this repository are used to create a Docker container with the MISP ("Malware Information Sharing Platform") application. 

All the required components (MySQL, Apache, Redis, ...) are running in a single docker. Most of the setup is performed automatically but some small steps must be performed manually after the initial run.

# Building the image:

```
# git clone https://github.com/xme/misp-docker
# cd misp-docker
# docker build -t misp/misp --build-arg MYSQL_ROOT_PASSWORD=<mysql_root_pw> .
```
(Choose your MySQL root password at build time)

The build is based on Ubuntu and will install all the components. The following extra steps are also performed:
* Generation of a new sald in config.php
* Generation of a self-signed certificate and reconfiguration of the vhost to offer SSL support

# Running the image

First, create a configuration file which will contains your MySQL passwords:
```
# cat env.txt
MYSQL_ROOT_PASSWORD=my_strong_root_pw
MYSQL_MISP_PASSWORD=my_strong_misp_pw
``` 
This file will help to create the MISP database.

Then boot the container:
```
# docker run -d -p 443:443 --env-file=env.txt --restart=always --name misp misp/misp
```

# Post-boot steps

Once the container started, connect to it:
```
# docker exec -it misp bash
```
Then, perform the following steps:
* Change 'baseurl' in config.php
* Reconfigure the Postfix instance

