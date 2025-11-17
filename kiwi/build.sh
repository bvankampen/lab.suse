#!/bin/sh

PROFILE_PREFIX=sles15
VERSION=${1-sp7}
NIVDIA=${2-0}
STREAM=prod

TARGET_DIR=./image
REPO_PREFIX=https://manager.suma.suse/rhn/manager/download/sles15-$VERSION-$STREAM
CERT_RPM=https://manager.suma.suse/pub/rhn-org-trusted-ssl-cert-osimage-1.0-1.noarch.rpm

if [[ $NVIDIA == 1 ]]; then
  cd $PROFILE_PREFIX-$VERSION-nvidia
else
  cd $PROFILE_PREFIX-$VERSION
fi

sudo rm -rf $TARGET_DIR
mkdir -p $TARGET_DIR
mkdir -p ./repo
sudo curl -sk $CERT_RPM -o ./repo/rhn-org-trusted-ssl-cert-osimage.noarch.rpm

sudo kiwi-ng \
  --kiwi-file config.kiwi \
  system build \
  --description . \
  --target-dir $TARGET_DIR \
  --ignore-repos-used-for-build \
  --allow-existing-root \
  --add-bootstrap-package rhn-org-trusted-ssl-cert-osimage \
  --add-repo file:$PWD/repo,rpm-dir,common_repo,90,false,false \
  --add-repo $REPO_PREFIX-sle-product-sles15-$VERSION-pool-x86_64 \
  --add-repo $REPO_PREFIX-sle-product-sles15-$VERSION-updates-x86_64 \
  --add-repo $REPO_PREFIX-sle-module-basesystem15-$VERSION-updates-x86_64 \
  --add-repo $REPO_PREFIX-sle-module-basesystem15-$VERSION-pool-x86_64 \
  --add-repo $REPO_PREFIX-sle-module-python3-15-$VERSION-updates-x86_64 \
  --add-repo $REPO_PREFIX-sle-module-python3-15-$VERSION-pool-x86_64 \
  --add-repo $REPO_PREFIX-sle-manager-tools15-pool-x86_64-$VERSION \
  --add-repo $REPO_PREFIX-sle-manager-tools15-updates-x86_64-$VERSION \
  --add-repo $REPO_PREFIX-sle-module-server-applications15-$VERSION-updates-x86_64 \
  --add-repo $REPO_PREFIX-sle-module-server-applications15-$VERSION-pool-x86_64 \
  --add-repo $REPO_PREFIX-sle-module-systems-management-15-$VERSION-updates-x86_64 \
  --add-repo $REPO_PREFIX-sle-module-systems-management-15-$VERSION-pool-x86_64 \
  --add-repo $REPO_PREFIX-sle-module-devtools15-$VERSION-pool-x86_64 \
  --add-repo $REPO_PREFIX-sle-module-devtools15-$VERSION-updates-x86_64 \
  --add-repo $REPO_PREFIX-sle-module-desktop-applications15-$VERSION-pool-x86_64 \
  --add-repo $REPO_PREFIX-sle-module-desktop-applications15-$VERSION-updates-x86_64 \
  --add-repo $REPO_PREFIX-sle-module-public-cloud15-$VERSION-pool-x86_64 \
  --add-repo $REPO_PREFIX-sle-module-public-cloud15-$VERSION-updates-x86_64 \
  --add-repo $REPO_PREFIX-nvidia-cuda-sles15

cd --
