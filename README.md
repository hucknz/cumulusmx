# MXWeather

This repo is the files required to build CumulusMX into a Docker container.

## Usage
Ensure docker is installed and configured on the host machine
Clone the repo into a folder (I generally use /opt/MXWeather/) on the Docker host.

### For Standard Weather Stations (Accessed via HTTP/IP etc, or no station.)
Run the following commands to prepare and start the container:
* `cd /opt/MXWeather`
* `./build.sh`

### For USB Weather Stations (eg. FineOffset)
Run the following commands to prepare and start the container:
* `cd /opt/MXWeather`
* `./build-nousb.sh`

### First Run
On the first run of CumulusMX the Installation wizard will need to be run. This can be started by navigating to the following http://{serveraddress}:8998/wizard.html
Once the wizard is completed, you will be prompted to restart CumulusNX. Restart the container using the command `docker restart MXWeather`
The restart will prompt the Cumulus.ini file to be written. At shutdown of the service, the Cumulus.ini file will be copied to the /config folder.
When the container is restarted, the Cumulus.ini file will be copied back to the /opt/CumulusMX directory from the /opt/CumulusMX/config folder.
Note: config changes won't be committed to the INI file outside the container unless the container receives a SIGTERM. The config file is persistent inside the container until the container is rebuilt or updated.

## Known Issues:
* If a /dev/hidraw0 device is not present the service will fail to start. This was added to the ./update.sh to support the FineOffset weather station I use. 
  If you don't use this weather station (or a USB station at all) you wont need this, so remove the --device=/dev/hidraw0 from the docker run statement.

## TODO:
* Stack container images.
* ~MXdiags Log Passthrough~
* Usage examples for different weather station configurations.
* Resolve issues with INI Config handling
