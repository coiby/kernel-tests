#!/bin/bash
# shellcheck disable=SC2154
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /CoreOS/rpm/Sanity/bz1896046-signfiles
#   Description: Test for BZ#1896046 (Rebuild rpm due to ima-evm-utils (libimaevm))
#   Author: Jan Blazek <jblazek@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

PACKAGE="rpm"
export GPG_TTY=$(tty)

rlJournalStart
    rlPhaseStartSetup
        rlAssertRpm $PACKAGE
        BACKUP=false
        if [[ -e ~/.rpmmacros || -d /root/.gnupg ]]; then
            BACKUP=true
            rlFileBackup ~/.rpmmacros /root/.gnupg
        fi
        rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
        cp signfiles.spec $TmpDir
        rlRun "pushd $TmpDir"
        rlRun -s "rpmbuild -bb signfiles.spec"
        TESTPKG=$(grep 'Wrote:' $rlRun_LOG | cut -d ' ' -f 2 | grep -v 'src.rpm')
        mv -v $TESTPKG .
        TESTPKG=$(basename $TESTPKG)
        pidof rngd && ENTROPY=false || ENTROPY=true
        $ENTROPY && rlRun "rngd -r /dev/urandom -o /dev/random" 0 "Start rngd to generate random numbers"
        # create expect script for signing packages
        cat > sign.exp <<EOF
#!/usr/bin/expect -f
spawn rpmsign --addsign --signfiles --fskpath privkey_evm.pem $TESTPKG
expect {
    "Enter pass phrase: " {
        send -- "abc\r"
    }
    "Passphrase: " {
        send -- "abc\r"
    }
}
expect eof
EOF
        # remove previous gpg keys (they are backed up)
        rm -rf /root/.gnupg
        # create gpg key settings
        cat >foo <<EOF
%echo Generating a basic OpenPGP key
Key-Type: RSA
Key-Length: 2048
Name-Real: Joe Tester
Name-Comment: with stupid passphrase
Name-Email: joe@foo.bar
Expire-Date: 0
Passphrase: abc
# Do a commit here, so that we can later print "done" :-)
%commit
%echo done
EOF

        cat >x509_evm.genkey <<EOF
[ req ]
default_bits = 1024
distinguished_name = req_distinguished_name
prompt = no
string_mask = utf8only
x509_extensions = myexts

[ req_distinguished_name ]
O = Magrathea
CN = Glacier signing key
emailAddress = slartibartfast@magrathea.h2g2

[ myexts ]
basicConstraints=critical,CA:FALSE
keyUsage=digitalSignature
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
EOF
        # create gpg key
        rlRun "gpg --batch --gen-key foo" 0 "Create gpg key"
        # add gpg key to rpm macros
        echo "%_gpg_name Joe Tester (with stupid passphrase) <joe@foo.bar>" > ~/.rpmmacros
        rlRun "gpg --export --armor joe@foo.bar > pub.key" 0 "Create gpg public key"
        rlRun "rpm --import pub.key" 0 "Import the key"
        rlRun "openssl req -new -nodes -utf8 -sha256 -days 36500 -batch  -x509 -config x509_evm.genkey -outform DER -out x509_evm.der -keyout privkey_evm.pem" 0 "Generate file signing key"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "expect sign.exp" 0 "Sign $TESTPKG"
        rlRun "rpm -ivh $TESTPKG" 0 "Install $TESTPKG"
        for FILE in $(rpm -ql --noconfig signfiles); do
            rlRun -s "getfattr -m security.ima -d $FILE"
            rlAssertGrep "^security.ima=" $rlRun_LOG
        done
        for FILE in $(rpm -ql --noconfig signfiles); do
            [[ -d $FILE || -L $FILE ]] && continue
            rlRun "evmctl ima_verify --key x509_evm.der $FILE" 0 "Verify $FILE"
        done
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "rpm -e signfiles" 0 "Remove test rpm"
        rlRun "popd"
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
        [[ $BACKUP = true ]] && rlRun "rlFileRestore"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
