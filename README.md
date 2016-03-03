# misp docker image
Docker image contains MISP web app.  
For production use fine tuning of the configuration is still needed,  
but for playing around with app the image works fine.

## Build misp docker image
```
git clone git@github.com:eg5846/misp-docker.git
cd misp-docker
sudo docker build -t eg5846/misp-docker .

# Pushing image to registry.hub.docker.com is no longer required!!!
# Image build is automatically initiated after pushing commits of project to github.com
# sudo docker push eg5846/misp-docker
```

## Run misp docker image
Instance of mysql is needed before running misp web app.
```
sudo docker run -d -P --name mysql_misp eg5846/mysql-docker
sudo docker run -d -p 22 -p 8080:80 --link mysql_misp:mysql --name misp eg5846/misp-docker

# Show logs
sudo docker logs misp

# Fetch SSH port with 'sudo docker ps', default password is 'linux'
ssh -p 49153 root@localhost
```
mysql-docker offers the possibillity to put the database files to a volume on the docker host (see readme of project).

## Access web app
```
http://localhost:8080/
  user:     admin@admin.test
  password: admin 
```

## TODO
- Make apache2 logs accessable from outside (VOLUME, syslog, stdout, ...)
