# Cumulus MX Weather Station app

## Overview
Cumulus MX is a cross platform version of the Cumulus weather station software. [Learn more](https://www.cumuluswiki.org/a/Main_Page) at the Cumulus wiki.

## Important changes for v4 ##

Because of the breaking changes between v3 and v4 I've added a new tagging format. 

"cumulusmx:v4" will be available for all new releases going forward. This will automatically be updated as new versions are released. **The "cumulusmx:latest" tag will shift to v4 in July.** You can choose to use v4 by changing to that tag earlier if you'd prefer. 

"cumulusmx:v3" will remain available for version 3 builds. These will be updated monthly to avoid the containers going stale or security flaws being left open. 

### Data migration ###

v4 has a completely new data structure, therefore your files will need to be migrated. **The v4 release migrates from the v3 to the v4 data structure by default.** You can disable the migration by adding an environment variable "MIGRATE=false" to your docker-compose or "-e MIGRATE=false" for docker run. If you use Custom Daily log files you will need to pass a list of these through an environment variable too. See migration detail below for more information. 

**Please ensure you back up your data files before updating to v4. I can not guarantee the migration will work correctly for you.**

You can see the migration logic [below](#migration). There is more detail regarding the CumulusMX version changes available [here](https://cumulus.hosiene.co.uk/viewtopic.php?t=22051).

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

# Migration
For v4 there is a new data structure. The v4 container will automatically migrate unless told not to. 

You can disable the migration by adding an environment variable `MIGRATE=false` to your docker-compose or `-e MIGRATE=false` for docker run. 

You can also force a migration by setting `MIGRATE=force`. This can be useful if the migration failed first time. 

If you have Custom Daily log files you can pass these to the script by setting an environment variable `MIGRATE_CUSTOM_LOG_FILES="File1 File2 File3"`. **Note:** as I do not use custom log files this is untested and may not work correctly. 

## Migration logic

### Pre-checks

If any of these fails the migration will not proceed: 
1. Check if migration is disabled
2. Check if there is more than one file in the data directory
 a. If the migration is skipped a file `/config/.nodata` is created to indicate the migration has been skipped so that the migration is not run next time the container is started
3. Check if there has been a pre-existing migration

If `MIGRATION=force` is set then checks will be ignored and the migration will run

### Migration

1. The Cumulus.ini files is backed up to `/config/Cumulus-v3.ini.bak`
2. The data directory is backed up to `/backup/datav3`
3. The data directory is copied to `/datav3`
4. The migration process is run
5. Once the migration has run a file `/config/.migrated` is created to indicate the migration has been completed
6. CumulusMX will then start as usual

### Recovery

The migration process is designed to make the data recoverable but there is no guarantee provided. 

If you need to recover there should be a copy of the necessary files available in the following locations: 
1. Cumulus.ini should be located at /config/Cumulus-v3.ini.bak
2. The v3 data files should be available at /backups/datav3

Replacing `/config/Cumulus-v3.ini.bak` with `/config/Cumulus.ini` and copying `/backup/datav3/` to `/data/` **should** restore things back to v3. 

# Thanks

Credit to [@optoisolated](https://github.com/optoisolated/MXWeather) for their initial work in containerising Cumulus MX. 
