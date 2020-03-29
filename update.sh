#!/bin/bash
cd /opt/MXWeather
docker stop MXWeather && docker rm MXWeather
docker build -t ubuntu:MXWeather .
docker run --name=MXWeather -p 8998:8998 -p 8080:80 -v /opt/MXWeather/data:/opt/CumulusMX/data -v /opt/MXWeather/backup:/opt/CumulusMX/backup -v /opt/MXWeather/log:/var/log/nginx -v /opt/MXWeather/Cumulus.ini:/opt/CumulusMX/Cumulus.ini --device=/dev/hidraw0 -d ubuntu:MXWeather
