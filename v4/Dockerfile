#
# Cumulus MX Dockerfile
#
# Thanks to https://github.com/Optoisolated/MXWeather

# Pull base image
FROM mcr.microsoft.com/dotnet/runtime:8.0
LABEL Maintainer="hucknz"

# Config Info
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=ETC/UTC
SHELL ["/bin/bash", "-c"]

# Install required packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends nginx curl tzdata unzip libudev-dev expect && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Configure NGINX and TZData
RUN echo "\ndaemon off;" >> /etc/nginx/nginx.conf && \
    chown -R www-data:www-data /var/lib/nginx && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone

# Ensure Cumulus MX Updates are acutally downloaded, and not cached
ARG CACHEBUST=1

# Download Latest Cumulus MX
RUN curl -L $(curl -s https://api.github.com/repos/cumulusmx/CumulusMX/releases/latest | grep browser_ | cut -d\" -f4) --output /tmp/CumulusMX.zip && \
    mkdir -p /opt/CumulusMX/publicweb /tmp/web && \
    unzip /tmp/CumulusMX.zip -d /opt/ && \
    chmod +x /opt/CumulusMX/CumulusMX.exe && \
    cp -R /opt/CumulusMX/web/* /tmp/web/ && \
    cp -r /opt/CumulusMX/webfiles/* /opt/CumulusMX/publicweb/

# Define mountable directories
VOLUME ["/opt/CumulusMX/data","/opt/CumulusMX/backup","/opt/CumulusMX/Reports","/var/log/nginx","/opt/CumulusMX/MXdiags","/opt/CumulusMX/publicweb","/opt/CumulusMX/web"]

# Add Start Script# Test File
COPY ./MXWeather.sh /opt/CumulusMX/

# Add Nginx Config
COPY ./nginx.conf /etc/nginx/
COPY ./MXWeather.conf /etc/nginx/sites-available/
RUN ln -s /etc/nginx/sites-available/MXWeather.conf /etc/nginx/sites-enabled/MXWeather.conf && \
    rm /etc/nginx/sites-enabled/default

WORKDIR /opt/CumulusMX/
RUN chmod +x MXWeather.sh

# Expose ports
EXPOSE 80
EXPOSE 8998

CMD ["./MXWeather.sh"]
