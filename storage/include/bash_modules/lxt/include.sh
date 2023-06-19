#!/bin/bash

# the order is important
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/tc.sh
. "$CDIR"/rootdev.sh
. "$CDIR"/suspend_resume.sh
