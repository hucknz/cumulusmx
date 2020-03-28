# MXWeather

This repo is the files required to build CumulusMX into a Docker container.

Clone the repo into a folder (I generally use /opt/MXWeather/) on the Docker host.
Run the following commands to prepare and start the container:
* cd /opt/MXWeather
* touch Cumulus.ini
* docker build -t ubuntu:MXWeather .
* docker run --name=MXWeather -p 8998:8998 -p 8080:80 -v /opt/MXWeather/data:/opt/CumulusMX/data -v /opt/MXWeather/backup:/opt/CumulusMX/backup -v /opt/MXWeather/log:/var/log/nginx -v /opt/MXWeather/Cumulus.ini:/opt/CumulusMX/Cumulus.ini --privileged --device=/dev/usb:/dev/usb -d ubuntu:MXWeather

Known Issues:
* Requires Privileged Level Access: 
The --privileged switch is required for the --device=/dev/usb:/dev/usb mapping to work correctly. Unfortunately while CumulusMX can see the USB devices in the container, it doesn't seem to be able to open the stream with out privileged access. 

