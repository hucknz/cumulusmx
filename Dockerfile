#
# MXWeather Dockerfile
#
# Thanks to https://github.com/Optoisolated/MXWeather
#
# Notes: 
#
# In order to prevent docker from turning Cumulus.ini into a folder, you need to touch it first
# eg. touch ${DOCKERCONFDIR}/cumulusmx/Cumulus.ini
#
# To allow USB Weather Station Support (eg. FineOffset), add the following switch to the run command.
#            --device=/dev/hidraw0
#            hidraw0 would be the USB device as shown on the host machines /dev/hidraw* list.
#            If you have more than one USB device, you may need to change the number at the end
#            to the correct USB device ID. (eg. hidraw0, hidraw1, hidraw2)

# Weather data, logs, templates, and settings are persistent outside of the container

# Pull base image.
FROM ubuntu:20.04
LABEL Maintainer="hucknz"

# Config Info
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=ETC/UTC
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
RUN apt-get update && \
    apt-get install -y curl tzdata unzip libudev-dev git python3-virtualenv

# Install Mono
RUN apt-get update && \
    apt-get install -y curl && \
    rm -rf /var/lib/apt/lists/*
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF
RUN echo "deb http://download.mono-project.com/repo/ubuntu bionic/snapshots/5.20.1 main" > /etc/apt/sources.list.d/mono-xamarin.list && \
    apt-get update && \
    apt-get install -y mono-devel ca-certificates-mono fsharp mono-vbnc nuget && \
    rm -rf /var/lib/apt/lists/*

# Configure TZData
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Ensure CumulusMX Updates are acutally downloaded, and not cached
ARG CACHEBUST=1

# Download Latest CumulusMX
RUN \
  curl -L $(curl -s https://api.github.com/repos/cumulusmx/CumulusMX/releases/latest | grep browser_ | cut -d\" -f4) --output /tmp/CumulusMX.zip && \
  mkdir /opt/CumulusMX && \
  mkdir /opt/CumulusMX/publicweb && \
  unzip /tmp/CumulusMX.zip -d /opt && \
  chmod +x /opt/CumulusMX/CumulusMX.exe

# Save Template files prior to mounting web folder
RUN \
  mkdir /tmp/web && \
  cp -R /opt/CumulusMX/web/* /tmp/web/

# Define mountable directories.
VOLUME ["/opt/CumulusMX/data","/opt/CumulusMX/backup","/opt/CumulusMX/Reports","/var/log/nginx","/opt/CumulusMX/MXdiags","/opt/CumulusMX/publicweb","/opt/CumulusMX/web"]

# Copy the Web Service Files into the Published Web Folder
RUN cp -r /opt/CumulusMX/webfiles/* /opt/CumulusMX/publicweb/

# Add Start Script# Test File
COPY ./MXWeather.sh /opt/CumulusMX/

# Add Nginx Config
COPY ./nginx.conf /etc/nginx/
COPY ./MXWeather.conf /etc/nginx/sites-available/
RUN ln -s /etc/nginx/sites-available/MXWeather.conf /etc/nginx/sites-enabled/MXWeather.conf && \
  rm /etc/nginx/sites-enabled/default

WORKDIR /opt/CumulusMX/
RUN chmod +x /opt/CumulusMX/MXWeather.sh

CMD ["./MXWeather.sh"]

# Expose ports.
EXPOSE 80
EXPOSE 8998
