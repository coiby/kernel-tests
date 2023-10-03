#!/usr/bin/env bash
### ---------------------------------------------------------------------------
### Initialize variables used in compose definitions --------------------------
### ---------------------------------------------------------------------------
# This section initializes variables that form consituent parts of a nightly
# repo url.

#
# Read current RHEL version from os-release.
#
# Since RHEL-x.y pipeline uses RHEL-x.y system in bkr to run tests, using this
# file is valid.
#
# Remark: This depends on the fact that upon the start of the devel process of
#         a new RHEL minor, distro_requires will have appropriate values set in
#         the corresponding trees/minor.xml.j2 file. Should that happen, make
#         sure to run a job patching os-release prior to this test.
#
FILE=$(readlink -f $BASH_SOURCE)
NAME=$(basename $FILE)
CDIR=$(dirname $FILE)

source /etc/os-release
source ${CDIR}/../../cki_lib/libcki.sh || exit 1

MAJOR=${VERSION_ID%%.*}

# Compose path contains AppStream versions as well; we don't care about
# AppStream -> use 0. Applicable from RHEL8 onwards.
if [ $MAJOR -ge 8 -a $(echo -n ${VERSION_ID//[^.]/} | wc -c) -lt 2 ]
then
    VERSION_ID+=".0"
fi

BASEARCH=$(uname -m)

# Depending on RHEL major version and whether or we're testing RT kernel,
# use BaseOS (RHEL8 onwards), RT (RHEL8 onwards, RT), Server (pre-RHEL8),
# or Server-RT (pre-RHEL8 RT).
if [ $MAJOR -lt 8 ]
then
    COMPOSE="Server"
    if  cki_is_kernel_rt; then
        COMPOSE+="-RT"
    fi
else
    COMPOSE="BaseOS"
    if  cki_is_kernel_rt; then
        COMPOSE="RT"
    fi
fi

### ---------------------------------------------------------------------------
### Define repository templates
### ---------------------------------------------------------------------------
#
# The following array contains possible nightly (or as close as we can get to
# a 'nightly') locations. Note that the first two links will be used most of
# the time, the others are kept as a fallback for really old RHELs.
#
# The following variables are used as a template in URL_REPO_CANDIDATES:
#
# $MAJOR        major id of a particular release; e.g. 8 for RHEL 8.0.0
# $VERSION_ID   value sourced from /etc/os-release, w/ added AppStream version
#               where applicable.
# $COMPOSE      Server for pre-RHEL8, Server-RT for pre-RHEL8 RT
#               BaseOS for RHEL8 onwards; RT for RHEL8 RT onwards
#
URL_REPO_CANDIDATES=(
    ## Nightly Repositories ---------------------------------------------------
    ## y-stream and recent z-stream. ------------------------------------------

    # y-stream nightly repositories
    "http://download.devel.redhat.com/rhel-$MAJOR/nightly/RHEL-$MAJOR/latest-RHEL-$VERSION_ID/compose/$COMPOSE/$BASEARCH/os/"

    # Some of the more recent z-stream nigthly composes
    "http://download.devel.redhat.com/rhel-$MAJOR/nightly/updates/RHEL-$MAJOR/latest-RHEL-$VERSION_ID/compose/$COMPOSE/$BASEARCH/os/"

    ## rel-eng fallback (alpha, betas, releases) ------------------------------
    ## There are z-stream releases for which nightlies are not built. In such -
    ## cases, we can use rel-eng as a fallback option as they are second best.-
    "http://download.eng.bos.redhat.com/rhel-$MAJOR/rel-eng/updates/RHEL-$MAJOR/latest-RHEL-$VERSION_ID/compose/Server$COMPOSE/$BASEARCH/os/"
)

baseurl=""
for candidate in "${URL_REPO_CANDIDATES[@]}"
do
    if curl --output /dev/null --silent --head --fail "$candidate"
    then
        baseurl="$candidate"
        break
    fi
done

cat >/etc/yum.repos.d/rhel-latest.repo <<-EOF
[rhel-latest]
name=Latest RHEL $VERSION_ID $COMPOSE
baseurl=$baseurl
enabled=0
gpgcheck=0
EOF
