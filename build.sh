#!/bin/bash
cd /opt/MXWeather
docker stop MXWeather && docker rm MXWeather
docker build -t ubuntu:MXWeather . --build-arg CACHEBUST=$(date +%s)
docker run --name=MXWeather -p 8998:8998 -p 80:80 \
  -v /opt/MXWeather/data:/opt/CumulusMX/data \
  -v /opt/MXWeather/backup:/opt/CumulusMX/backup \
  -v /opt/MXWeather/log:/var/log/nginx \
  -v /opt/MXWeather/MXdiags:/opt/CumulusMX/MXdiags \
  -v /opt/MXWeather/config:/opt/CumulusMX/config \
  -v /opt/MXWeather/publicweb:/opt/CumulusMX/publicweb \
  -d ubuntu:MXWeather
cp -n /opt/MXWeather/overload/favicon.ico /opt/MXWeather/publicweb/
docker stop MXWeather && sleep 5 && docker start MXWeather
