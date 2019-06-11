#!/bin/bash

# Initialize the root dirs of the components hosted on the container.
# Looking in the /toskose/apps dir for obtaining the names of the hosted apps.
cd /toskose/apps
for d in */ ; do
    echo "creating root dir for ${d}.."
    mkdir -p /$TOSCA_APP_NAME-$d
done

/toskose/supervisord/bundle/supervisord \
-c /toskose/supervisord/config/supervisord.conf
