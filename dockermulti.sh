#!/usr/bin/bash

# About this script
#
# This script will deploy a single certificate to multiple docker continers
# where the certificate domain matches the container label sh.acme.autoload.domain
#
# It will then read a series of container labels as noted below to determine 
# the format of the private key and certificates required by the container, the
# path tothe private key and certificates in the container, and the filenames
# for the private key and certtificate in the container.
#
# The only global variable required from the user is the P12 password where this
# is used (DEPLOY_DOCKERMULTI_CONTAINER_P12PASS).
# 
# Use the label sh.acme.autoload.certtype to specify the type of certificate
# files to be generated from one of the following:
# - p12: Generate a PKCS12 file
# - ca: Generate separate key, cert, and ca files
# - all: Generate separate key, cert, ca, and fullchain files
# - cert: Generate separate key and cert files
# - fullchain: Generate separate key and fullchain files
# - bundledchain: Generate a bundled key file containing the key and fullchain files
# - bundledcert: Generate a bundled key file containing the key and cert files
# - bundledca: Generate a bundled key file containing the key, cert and ca files
# - crashplan: Generate separate key and fullchain files, and a bundled file containing
#              the key and fullchain files (this has been added to support the docker image "jlesage/crashplan-pro")
#
# p12 requires the following labels:
# - sh.acme.autoload.certpath: The path to the PKCS12 files within the container (default is /config)
# - sh.acme.autoload.p12name: The name of the PKCS12 file to be created
#
# ca requires the following labels:
# - sh.acme.autoload.certpath: The path to the certificate files within the container (default is /config)
# - sh.acme.autoload.keyname: The name of the key file to be created
# - sh.acme.autoload.certname: The name of the cert file to be created
# - sh.acme.autoload.caname: The name of the ca file to be created
#
# all requires the following labels:
# - sh.acme.autoload.certpath: The path to the certificate files within the container (default is /config)
# - sh.acme.autoload.keyname: The name of the key file to be created
# - sh.acme.autoload.certname: The name of the cert file to be created
# - sh.acme.autoload.caname: The name of the ca file to be created
# - sh.acme.autoload.fullchainname: The name of the fullchain file to be created
#
# cert requires the following labels:
# - sh.acme.autoload.certpath: The path to the certificate files within the container (default is /config)
# - sh.acme.autoload.keyname: The name of the key file to be created
# - sh.acme.autoload.certname: The name of the cert file to be created
#
# fullchain requires the following labels:
# - sh.acme.autoload.certpath: The path to the certificate files within the container (default is /config)
# - sh.acme.autoload.keyname: The name of the key file to be created
# - sh.acme.autoload.fullchainname: The name of the fullchain file to be created
#
# bundledchain requires the following labels:
# - sh.acme.autoload.certpath: The path to the bundled file within the container (default is /config)
# - sh.acme.autoload.bundlename: The name of the bundled file to be created
#
# bundledcert requires the following labels:
# - sh.acme.autoload.certpath: The path to the bundled file within the container (default is /config)
# - sh.acme.autoload.bundlename: The name of the bundled file to be created
#
# bundledca requires the following labels:
# - sh.acme.autoload.certpath: The path to the bundled file within the container (default is /config)
# - sh.acme.autoload.bundlename: The name of the bundled file to be created
#
# crashplan requires the following labels:
# - sh.acme.autoload.certpath: The path to the certificate and bundled files within the container (default is /config)
# - sh.acme.autoload.keyname: The name of the key file to be created
# - sh.acme.autoload.fullchainname: The name of the fullchain file to be created
# - sh.acme.autoload.bundlename: The name of the bundled file to be created
#
# The script will then copy the generated files to the container and restart the container.


# Global Variables (either set here by uncommenting or in the environment before calling this script)
#export DEPLOY_DOCKERMULTI_CONTAINER_P12PASS='xxxxxxxxxx'

### Do not edit below this line ###

# Define the dockermulti_deploy function
dockermulti_deploy() {

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

    _getdeployconf DEPLOY_DOCKERMULTI_CONTAINER_P12PASS

    _debug2 DEPLOY_DOCKERMULTI_CONTAINER_P12PASS "$DEPLOY_DOCKERMULTI_CONTAINER_P12PASS"

    # Flag to track errors
    ERROR_FLAG=false

    # Generate pkcs12 file
    # I know that acme.sh can generate a pkcs12 file with the certificate renewal, however I've decided to generate
    # it here rather than needing to add code to check if the PFX file exists and the certificate has been renewed.
    _debug "Generate import pkcs12"
    _import_pkcs12="$(_mktemp)"
    _toPkcs "$_import_pkcs12" "$_ckey" "$_ccert" "$_cca" "$DEPLOY_DOCKERMULTI_CONTAINER_P12PASS"
    # shellcheck disable=SC2181
    if [ "$?" != "0" ]; then
        _err "Error generating pkcs12. Please re-run with --debug and report a bug."
        return 1
    fi

    # Iterate over running containers with the specified label
    while IFS= read -r container_id; do
	#Get container name
	if ! container_name=$(docker inspect --format '{{.Name}}' "$container_id" | tr -d /); then
		echo "Error getting container name for $container_id"
		 ERROR_FLAG=true
            continue
        fi
	
	    echo "Processing container $container_id ($container_name)"

	    # Get the CERTPATH & CERTTPYE label from the container
        if ! CERTPATH_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.certpath"}}' "$container_id"); then
            echo "Error getting sh.acme.autoload.certpath for $container_id ($container_name)"
            ERROR_FLAG=true
            continue
        fi
        if ! CERTTYPE_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.certtype"}}' "$container_id"); then
            echo "Error getting sh.acme.autoload.certtype for $container_id ($container_name)"
            ERROR_FLAG=true
            continue
        fi
				
        # Use CERTPATH_LABEL or /config if not set
        DESTINATION_PATH="${CERTPATH_LABEL:-/config}"

        # Copy files based on CERTTYPELABEL
        if [ "$CERTTYPE_LABEL" == "p12" ]; then
            # Get P12NAME label
            if ! P12NAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.p12name"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.p12name for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi

            # Copy the _import_pkcs12 file into the container
            docker cp "$_import_pkcs12" "$container_id:$DESTINATION_PATH/$P12NAME_LABEL" || { echo "Error copying PKCS12 file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
            echo "$CERTTYPE_LABEL certificate type files successfully copied to container: $container_id ($container_name)"

        elif [ "$CERTTYPE_LABEL" == "ca" ]; then
            # Get KEYNAME, CERTNAME, and CANAME labels
            if ! KEYNAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.keyname"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.keyname for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi
            if ! CERTNAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.certname"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.certname for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi
            if ! CANAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.caname"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.caname for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi

            # Copy the _ckey, _ccert, and _cca files into the container
            docker cp "$_ckey" "$container_id:$DESTINATION_PATH/$KEYNAME_LABEL" || { echo "Error copying key file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
            docker cp "$_ccert" "$container_id:$DESTINATION_PATH/$CERTNAME_LABEL" || { echo "Error copying cert file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
            docker cp "$_cca" "$container_id:$DESTINATION_PATH/$CANAME_LABEL" || { echo "Error copying ca file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
            echo "$CERTTYPE_LABEL certificate type files successfully copied to container: $container_id ($container_name)"

        elif [ "$CERTTYPE_LABEL" == "all" ]; then
            # Get KEYNAME, CERTNAME, CANAME, and FULLCHAINNAME labels
            if ! KEYNAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.keyname"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.keyname for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi
            if ! CERTNAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.certname"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.certname for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi
            if ! CANAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.caname"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.caname for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi
            if ! FULLCHAINNAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.fullchainname"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.fullchainname for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi

            # Copy the _ckey, _ccert, _cca, and _cfullchain files into the container
            docker cp "$_ckey" "$container_id:$DESTINATION_PATH/$KEYNAME_LABEL" || { echo "Error copying key file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
            docker cp "$_ccert" "$container_id:$DESTINATION_PATH/$CERTNAME_LABEL" || { echo "Error copying cert file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
            docker cp "$_cca" "$container_id:$DESTINATION_PATH/$CANAME_LABEL" || { echo "Error copying ca file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
            docker cp "$_cfullchain" "$container_id:$DESTINATION_PATH/$FULLCHAINNAME_LABEL" || { echo "Error copying fullchain file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
            echo "$CERTTYPE_LABEL certificate type files successfully copied to container: $container_id ($container_name)"

        elif [ "$CERTTYPE_LABEL" == "cert" ]; then
            # Get KEYNAME and CERTNAME labels
            if ! KEYNAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.keyname"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.keyname for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi
            if ! CERTNAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.certname"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.certname for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi

            # Copy the _ckey and _ccert files into the container
            docker cp "$_ckey" "$container_id:$DESTINATION_PATH/$KEYNAME_LABEL" || { echo "Error copying key file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
            docker cp "$_ccert" "$container_id:$DESTINATION_PATH/$CERTNAME_LABEL" || { echo "Error copying cert file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
            echo "$CERTTYPE_LABEL certificate type files successfully copied to container: $container_id ($container_name)"

        elif [ "$CERTTYPE_LABEL" == "fullchain" ]; then
            # Get KEYNAME and FULLCHAINNAME labels
            if ! KEYNAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.keyname"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.keyname for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi
            if ! FULLCHAINNAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.fullchainname"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.fullchainname for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi

            # Copy the _ckey and _cfullchain files into the container
            docker cp "$_ckey" "$container_id:$DESTINATION_PATH/$KEYNAME_LABEL" || { echo "Error copying key file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
            docker cp "$_cfullchain" "$container_id:$DESTINATION_PATH/$FULLCHAINNAME_LABEL" || { echo "Error copying cert file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
            echo "$CERTTYPE_LABEL certificate type files successfully copied to container: $container_id ($container_name)"

        elif [ "$CERTTYPE_LABEL" == "bundledchain" ]; then
            # Get BUNDLENAME labels
            if ! BUNDLENAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.bundlename"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.bundlename for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi
            
			# Create bundled file from _ckey and _cfullchain
			cat $_ckey > /tmp/bundle.pem
			if [ "$?" != "0" ]; then
				echo "Error generating bundled file for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
			fi
			cat $_cfullchain >> /tmp/bundle.pem
			if [ "$?" != "0" ]; then
				echo "Error generating bundled file for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
			fi
            # Copy the bundled files into the container
            docker cp "/tmp/bundle.pem" "$container_id:$DESTINATION_PATH/$BUNDLENAME_LABEL" || { echo "Error copying VNC cert file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
			rm /tmp/bundle.pem
            echo "$CERTTYPE_LABEL certificate type files successfully copied to container: $container_id ($container_name)"
        
        elif [ "$CERTTYPE_LABEL" == "bundledcert" ]; then
            # Get BUNDLENAME labels
            if ! BUNDLENAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.bundlename"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.bundlename for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi
            
			# Create bundled file from _ckey and _ccert
			cat $_ckey > /tmp/bundle.pem
			if [ "$?" != "0" ]; then
				echo "Error generating bundled file for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
			fi
			cat $_ccert >> /tmp/bundle.pem
			if [ "$?" != "0" ]; then
				echo "Error generating bundled file for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
			fi
            # Copy the bundled files into the container
            docker cp "/tmp/bundle.pem" "$container_id:$DESTINATION_PATH/$BUNDLENAME_LABEL" || { echo "Error copying VNC cert file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
			rm /tmp/bundle.pem
            echo "$CERTTYPE_LABEL certificate type files successfully copied to container: $container_id ($container_name)"
        
        elif [ "$CERTTYPE_LABEL" == "bundledca" ]; then
            # Get BUNDLENAME labels
            if ! BUNDLENAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.bundlename"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.bundlename for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi
            
			# Create bundled file from _ckey and _cca
			cat $_ckey > /tmp/bundle.pem
			if [ "$?" != "0" ]; then
				echo "Error generating bundled file for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
			fi
			cat $_cca >> /tmp/bundle.pem
			if [ "$?" != "0" ]; then
				echo "Error generating bundled file for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
			fi
            # Copy the bundled files into the container
            docker cp "/tmp/bundle.pem" "$container_id:$DESTINATION_PATH/$BUNDLENAME_LABEL" || { echo "Error copying VNC cert file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
			rm /tmp/bundle.pem
            echo "$CERTTYPE_LABEL certificate type files successfully copied to container: $container_id ($container_name)"

        elif [ "$CERTTYPE_LABEL" == "crashplan" ]; then
            # Get KEYNAME, BUNDLENAME and FULLCHAINNAME labels
            if ! KEYNAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.keyname"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.keyname for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi
            if ! BUNDLENAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.bundlename"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.bundlename for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi
            if ! FULLCHAINNAME_LABEL=$(docker inspect --format='{{index .Config.Labels "sh.acme.autoload.fullchainname"}}' "$container_id"); then
                echo "Error getting sh.acme.autoload.fullchainname for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
            fi

			# Create bundled file from _ckey and _cfullchain
			cat $_ckey > /tmp/bundle.pem
			if [ "$?" != "0" ]; then
				echo "Error generating bundled file for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
			fi
			cat $_cfullchain >> /tmp/bundle.pem
			if [ "$?" != "0" ]; then
				echo "Error generating bundled file for $container_id ($container_name)"
                ERROR_FLAG=true
                continue
			fi
            # Copy the _ckey, _cfullchain files into the container
            docker cp "$_ckey" "$container_id:$DESTINATION_PATH/$KEYNAME_LABEL" || { echo "Error copying key file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
            docker cp "$_cfullchain" "$container_id:$DESTINATION_PATH/$FULLCHAINNAME_LABEL" || { echo "Error copying cert file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
			# Copy the bundled files into the container
            docker cp "/tmp/bundle.pem" "$container_id:$DESTINATION_PATH/$BUNDLENAME_LABEL" || { echo "Error copying bundled file to $container_id ($container_name)"; ERROR_FLAG=true; continue; }
			rm /tmp/bundle.pem
            echo "$CERTTYPE_LABEL certificate type files successfully copied to container: $container_id ($container_name)"

        else
            # Set error flag and print error message
            ERROR_FLAG=true
            echo "Error, incorrect certificate type defined in sh.acme.autoload.certtype for $container_id ($container_name)"
			continue
        fi
		
		echo "Restarting container: $container_id ($container_name)"
        docker restart "$container_id" || { echo "Error restarting $container_id  ($container_name)"; ERROR_FLAG=true; continue; }
    
	    echo "Container restarted: $container_id ($container_name)"
        
    done < <(docker ps --filter "label=sh.acme.autoload.domain=$_cdomain" --quiet)

    # Check if any errors occurred during processing
    if [ "$ERROR_FLAG" = true ]; then
        _err "Docker Multi Deploy script completed with errors."
        return 1
    fi
}

