#!/bin/sh

mkdir /toskose-test/
mv /toskose/apps/test/artifacts/* /toskose-test/

while [ 0 ]; do
  cat /toskose-test/easter_egg.txt
  sleep 10
done
