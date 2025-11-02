#
# Cumulus MX Dockerfile
#
# Thanks to https://github.com/Optoisolated/MXWeather

# Pull base image
FROM mcr.microsoft.com/dotnet/runtime:8.0
LABEL Maintainer="hucknz"

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=ETC/UTC
SHELL ["/bin/bash", "-c"]

# Install & configure packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends nginx curl tzdata unzip libudev-dev expect && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    echo "\ndaemon off;" >> /etc/nginx/nginx.conf && \
    chown -R www-data:www-data /var/lib/nginx

# Use CACHEBUST to ensure latest CumulusMX is downloaded
ARG CACHEBUST=1

# Download & install CumulusMX
RUN curl -L $(curl -s https://api.github.com/repos/cumulusmx/CumulusMX/releases/latest | grep browser_ | cut -d\" -f4) --output /tmp/CumulusMX.zip && \
    mkdir -p /opt/CumulusMX/publicweb /tmp/web && \
    unzip /tmp/CumulusMX.zip -d /opt/ && \
    chmod +x /opt/CumulusMX/CumulusMX.exe && \
    cp -R /opt/CumulusMX/web/* /tmp/web/ && \
    cp -r /opt/CumulusMX/webfiles/* /opt/CumulusMX/publicweb/ && \
    rm /tmp/CumulusMX.zip

# Define mountable directories
VOLUME ["/opt/CumulusMX/data", "/opt/CumulusMX/backup", "/opt/CumulusMX/Reports", "/var/log/nginx", "/opt/CumulusMX/MXdiags", "/opt/CumulusMX/publicweb", "/opt/CumulusMX/web"]

# Add start script & NGINX config
COPY ./MXWeather.sh /opt/CumulusMX/
COPY ./nginx.conf /etc/nginx/
COPY ./MXWeather.conf /etc/nginx/sites-available/

RUN ln -s /etc/nginx/sites-available/MXWeather.conf /etc/nginx/sites-enabled/MXWeather.conf && \
    rm /etc/nginx/sites-enabled/default && \
    chmod +x /opt/CumulusMX/MXWeather.sh

WORKDIR /opt/CumulusMX/

EXPOSE 80 8998

ENTRYPOINT ["./MXWeather.sh"]
