#!/bin/sh


# PROFILE=${1-Base-SelfInstall}
PROFILE=${1-Base-qcow}
VERSION=${2-6.1}


TARGET_DIR=./image
REPO_PREFIX=https://manager.suma.suse/rhn/manager/download/sl-micro-6.1-latest
CERT_RPM=https://manager.suma.suse/pub/rhn-org-trusted-ssl-cert-osimage-1.0-1.noarch.rpm

sudo rm -rf $TARGET_DIR
mkdir -p $TARGET_DIR
mkdir -p ./repo
sudo curl -sk $CERT_RPM -o ./repo/rhn-org-trusted-ssl-cert-osimage.noarch.rpm

sudo kiwi-ng \
  --kiwi-file config.kiwi \
  --profile $PROFILE \
  system build \
  --description . \
  --target-dir $TARGET_DIR \
  --ignore-repos-used-for-build \
  --allow-existing-root \
  --add-bootstrap-package rhn-org-trusted-ssl-cert-osimage \
  --add-repo file:$PWD/repo,rpm-dir,common_repo,90,false,false \
  --add-repo $REPO_PREFIX-sl-micro-$VERSION-pool-x86_64\
  --add-repo $REPO_PREFIX-sl-micro-extras-$VERSION-pool-x86_64 \
  --add-repo $REPO_PREFIX-suse-manager-tools-for-sl-micro-$VERSION-x86_64\
  --add-repo $REPO_PREFIX-managertools-sl-micro-$VERSION-x86_64 \

cd --
