# MXWeather

This repo is the files required to build CumulusMX into a Docker container.

## Usage
Ensure docker is installed and configured on the host machine
Clone the repo into a folder (I generally use `/opt/MXWeather/`) on the Docker host.

### For Standard Weather Stations (Accessed via HTTP/IP etc, or no station.)
Run the following commands to prepare and start the container:
* `mkdir /opt/MXWeather`
* `cd /opt/MXWeather`
* `./build.sh`

### For USB Weather Stations (eg. FineOffset)
Run the following commands to prepare and start the container:
* `mkdir /opt/MXWeather`
* `cd /opt/MXWeather`
* `./build-usbsupport.sh`

### First Run
On the first run of CumulusMX the Installation wizard will need to be run. This can be started by navigating to the following `http://{serveraddress}:8998/wizard.html`
Once the wizard is completed, you will be prompted to restart CumulusNX. Restart the container using the command `docker restart MXWeather`
The restart will prompt the `Cumulus.ini` file to be written. At shutdown of the service, the Cumulus.ini file will be copied to the `./config` folder.
When the container is restarted, the Cumulus.ini file will be copied back to the `/opt/CumulusMX` directory from the `/opt/CumulusMX/config` folder.

Note: config changes won't be committed to the INI file outside the container unless the container receives a SIGTERM. The config file is persistent inside the container until the container is rebuilt or updated.

### Public Website Generation
Once the Cumulus wizard deployment is completed, the website generation can be enabled. Once enabled, realtime/interval web pages will be rendered and available outside the container in the `./publicweb` folder. To enable this generation:
* Navigate to `http://{serveraddress}:8998/`
* Select `Settings | Internet Settings` from the menu
* Expand `Web/FTP Site` and select `Enable file copy of standard files`
* Set the Local copy destination folder path to `./publicweb/`
* Expand `Interval Configuration` and select `I want to use the supplied default website`
* Save the settings
* Expand `Interval Configuration` and verify that the normal interval settings and realtime interval settings are enabled.
* Expand `Moon Image` and verify that `Copy Moon image file` is checked. Then update the destination folder to `./publicweb/images/moon.png`
* Save the seittings.

The `/opt/MXWeather/publicweb` folder (once the schedules are reached) will contain the public web files which can then be published online. The publicweb is published locally as well for convenience on port 80 at `http://{serveraddress}/`. The port can be changed in the build script and Dockerfile if required.

## Known Issues:
* If using the USB build and `/dev/hidraw0` device is not present the container will fail to start. This was added to the `./build-usbsupport.sh` to support the FineOffset weather station I used to use. 
  If you don't use this weather station (or a USB station at all) you wont need this, in which case, use the `build.sh` build script.

## TODO:
* Stack container images.
* Publish in the DockerHub
* Usage examples for different weather station configurations.
 
## Resolved:
* ~MXdiags Log Passthrough~
* ~Resolve issues with INI Config handling~
