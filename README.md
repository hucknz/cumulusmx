# MXWeather

This repo is the files required to build CumulusMX into a Docker container.

## Usage
Clone the repo into a folder (I generally use /opt/MXWeather/) on the Docker host.

### For USB Weather Stations (including FineOffset)
Run the following commands to prepare and start the container:
* `cd /opt/MXWeather`
* `touch Cumulus.ini`
* `docker build -t ubuntu:MXWeather .`
* `docker run --name=MXWeather -p 8998:8998 -p 8080:80 -v /opt/MXWeather/data:/opt/CumulusMX/data -v /opt/MXWeather/backup:/opt/CumulusMX/backup -v /opt/MXWeather/log:/var/log/nginx -v /opt/MXWeather/Cumulus.ini:/opt/CumulusMX/Cumulus.ini --device=/dev/hidraw0 -d ubuntu:MXWeather`

### For non-USB Weather Stations (TCP, HTTP or no Station)
Run the following commands to prepare and start the container:
* `cd /opt/MXWeather`
* `touch Cumulus.ini`
* `docker build -t ubuntu:MXWeather .`
* `docker run --name=MXWeather -p 8998:8998 -p 8080:80 -v /opt/MXWeather/data:/opt/CumulusMX/data -v /opt/MXWeather/backup:/opt/CumulusMX/backup -v /opt/MXWeather/log:/var/log/nginx -v /opt/MXWeather/Cumulus.ini:/opt/CumulusMX/Cumulus.ini -d ubuntu:MXWeather`

## Known Issues:
* If a /dev/hidraw0 device is not present the service will fail to start. This was added to the ./update.sh to support the FineOffset weather station I use. 
  If you don't use this weather station (or a USB station at all) you wont need this, so remove the --device=/dev/hidraw0 from the docker run statement.

## TODO:
* Need to build a Docker-create.yml. 
* Stack container images.
* Usage examples for different weather station configurations.
