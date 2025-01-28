#!/usr/bin/bash

# This script is an acme.sh deployment script for Plex Media Server
# It will deploy the certificate to the Plex Media Server and then reload the service

# Global vairables (either set here by uncommenting or in the environment before calling this script)

# Your PFX file password/key
#DEPLOY_PLEX_P12PASS='<password>'

# The location that you want to deploy the certificate to that your Plex Media Server can access
# If using docker, then this assumed the volume /config is mapped to /var/lib/plexmediaserver
#DEPLOY_PLEX_CERT_LIBRARY='/var/lib/plexmediasever'

# The command to restart your Plex Media Server (if using docker then you can use 'docker restart plexcontainername')
#DEPLOY_PLEX_RELOAD='systemctl restart plexmediaserver'


#### Do not edit below this line ####

plex_deploy() {
	_cdomain="$1"
	_ckey="$2"
	_ccert="$3"
	_cca="$4"
	_cfullchain="$5"

	_debug _cdomain "$_cdomain"
	_debug _ckey "$_ckey"
	_debug _ccert "$_ccert"
	_debug _cca "$_cca"
	_debug _cfullchain "$_cfullchain"

	_getdeployconf DEPLOY_PLEX_P12PASS
	_getdeployconf DEPLOY_PLEX_CERT_LIBRARY
	_getdeployconf DEPLOY_PLEX_RELOAD

	_debug2 DEPLOY_PLEX_P12PASS "$DEPLOY_PLEX_P12PASS"
	_debug2 DEPLOY_PLEX_CERT_LIBRARY "$DEPLOY_PLEX_CERT_LIBRARY"
	_debug2 DEPLOY_PLEX_RELOAD "$DEPLOY_PLEX_RELOAD"

	_reload_cmd=$DEPLOY_PLEX_RELOAD

	# Check if deployment path exists
	if [ ! -d $DEPLOY_PLEX_CERT_LIBRARY ]; then
		_err "Certificate deployment path doesn't exist"
		return 1
	fi

	# Flag to track errors
	ERROR_FLAG=false

	DEPLOY_P12_FILE="$DEPLOY_PLEX_CERT_LIBRARY/$_cdomain.pfx"

	
	cp $_import_pkcs12 $DEPLOY_P12_FILE || { _err "Error copying pkcs12 file"; ERROR_FLAG=true; }

	# Restart Plex Media Server if no errors encountered
	if [ "$ERROR_FLAG" = false ]; then
		_info "Reload services (this may take some time): $_reload_cmd"
		if eval "$_reload_cmd"; then
			_info "Reload success!"
		else
			ERROR_FLAG=true
			_err "Reload error"
			return 1
		fi
	fi

	# Check if any errors occurred during processing
	if [ "$ERROR_FLAG" = true ]; then
		_err "Plex Media Server deploy script failed with errors."
		return 1
	fi

	# Successful, so save all (non-default) config:
	_savedeployconf DEPLOY_PLEX_P12PASS "$DEPLOY_PLEX_P12PASS"
	_savedeployconf DEPLOY_PLEX_CERT_LIBRARY "$DEPLOY_PLEX_CERT_LIBRARY"
	_savedeployconf DEPLOY_PLEX_RELOAD "$DEPLOY_PLEX_RELOAD"

	return 0

}