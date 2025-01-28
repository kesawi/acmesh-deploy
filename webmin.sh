#!/usr/bin/bash

#A script to deploy an acme.sh generatyed certificate to a local webmmin server.

# Global vairables (either set here by uncommenting or in the environment before calling this script) 

#export DEPLOY_WEBMIN_DIR="/etc/webmin" # defaults to /etc/webmin
#export DEPLOY_WEBMIN_CERTNAME="miniserve.pem" # defaults to miniserve.pem
#export DEPLOY_WEBMIN_CA="intermediate.crt" # defaults to intermediate.crt
#export DEPLOY_WEBMIN_CMD="webmin restart" # defaults to service webmin restart
#export DEPLOY_WEBMIN_CONF="miniserv.conf" # defaults to miniserv.conf


########  Do not edit below this line #####################

#domain keyfile certfile cafile fullchain
webmin_deploy() {
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

  #Setting defaults
  _getdeployconf DEPLOY_WEBMIN_DIR
  if [ -z "$DEPLOY_WEBMIN_DIR" ]; then
    _target_directory="/etc/webmin"
  else
    _target_directory="$DEPLOY_WEBMIN_DIR"
    _savedeployconf DEPLOY_WEBMIN_DIR "$DEPLOY_WEBMIN_DIR"
  fi
  _debug2 DEPLOY_WEBMIN_DIR "$_target_directory"

  _getdeployconf DEPLOY_WEBMIN_CERTNAME
  if [ -z "$DEPLOY_WEBMIN_CERTNAME" ]; then
    _target_certificate="miniserv.pem"
  else
    _target_certificate="$DEPLOY_WEBMIN_CERTNAME"
    _savedeployconf DEPLOY_WEBMIN_CERTNAME "$DEPLOY_WEBMIN_CERTNAME"
  fi
  _debug2 DEPLOY_WEBMIN_CERTNAME "$_target_certificate"

  _getdeployconf DEPLOY_WEBMIN_CA
  if [ -z "$DEPLOY_WEBMIN_CA" ]; then
    _target_ca="intermediate.crt"
  else
    _target_ca="$DEPLOY_WEBMIN_CA"
    _savedeployconf DEPLOY_WEBMIN_CA "$DEPLOY_WEBMIN_CA"
  fi
  _debug2 DEPLOY_WEBMIN_CA "$_target_ca"

  _getdeployconf DEPLOY_WEBMIN_CMD
  if [ -z "$DEPLOY_WEBMIN_CMD" ]; then
    _target_cmd="service webmin restart"
  else
    _target_cmd="$DEPLOY_WEBMIN_CMD"
    _savedeployconf DEPLOY_WEBMIN_CMD "$DEPLOY_WEBMIN_CMD"
  fi
  _debug2 DEPLOY_WEBMIN_CMD "$_target_cmd"

  _getdeployconf DEPLOY_WEBMIN_CONF
  if [ -z "$DEPLOY_WEBMIN_CONF" ]; then
    _target_conf="miniserv.conf"
  else
    _target_conf="$DEPLOY_WEBMIN_CONF"
    _savedeployconf DEPLOY_WEBMIN_CONF "$DEPLOY_WEBMIN_CONF"
  fi
  _debug2 DEPLOY_WEBMIN_CONF "$_target_conf"


  # copy overwrite existing certificate
  cat $_ckey $_ccert > $_target_directory/$_target_certificate
    
  # copy intermediate certificate
  cp $_cca $_target_directory/$_target_ca
  
  # check for intermediate string setting in Webmin configuration file and update/add
  if grep -q "extracas" "$_target_directory/$_target_conf"; then
	sed -i "/extracas/c\\$_target_directory/$_target_ca" "$_target_directory/$_target_conf"
  else
	echo "extracas=$_target_directory/$_target_ca" >> "$_target_directory/$_target_conf"
  fi
  
  # restart webmin
  $_target_cmd
  _err_code="$?"
  if [ "$_err_code" != "0" ]; then
    _err "Error code $_err_code returned from restarting webmin"
  fi

  return $_err_code

}
