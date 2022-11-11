#!/bin/sh

# Source the common test script helpers
. /usr/bin/rhts-environment.sh

SUBTEST=""
# All loopbacked cards that we have on our test systems
SUPPORTED_CARDS="PCH Intel SB MID Generic"

report()
{
    local result=$1
    local code=$2

    #hack to bubble up failures
    test "$result" == "FAIL" && touch .${SUBTEST}

    report_result "${TEST}/${SUBTEST}${SUBSUBTEST}" "${result}" "${code}"
}

fatal()
{
    code=$1
    report "FAIL" "${code}"

    #end the test
    exit 0
}

die()
{
    echo "$1"
    fatal "runcmd"
}

#internal
runcmd()
{
    local cmd=$1

    test -n "$cmd" || die "runcmd needs args"

    echo " -# $cmd" >> $OUTPUTFILE
    eval $cmd | tee -a $OUTPUTFILE

    return "${PIPESTATUS[0]}"
}

#run command, exit test if it fails
runcmd_fatal()
{
    runcmd "$1" || fatal "$?"
}

#run command, report failure but continue
runcmd_report_fail()
{
    runcmd "$1" || report "FAIL" "$?"
}

#run command, report success as a failure (negative testing)
runcmd_report_notfail()
{
    runcmd "$1" && report "FAIL" "$?"
}

#run subtest command, report pass or fail and continue
#hacked in mechanism to bubble up failures
runcmd_subtest()
{
    SUBTEST="$1"
    local cmd="$2"

    test -n "$cmd" || die "runcmd_subtest needs args"
    rm -f .${SUBTEST}

    runcmd "$2" || touch .${SUBTEST}

    #hack to bubble up failures
    test -f .${SUBTEST} && report "FAIL" "0" || report "PASS" "0"
    rm -f .${SUBTEST}

    SUBTEST=""
}

loopback_test() {

	test -n "$1"  || die "need input file"
	input_file=$1
	output_file="out.wav"

	#play a wav file and record it at the same time
	(aplay -D plug:default -d 15 $input_file ; echo $? > p1.ret) &
	(arecord -D plug:default -f dat -d 15 $output_file ; echo $? > p2.ret) &
	wait

	#check the return codes
	playreturncode=$(cat p1.ret)
	recreturncode=$(cat p2.ret)
	rm -f p1.ret p2.ret
	if [ $playreturncode -ne 0 ]; then
	  echo "Playback error: $playreturncode"
	  return 1
	fi
	if [ $recreturncode -ne 0 ]; then
	  echo "Capture error: $recreturncode"
	  return 2
	fi

	#verify the out.wav.  The guess is seen in the SPECTURAL_NAME output
	guess="$(./fft1.py $output_file |grep SPECTRAL_NAME|cut -d'=' -f2|sed 's/"//g')"
	#strip the sample variation number if present
	#this allows for matching multiple fft samples to a single wav sample
	#e.g. both sine-5000 and sine-5000.2 to sine-5000.wav
	guess=$(echo $guess | sed 's/\.[0-9]*$//')
	rm -f out.wav
	if [ "${guess}.wav" != "$input_file" ]; then
	  echo "FFT verify failed: $guess != $input_file"
	  return 3
	fi

	return 0
}

setup() {
	#figure out what release we are on
	release="$(rpm -q --qf '%{VERSION}\n' $(rpm -q --whatprovides redhat-release)|sed -re 's/([0-9]).*/\1/g')"

	EPELLOC="http://mirrors.kernel.org/fedora-epel"

	case "$release" in
	5)
		#setup RHEL-5
		EPELFILE="epel-release-5-4.noarch.rpm"
		test -f $EPELFILE || wget $EPELLOC/5/i386/$EPELFILE
		;;
	6)
		#setup RHEL-6
		EPELFILE="epel-release-6-8.noarch.rpm"
		test -f $EPELFILE || wget $EPELLOC/6/i386/$EPELFILE
		;;
	7)
		#setup RHEL-7
		#nothing to do here
		;;
	*)
		#not supported
		die "Unsupported OS"
		;;
	esac

	#setup epel repo and install dependency scipy
	SUBSUBTEST="/yum_install"
	test -f "$EPELFILE" && runcmd_fatal "yum localinstall -y --nogpg $EPELFILE"
	runcmd_fatal "yum install -y scipy"

	#sanity check for the wav files
	SUBSUBTEST="/wav_check"
	runcmd_fatal "ls *.wav"

	SUBSUBTEST="/sounddevice_check"
	runcmd_fatal "test -n \"$(aplay -l)\""

	#select the card to test by mapping the default PCM
	#device to the one of the supported cards for which
	#a symlink exists in /proc/asound.  If the number
	#of matches is not 1, fail.
	SUBSUBTEST="/sounddevice_select"
	for card in $SUPPORTED_CARDS; do
		if [ -L /proc/asound/$card ]; then
			#did we already select one?
			if [ -n "$card_found" ]; then
				die "Not sure which card to test"
			fi
			card_found=1
			#backup any old config
			rhts-backup ~/.asoundrc
			#create a new temporary config
			echo "pcm."'!'"default {type hw card $card device 0}" >| ~/.asoundrc
			echo "ctl."'!'"default {type hw card $card}" >> ~/.asoundrc
			#print the selected card for reference
			echo "----------------------------"
			echo "Testing '$card' card"
			echo "----------------------------"
			#continue to check for any conflicts
		fi
	done
	runcmd_fatal "test -n \"$card_found"\"

	#upload output of alsa-info for debug purposes
	SUBSUBTEST="/alsainfo"
	alsa-info --no-upload --output alsa-info.txt
	gzip alsa-info.txt
	rhts-submit-log -l alsa-info.txt.gz
	rm alsa-info.txt.gz

	SUBSUBTEST=""
}

setup_audio() {
	#setup the Master channel if present
	if `amixer|grep "Master" > /dev/null`; then
		runcmd_fatal "amixer set 'Master' 70% unmute"
	fi
	#enable capture at 70%
	runcmd_fatal "amixer set 'Capture',0 17dB cap"
	if `amixer|grep "Input Source" > /dev/null`; then
		if `amixer|grep "Rear Mic" > /dev/null`; then
			runcmd_fatal "amixer set 'Input Source',0 'Rear Mic'"
		fi
	fi
	if `amixer cget name='Capture Source' | grep "'Mic'" > /dev/null`; then
	    runcmd_fatal "amixer cset name='Capture Source' 'Mic'"
	fi
	if `amixer|grep "ADC" > /dev/null`; then
		runcmd_fatal "amixer set 'ADC' cap"
	fi
}

test_audio() {
	#basic loop back testing across four different sine waves
	SUBSUBTEST="/sine-1000" runcmd_report_fail "loopback_test sine-1000.wav"
	SUBSUBTEST="/sine-5000" runcmd_report_fail "loopback_test sine-5000.wav"
	SUBSUBTEST="/sine-500" runcmd_report_fail "loopback_test sine-500.wav"

	#mute the capture device and make sure it fails the loopback test
	SUBSUBTEST="/mute-capture" runcmd_report_fail "amixer set 'Capture',0 nocap"
	SUBSUBTEST="/mute-capture" runcmd_report_notfail "loopback_test sine-1000.wav"
	SUBSUBTEST="/mute-capture" runcmd_report_fail "amixer set 'Capture',0 cap"

	#mute the Master device and make sure it fails the loopback test
	SUBSUBTEST="/mute-master" runcmd_report_fail "amixer set 'Master',0 mute"
	SUBSUBTEST="/mute-master" runcmd_report_notfail "loopback_test sine-1000.wav"
	SUBSUBTEST="/mute-master" runcmd_report_fail "amixer set 'Master',0 unmute"

	SUBSUBTEST=""
}

cleanup() {
	echo '========== Clean up =============================' | tee -a ${OUTPUTFILE}
	SUBSUBTEST="/cleanup"
	#revert to the original config
	rhts-restore ~/.asoundrc
	SUBSUBTEST=""
}

quick_test() {
	setup_audio
	loopback_test $1
	exit 0
}

#for quick test
test "$1" == "test" && quick_test $2

runcmd_subtest "setup" setup
runcmd_subtest "setup_audio" setup_audio
runcmd_subtest "test_audio" test_audio
runcmd_subtest "cleanup" cleanup
