# Pull base image
FROM mono:latest
LABEL Maintainer="hucknz"

# Config Info
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=ETC/UTC
SHELL ["/bin/bash", "-c"]

# Install required packages and configure NGINX and TZData
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nginx \
        curl \
        tzdata \
        unzip \
        libudev-dev \
        git \
        python3-virtualenv && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    echo "\ndaemon off;" >> /etc/nginx/nginx.conf && \
    chown -R www-data:www-data /var/lib/nginx && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone

# Ensure Cumulus MX Updates are actually downloaded, and not cached
ARG CACHEBUST=1

# Download and set up Latest Cumulus MX
RUN curl -L https://github.com/cumulusmx/CumulusMX/releases/download/b3283/CumulusMXDist3283a.zip --output /tmp/CumulusMX.zip && \
    mkdir -p /opt/CumulusMX/publicweb /tmp/web && \
    unzip /tmp/CumulusMX.zip -d /opt/ && \
    chmod +x /opt/CumulusMX/CumulusMX.exe && \
    cp -R /opt/CumulusMX/web/* /tmp/web/ && \
    cp -r /opt/CumulusMX/webfiles/* /opt/CumulusMX/publicweb/ && \
    rm /tmp/CumulusMX.zip

# Define mountable directories
VOLUME ["/opt/CumulusMX/data", "/opt/CumulusMX/backup", "/opt/CumulusMX/Reports", "/var/log/nginx", "/opt/CumulusMX/MXdiags", "/opt/CumulusMX/publicweb", "/opt/CumulusMX/web"]

# Add Start Script
COPY ./MXWeather.sh /opt/CumulusMX/

# Add Nginx Config
COPY ./nginx.conf /etc/nginx/
COPY ./MXWeather.conf /etc/nginx/sites-available/
RUN ln -s /etc/nginx/sites-available/MXWeather.conf /etc/nginx/sites-enabled/MXWeather.conf && \
    rm /etc/nginx/sites-enabled/default

WORKDIR /opt/CumulusMX/
RUN chmod +x MXWeather.sh

# Expose ports
EXPOSE 80 8998

CMD ["./MXWeather.sh"]