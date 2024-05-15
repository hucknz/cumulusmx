# Cumulus MX Weather Station app

## Overview
Cumulus MX is a cross platform version of the Cumulus weather station software. [Learn more](https://www.cumuluswiki.org/a/Main_Page) at the Cumulus wiki.

## Important changes for v4 ##

With the release of CumulusMX v4 there are breaking changes for the Docker containers. **Please read the warning below before moving to v4.** There is more detail regarding the changes available [here](https://cumulus.hosiene.co.uk/viewtopic.php?t=22051).

### Latest releases ###
"cumulusmx:v4-beta" is now available. This is currently being tested and will be rolled out to the v4 tag shortly. **Please be careful as this will migrate your data from v3 to v4. See warning below.** 

"cumulusmx:v4" will be available for all new releases going forward. This will automatically be updated as new versions are released.

The "cumulusmx:latest" tag will be moved to v4 once it is more stable. 

#### Warning ####
The v4 release includes an automatic migration from v3 to v4 data structure. **Please ensure you back up your data files before updating to v4. I can not guarantee the migration will work correctly for you and no support will be provided.**

### Version 3 ###
"cumulusmx:v3" will be available for version 3 builds. These will be updated monthly to avoid the containers going stale or security flaws being left open. 

## Usage
1. Ensure Docker is installed and configured on the host machine (I recommend using DockSTARTer if you want an easy way to get started with Docker)
2. Clone the docker-compose.yml and .env files to your local machine
3. Modify the .env file to suit your environment
4. Important: If you're not using USB passthrough make sure to remove the "devices" section from the docker-compose.yml file (see Known Issues)
5. Run `docker compose up` to start the container

## First Run
1. On the first run of CumulusMX the Installation wizard will need to be run. This can be started by navigating to the following `http://{serveraddress}:8998/wizard.html`
2. Once the wizard is completed, you will be prompted to restart Cumulus MX. Restart the container using the command `docker restart cumulusmx`
3. The restart will prompt the `Cumulus.ini` file to be written. At shutdown of the service, the Cumulus.ini file will be copied to the `./config` folder. When the container is restarted, the Cumulus.ini file will be copied back to the `/opt/CumulusMX` directory from the `/opt/CumulusMX/config` folder.

Note: config changes won't be committed to the INI file outside the container unless the container receives a SIGTERM. The config file is persistent inside the container until the container is rebuilt or updated.

## Known Issues:
* If using the docker compose file and `/dev/hidraw0` device is not present the container will fail to start.

# Container builds
The upstream repo for Cumulus MX is checked daily for new releases. When a new release is identified the build process should automatically trigger and commit a new build to https://hub.docker.com/r/hucknz/cumulusmx and https://ghcr.io/hucknz/cumulusmx. You can use the v3 or v4 tags to get the latest build of each version. 

# Thanks

Credit to [@optoisolated](https://github.com/optoisolated/MXWeather) for their initial work in containerising Cumulus MX. 
