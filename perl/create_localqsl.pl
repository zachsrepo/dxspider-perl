#!/usr/bin/perl
#
# Implement a 'GO' database list
#
# Copyright (c) 2003 Dirk Koopman G1TLH
#
# $Id$
#

# search local then perl directories
BEGIN {
	use vars qw($root);
	
	# root of directory tree for this system
	$root = "/spider"; 
	$root = $ENV{'DXSPIDER_ROOT'} if $ENV{'DXSPIDER_ROOT'};
	
	unshift @INC, "$root/perl";	# this IS the right way round!
	unshift @INC, "$root/local";
}

use strict;

use IO::File;
use DXVars;
use DXUtil;
use Spot;
use DXDb;

use vars qw($end $lastyear $lastday);

$end = 0;
$SIG{TERM} = $SIG{INT} = sub { $end++ };

my $qslfn = "localqsl";
$lastyear = 0;
$lastday = 0;

$main::systime = time;

DXDb::load();
my $db = DXDb::getdesc($qslfn);
unless ($db) {
	DXDb::new($qslfn);
	DXDb::load();
	$db = DXDb::getdesc($qslfn);
}
die "cannot load $qslfn $!" unless $db;

# find start point (if any)
my $statefn = "$root/data/$qslfn.state";
my $s = readfilestr($statefn);
eval $s if $s;

my $base = "$root/data/spots";

opendir YEAR, $base or die "$base $!";
foreach my $year (sort readdir YEAR) {
	next if $year =~ /^\./;
	next unless $year ge $lastyear;
	
	my $baseyear = "$base/$year";
	opendir DAY,  $baseyear or die "$baseyear $!";
	foreach my $day (sort readdir DAY) {
		next unless $day =~ /(\d+)\.dat$/;
		my $dayno = $1 + 0;
		next unless $dayno >= $lastday;
		
		my $fn = "$baseyear/$day";
		my $f = new IO::File $fn  or die "$fn ($!)"; 
		print "doing: $fn\n";
		while (<$f>) {
			if (/(QSL|VIA)/i) {
				my ($freq, $call, $t, $comment, $by, @rest) = split /\^/;
				my $value = $db->getkey($call) || "";
				my $newvalue = update($value, $call, $t, $comment, $by);
				if ($newvalue ne $value) {
					$db->putkey($call, $newvalue);
				}
			}
		}
		$f->close;
		$f = new IO::File ">$statefn" or die "cannot open $statefn $!";
		print $f "\$lastyear = $year; \$lastday = $dayno;\n";
		$f->close;
	}
}

DXDb::closeall();
exit(0);

sub update
{
	my ($line, $call, $t, $comment, $by) = @_;
	my @lines = split /\n/, $line;
	my @in;
	
	# decode the lines
	foreach my $l (@lines) {
		my ($date, $time, $oby, $ocom) = $l =~ /^(\s?\S+)\s+(\s?\S+)\s+de\s+(\S+):\s+(.*)$/;
		if ($date) {
			my $ot = cltounix($date, $time);
			push @in, [$ot, $oby, $ocom];
		}
	}
	
	# is this newer than the earliest one?
	if (@in && $in[0]->[0] < $t) {
		@in = grep {$_->[1] ne $by} @in;
	}
	$comment =~ s/://g;
	unshift @in, [$t, $by, $comment] if grep /^bur/i || is_callsign(uc $_), split(/\b/, $comment);
	pop @in, if @in > 10;
	return join "\n", (map {(cldatetime($_->[0]) . " de $_->[1]: $_->[2]")} @in);
}
