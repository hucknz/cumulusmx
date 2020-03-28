#
# MXWeather Dockerfile
#
# https://github.com/Optoisolated/MXWeather
#
# Note: in order to prevent docker from turning Cumulus.ini into a folder, you need to touch it first
# eg. touch /opt/MXWeather/Cumulus.ini
# To build:  docker build -t ubuntu:MXWeather .
# To run:    docker run --name=MXWeather -p 8998:8998 -p 8080:80 -v /opt/MXWeather/data:/opt/CumulusMX/data -v /opt/MXWeather/backup:/opt/CumulusMX/backup -v /opt/MXWeather/log:/var/log/nginx -v /opt/MXWeather/Cumulus.ini:/opt/CumulusMX/Cumulus.ini --privileged --device=/dev/usb:/dev/usb -d ubuntu:MXWeather
# Weather data, logs, and settings are persistent outside of the container

# Pull base image.
FROM ubuntu
LABEL Maintainer="Optoisolated"

# Config Info
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Australia/Brisbane
SHELL ["/bin/bash", "-c"]

# Install Nginx.
RUN \
  apt-get update && \
  apt-get install -y software-properties-common && \
  add-apt-repository -y ppa:nginx/stable && \
  apt-get update && \
  apt-get install -y nginx && \
  rm -rf /var/lib/apt/lists/* && \
  echo "\ndaemon off;" >> /etc/nginx/nginx.conf && \
  chown -R www-data:www-data /var/lib/nginx

# Install Packages
RUN \
  apt-get update && \
  apt-get install -y mono-complete wget curl tzdata unzip libudev-dev git python-virtualenv
  
# Configure TZData
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Download Latest CumulusMX
RUN \
  LATEST_RELEASE=$(curl -L -s -H 'Accept: application/json' https://github.com/cumulusmx/CumulusMX/releases/latest) && \
  LATEST_VERSION=$(echo $LATEST_RELEASE | sed -e 's/.*"tag_name":"\([^"]*\)".*/\1/') && \
  CUMULUS_ZIP="CumulusMXDist${LATEST_VERSION:4,1}.zip" && \
  ARTIFACT_URL="https://github.com/cumulusmx/CumulusMX/releases/download/$LATEST_VERSION/$CUMULUS_ZIP" && \
  wget $ARTIFACT_URL -P /tmp && \
  mkdir /opt/CumulusMX && \ 
  unzip /tmp/$CUMULUS_ZIP -d /opt && \
  chmod +x /opt/CumulusMX/CumulusMX.exe

# Define mountable directories.
VOLUME ["/opt/CumulusMX/data","/opt/CumulusMX/backup","/opt/CumulusMX/Reports","/var/log/nginx"]

# Test File
COPY ./index.htm /opt/CumulusMX/web/

# Add Start Script
COPY ./MXWeather.sh /opt/CumulusMX/

# Add Nginx Config
COPY ./nginx.conf /etc/nginx/
COPY ./MXWeather.conf /etc/nginx/sites-available/
RUN ln -s /etc/nginx/sites-available/MXWeather.conf /etc/nginx/sites-enabled/MXWeather.conf && \
  rm /etc/nginx/sites-enabled/default

WORKDIR /opt/CumulusMX/
RUN chmod +x /opt/CumulusMX/MXWeather.sh

CMD ["./MXWeather.sh"]

# How to bail
#STOPSIGNAL SIGTERM

# Expose ports.
EXPOSE 80
EXPOSE 8998