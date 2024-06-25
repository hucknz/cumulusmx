#
# Cumulus MX Dockerfile
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

# Pull base image
FROM ubuntu:24.04
LABEL Maintainer="hucknz"

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=ETC/UTC
SHELL ["/bin/bash", "-c"]

# Install packages, configure packages then download and install CumulusMX
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    nginx mono-complete curl tzdata unzip libudev-dev git python3-virtualenv ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    echo "\ndaemon off;" >> /etc/nginx/nginx.conf && \
    chown -R www-data:www-data /var/lib/nginx && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    mkdir -p /opt/CumulusMX/publicweb /tmp/web && \
    curl -L https://github.com/cumulusmx/CumulusMX/releases/download/b3283/CumulusMXDist3283a.zip --output /tmp/CumulusMX.zip && \
    unzip /tmp/CumulusMX.zip -d /opt/ && \
    chmod +x /opt/CumulusMX/CumulusMX.exe && \
    cp -R /opt/CumulusMX/web/* /tmp/web/ && \
    cp -r /opt/CumulusMX/webfiles/* /opt/CumulusMX/publicweb/ && \
    rm /tmp/CumulusMX.zip && \
    rm /etc/nginx/sites-enabled/default

# Define mountable directories
VOLUME ["/opt/CumulusMX/data","/opt/CumulusMX/backup","/opt/CumulusMX/Reports","/var/log/nginx","/opt/CumulusMX/MXdiags","/opt/CumulusMX/publicweb","/opt/CumulusMX/web"]

# Add Start Script and Nginx Configs
COPY ./MXWeather.sh /opt/CumulusMX/
COPY ./nginx.conf /etc/nginx/
COPY ./MXWeather.conf /etc/nginx/sites-available/

# Create symlink for Nginx config after copying the file
RUN ln -s /etc/nginx/sites-available/MXWeather.conf /etc/nginx/sites-enabled/MXWeather.conf

WORKDIR /opt/CumulusMX/
RUN chmod +x MXWeather.sh

# Expose ports
EXPOSE 80 8998

CMD ["./MXWeather.sh"]