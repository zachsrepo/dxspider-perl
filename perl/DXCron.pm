#
# module to timed tasks
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

package DXCron;

use DXVars;
use DXUtil;
use DXM;
use DXDebug;
use FileHandle;
use Carp;

use strict;

use vars qw{@crontab $mtime $lasttime $lastmin};

@crontab = ();
$mtime = 1;
$lasttime = 0;
$lastmin = 0;


my $fn = "$main::cmd/crontab";
my $localfn = "$main::localcmd/crontab";

# cron initialisation / reading in cronjobs
sub init
{
	if ((-e $localfn && -M $localfn < $mtime) || (-e $fn && -M $fn < $mtime) || $mtime == 0) {
		my $t;
		
		@crontab = ();
		
		# first read in the standard one
		if (-e $fn) {
			$t = -M $fn;
			
			cread($fn);
			$mtime = $t if  $t <= $mtime;
		}

		# then read in any local ones
		if (-e $localfn) {
			$t = -M $localfn;
			
			cread($localfn);
			$mtime = $t if $t <= $mtime;
		}
	}
}

# read in a cron file
sub cread
{
	my $fn = shift;
	my $fh = new FileHandle;
	my $line = 0;

	dbg('cron', "cron: reading $fn\n");
	open($fh, $fn) or confess("cron: can't open $fn $!");
	while (<$fh>) {
		$line++;
		chomp;
		next if /^\s*#/o or /^\s*$/o;
		my ($min, $hour, $mday, $month, $wday, $cmd) = /^\s*(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.+)$/o;
		next if !$min;
		my $ref = bless {};
		my $err;
		
		$err |= parse($ref, 'min', $min, 0, 60);
		$err |= parse($ref, 'hour', $hour, 0, 23);
		$err |= parse($ref, 'mday', $mday, 1, 31);
		$err |= parse($ref, 'month', $month, 1, 12, "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec");
		$err |= parse($ref, 'wday', $wday, 0, 6, "sun", "mon", "tue", "wed", "thu", "fri", "sat");
		if (!$err) {
			$ref->{cmd} = $cmd;
			push @crontab, $ref;
			dbg('cron', "cron: adding $_\n");
		} else {
			dbg('cron', "cron: error on line $line '$_'\n");
		}
	}
	close($fh);
}

sub parse
{
	my $ref = shift;
	my $sort = shift;
	my $val = shift;
	my $low = shift;
	my $high = shift;
	my @req;

	# handle '*' values
	if ($val eq '*') {
		$ref->{$sort} = 0;
		return 0;
	}

	# handle comma delimited values
	my @comma = split /,/o, $val;
	for (@comma) {
		my @minus = split /-/o;
		if (@minus == 2) {
			return 1 if $minus[0] < $low || $minus[0] > $high;
			return 1 if $minus[1] < $low || $minus[1] > $high;
			my $i;
			for ($i = $minus[0]; $i <= $minus[1]; ++$i) {
				push @req, 0 + $i; 
			}
		} else {
			return 1 if $_ < $low || $_ > $high;
			push @req, 0 + $_;
		}
	}
	$ref->{$sort} = \@req;
	
	return 0;
}

# process the cronjobs
sub process
{
	my $now = $main::systime;
	return if $now-$lasttime < 1;
	
	my ($sec, $min, $hour, $mday, $mon, $wday) = (gmtime($now))[0,1,2,3,4,6];

	# are we at a minute boundary?
	if ($min != $lastmin) {
		
		# read in any changes if the modification time has changed
		init();

		$mon += 1;       # months otherwise go 0-11
		my $cron;
		foreach $cron (@crontab) {
			if ((!$cron->{min} || grep $_ eq $min, @{$cron->{min}}) &&
				(!$cron->{hour} || grep $_ eq $hour, @{$cron->{hour}}) &&
				(!$cron->{mday} || grep $_ eq $mday, @{$cron->{mday}}) &&
				(!$cron->{mon} || grep $_ eq $mon, @{$cron->{mon}}) &&
				(!$cron->{wday} || grep $_ eq $wday, @{$cron->{wday}})	){
				
				if ($cron->{cmd}) {
					dbg('cron', "cron: $min $hour $mday $mon $wday -> doing '$cron->{cmd}'");
					eval "$cron->{cmd}";
					dbg('cron', "cron: cmd error $@") if $@;
				}
			}
		}
	}

	# remember when we are now
	$lasttime = $now;
	$lastmin = $min;
}

# 
# these are simple stub functions to make connecting easy in DXCron contexts
#

sub connected
{
	my $call = uc shift;
	return DXChannel->get($call);
}

sub start_connect
{
	my $call = uc shift;
	my $lccall = lc $call;

	my $prog = "$main::root/local/client.pl";
	$prog = "$main::root/perl/client.pl" if ! -e $prog;
	
	my $pid = fork();
	if (defined $pid) {
		if (!$pid) {
			# in child, unset warnings, disable debugging and general clean up from us
			$^W = 0;
#			do "$main::root/perl/Disable_debug.pl";
			eval "{ package DB; sub DB {} }";
			alarm(0);
			$SIG{CHLD} = $SIG{TERM} = $SIG{INT} = $SIG{__WARN__} = 'DEFAULT';
			exec $prog, $call, 'connect';
			dbg('cron', "exec '$prog' failed $!");
		}
		dbg('cron', "connect to $call started");
	} else {
		dbg('cron', "can't fork for $prog $!");
	}
}

sub spawn
{
	my $line = shift;
	
	my $pid = fork();
	if (defined $pid) {
		if (!$pid) {
			# in child, unset warnings, disable debugging and general clean up from us
			$^W = 0;
#			do "$main::root/perl/Disable_debug.pl";
			eval "{ package DB; sub DB {} }";
			alarm(0);
			$SIG{CHLD} = $SIG{TERM} = $SIG{INT} = $SIG{__WARN__} = 'DEFAULT';
			exec "$line";
			dbg('cron', "exec '$line' failed $!");
		}
		dbg('cron', "spawn of $line started");
	} else {
		dbg('cron', "can't fork for $line $!");
	}
}
1;
__END__
