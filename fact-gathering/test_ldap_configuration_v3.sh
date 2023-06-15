#!/bin/bash

# This script reads in LDAP connection information from SAS Configuration Server, then uses it to perform an LDAP query using the ldapsearch command.
# Date: 29MAY2020

# Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0


echo "NOTE: Checking if ldapsearch is installed."

if ! ldapsearch -VV
        then
                echo "ERROR: This script requires ldapsearch be installed."
                exit 1
fi
echo "NOTE: ldapsearch is installed, continuing..."

echo "NOTE: Checking if we can read /opt/sas/viya/config/etc/SASSecurityCertificateFramework/cacerts/trustedcerts.pem"
if [ -r "/opt/sas/viya/config/etc/SASSecurityCertificateFramework/cacerts/trustedcerts.pem" ]
        then
        echo "NOTE: We can, setting LDAPTLS_CACERT variable to that path."
        LDAPTLS_CACERT="/opt/sas/viya/config/etc/SASSecurityCertificateFramework/cacerts/trustedcerts.pem"
        export LDAPTLS_CACERT
        else
        echo "WARN: We do not have read permission to the default certificate trust store /opt/sas/viya/config/etc/SASSecurityCertificateFramework/cacerts/trustedcerts.pem"
fi

# Source consul config file
echo "NOTE: Checking if we can read /opt/sas/viya/config/consul.conf"

# Fail if consul.conf unreadable.
if [ ! -r "/opt/sas/viya/config/consul.conf" ]
        then
                echo "ERROR: We do not have read permission on /opt/sas/viya/config/consul.conf"
                exit 1
fi

echo "NOTE: Sourcing /opt/sas/viya/config/consul.conf"
# shellcheck source=/dev/null
. /opt/sas/viya/config/consul.conf

# Put consul client token in CONSUL_HTTP_TOKEN
echo "NOTE: Checking if we can read /opt/sas/viya/config/etc/SASSecurityCertificateFramework/tokens/consul/default/client.token"

# Fail if client.token unreadable.
if [ ! -r "/opt/sas/viya/config/etc/SASSecurityCertificateFramework/tokens/consul/default/client.token" ]
        then
                echo "ERROR: We do not have read permission on /opt/sas/viya/config/etc/SASSecurityCertificateFramework/tokens/consul/default/client.token"
                exit 1
fi

echo "NOTE: Setting contents of client.token to variable CONSUL_HTTP_TOKEN"

CONSUL_HTTP_TOKEN=$(cat /opt/sas/viya/config/etc/SASSecurityCertificateFramework/tokens/consul/default/client.token)
export CONSUL_HTTP_TOKEN

# Get LDAP connection attributes for ldapsearch
echo "NOTE: Reading contents of sas.identities.ldap.connection properties"

LDAPHOST=$(/opt/sas/viya/home/bin/sas-bootstrap-config kv read  config/identities/sas.identities.providers.ldap.connection/host)
LDAPPORT=$(/opt/sas/viya/home/bin/sas-bootstrap-config kv read config/identities/sas.identities.providers.ldap.connection/port)
LDAPUSERDN=$(/opt/sas/viya/home/bin/sas-bootstrap-config kv read config/identities/sas.identities.providers.ldap.connection/userDN)
LDAPPASS=$(/opt/sas/viya/home/bin/sas-bootstrap-config kv read config/identities/sas.identities.providers.ldap.connection/password)
LDAPSCHEME=$(/opt/sas/viya/home/bin/sas-bootstrap-config kv read config/identities/sas.identities.providers.ldap.connection/url | cut -f1 -d':')

# Fail if any properties could not be read.
if [ -z "$LDAPHOST" ] || [ -z "$LDAPPORT" ] || [ -z "$LDAPUSERDN" ] || [ -z "$LDAPPASS" ] || [ -z "$LDAPSCHEME" ]
        then
                echo "ERROR: One or more connection properties were not available."
                exit 1
fi


echo "NOTE: Reading contents of identities.providers.ldap.group"

# Get group info for ldapsearch
LDAPGROUPBASE=$(/opt/sas/viya/home/bin/sas-bootstrap-config kv read config/identities/sas.identities.providers.ldap.group/baseDN)
LDAPGROUPOFILTER=$(/opt/sas/viya/home/bin/sas-bootstrap-config kv read config/identities/sas.identities.providers.ldap.group/objectFilter)

# Fail if any properties could not be read.
if [ -z "$LDAPGROUPBASE" ] || [ -z "$LDAPGROUPOFILTER" ]
        then
                echo "ERROR: One or more group properties were not available."
                exit 1
fi

echo "NOTE: Running ldapsearch for groups."

# Execute the ldapsearch command. -z 1 option limits results to a single entry.
ldapsearch -H "$LDAPSCHEME://$LDAPHOST:$LDAPPORT" -D "$LDAPUSERDN" -w "$LDAPPASS" -b "$LDAPGROUPBASE" "$LDAPGROUPOFILTER" -z 1 cn member

echo " NOTE: Reading contents of identities.providers.ldap.users"

# get user info for ldapsearch
LDAPUSERBASE=$(/opt/sas/viya/home/bin/sas-bootstrap-config kv read config/identities/sas.identities.providers.ldap.user/baseDN)
LDAPUSEROFILTER=$(/opt/sas/viya/home/bin/sas-bootstrap-config kv read config/identities/sas.identities.providers.ldap.user/objectFilter)

# Fail if any properties could not be read.
if [ -z "$LDAPUSERBASE" ] || [ -z "$LDAPUSEROFILTER" ]
        then
                echo "ERROR: One or more user properties were not available."
                exit 1
fi

echo "NOTE: Running ldapsearch for users."
# Execute the ldapsearch command. -z 1 option limits results to a single entry.
ldapsearch -H "$LDAPSCHEME://$LDAPHOST:$LDAPPORT" -D "$LDAPUSERDN" -w "$LDAPPASS" -b "$LDAPUSERBASE" "$LDAPUSEROFILTER" -z 1 cn memberOf