#!/bin/bash
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#

# Include environments
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Include the AMD accelerators library
CDIR=$(dirname "${FILE}")
. "${CDIR}/include.sh"    || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlLog "Checking if rocm package is installed"
        rlRun "rpm -q rocm" 1 "rocm package should not be installed"

        # ROCm-devel is not available for RHEL 9
        if rlIsRHEL 10; then
          rlLog "Checking if rocm-devel package is installed"
          rlRun "rpm -q rocm-devel" 1 "rocm-devel package should not be installed"
        fi

        rlLog "Starting AMD ROCm setup"
        AmdROCmSetUp
    rlPhaseEnd

    rlPhaseStartTest
        rlLog "Checking if rocm package is installed"
        rlRun "rpm -q rocm" 0 "rocm package should be installed"

        # ROCm-devel is not available for RHEL 9
        if rlIsRHEL 10; then
          rlLog "Checking if rocm-devel package is installed"
          rlRun "rpm -q rocm-devel" 0 "rocm-devel package should be installed"
        fi
    rlPhaseEnd

    rlPhaseStartCleanup
        rlLog "Starting AMD ROCm cleanup"
        AmdROCmCleanUp

        rlLog "Checking if rocm package is installed"
        rlRun "rpm -q rocm" 1 "rocm package should not be installed"

        # ROCm-devel is not available for RHEL 9
        if rlIsRHEL 10; then
          rlLog "Checking if rocm-devel package is installed"
          rlRun "rpm -q rocm-devel" 1 "rocm-devel package should not be installed"
        fi

    rlPhaseEnd

rlJournalEnd
