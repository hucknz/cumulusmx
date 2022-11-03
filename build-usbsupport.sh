#!/bin/bash
cd /.config/appdata/mxweather
docker stop mxweather && docker rm mxweather
docker build -t ubuntu:mxweather . --build-arg CACHEBUST=$(date +%s)
docker run --name=mxweather -p 8998:8998 -p 80:80 \
  -v /.config/appdata/mxweather/data:/opt/CumulusMX/data \
  -v /.config/appdata/mxweather/backup:/opt/CumulusMX/backup \
  -v /.config/appdata/mxweather/log:/var/log/nginx \
  -v /.config/appdata/mxweather/MXdiags:/opt/CumulusMX/MXdiags \
  -v /.config/appdata/mxweather/config:/opt/CumulusMX/config \
  -v /.config/appdata/mxweather/publicweb:/opt/CumulusMX/publicweb \
  --device=/dev/hidraw0  \
  --restart=unless-stopped \
  -d ubuntu:mxweather
cp -n /.config/appdata/mxweather/overload/favicon.ico /.config/appdata/mxweather/publicweb/
docker stop mxweather && sleep 5 && docker start mxweather
