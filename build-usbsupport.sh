#!/bin/bash
cd /opt/MXWeather
docker stop MXWeather && docker rm MXWeather
docker build -t ubuntu:MXWeather .
docker run --name=MXWeather -p 8998:8998 -p 8080:80 \
  -v /opt/MXWeather/data:/opt/CumulusMX/data \
  -v /opt/MXWeather/backup:/opt/CumulusMX/backup \
  -v /opt/MXWeather/log:/var/log/nginx \
  -v /opt/MXWeather/MXdiags:/opt/CumulusMX/MXdiags \
  -v /opt/MXWeather/config:/opt/CumulusMX/config \
  -v /opt/MXWeather/publicweb:/opt/CumulusMX/publicweb \
  --device=/dev/hidraw0  \
  -d ubuntu:MXWeather
docker stop MXWeather && sleep 5 && docker start MXWeather
