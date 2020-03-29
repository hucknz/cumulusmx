# MXWeather

This repo is the files required to build CumulusMX into a Docker container.

## Usage
Clone the repo into a folder (I generally use /opt/MXWeather/) on the Docker host.
Run the following commands to prepare and start the container:
* `cd /opt/MXWeather`
* `touch Cumulus.ini`
* `docker build -t ubuntu:MXWeather .`
* `docker run --name=MXWeather -p 8998:8998 -p 8080:80 -v /opt/MXWeather/data:/opt/CumulusMX/data -v /opt/MXWeather/backup:/opt/CumulusMX/backup -v /opt/MXWeather/log:/var/log/nginx -v /opt/MXWeather/Cumulus.ini:/opt/CumulusMX/Cumulus.ini --device=/dev/hidraw0 -d ubuntu:MXWeather`

## Known Issues:
* None

## TODO:
* Need to build a Docker-create.yml. 
