# Build stage
FROM ubuntu:24.04 AS builder
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=ETC/UTC

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Download and extract CumulusMX
ARG CACHEBUST=1
RUN curl -L https://github.com/cumulusmx/CumulusMX/releases/download/b3283/CumulusMXDist3283a.zip --output /tmp/CumulusMX.zip && \
    mkdir -p /opt/CumulusMX /tmp/web && \
    unzip /tmp/CumulusMX.zip -d /opt/ && \
    cp -R /opt/CumulusMX/web/* /tmp/web/ && \
    cp -r /opt/CumulusMX/webfiles/* /opt/CumulusMX/publicweb/ && \
    rm /tmp/CumulusMX.zip

# Final stage
FROM ubuntu:24.04
LABEL Maintainer="hucknz"

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=ETC/UTC
SHELL ["/bin/bash", "-c"]

# Install required packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nginx \
        mono-complete \
        tzdata \
        libudev-dev \
        git \
        python3-virtualenv && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    echo "\ndaemon off;" >> /etc/nginx/nginx.conf && \
    chown -R www-data:www-data /var/lib/nginx && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone

# Copy CumulusMX from builder stage
COPY --from=builder /opt/CumulusMX /opt/CumulusMX
COPY --from=builder /tmp/web /opt/CumulusMX/web

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
RUN chmod +x MXWeather.sh && chmod +x CumulusMX.exe

# Expose ports
EXPOSE 80 8998

CMD ["./MXWeather.sh"]