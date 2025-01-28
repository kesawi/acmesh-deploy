# acmesh-deploy
Collection of deployment scripts for [acme.sh](https://github.com/acmesh-official/acme.sh) shell script.

* dockermulti.sh - Deploys a single certificate to multiple docker continers where the certificate domain matches the container label `sh.acme.autoload.domain`
* plex.sh - Deploys a custom certificate to a [Plex Media Server](https://www.plex.tv/)
* unms.sh - Deploys a custom certificate to a [Unifi USIP/UNMS server](https://uisp.com/)
* webmin.sh - Deploys a custom certificate to a [webmin](https://webmin.com/) system admin GUI

Instructions for use are currently contained within each script.

To install you need to copy the script you want to use into the acme.sh `deploy` folder.

The scripts will function as a [deployhook](https://github.com/acmesh-official/acme.sh/wiki/deployhooks) in acme.sh.

Each script has specific global variables that will need to be exported on the first run for a particular certificate (see the `export` statments in each script).

The script name can then be used as the deployment hook. For example to use the dockermulti deployment script:
```
export DEPLOY_DOCKERMULTI_CONTAINER_P12PASS='xxxxxxxxxx'
acme.sh --deploy -d ftp.example.com --deploy-hook dockermulti
```

Happy to have [issues](https://github.com/kesawi/acmesh-deploy/issues) raised.