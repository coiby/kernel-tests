#!/usr/bin/perl
use strict;
use Config;
printf "%-7s %6s %6s  %8s %8s  %-16s %s\n",
    'STATUS', 'UID', 'PID', 'BTIME', 'ETIME', 'COMMAND', 'FLAG';
my @sig = split ' ', $Config{sig_name};
$/ = \64;
while(<>){
    my @f = unpack 'CCSL6fS8A*', $_;
    my ($flag, $version, $tty, $exitcode, $uid, $gid, $pid, $ppid,
    $btime, $etime, $utime, $stime, $mem, $io, $rw,
    $minflt, $majflt, $swaps, $cmd) = @f;
    my $s = $exitcode & 0x7f;
    my $status = $s ?  "SIG$sig[$s]" : $exitcode >> 8;
    printf "%-7s %6d %6d  %02d:%02d:%02d %8.2f  %-16s %x\n",
    $status, $uid, $pid,
    (localtime $btime)[2,1,0],
    $etime / 100,
    $cmd, $flag;
}
