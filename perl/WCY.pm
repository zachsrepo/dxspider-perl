#!/usr/bin/perl
# 
# The WCY analog of the WWV geomagnetic information and calculation module
#
# Copyright (c) 2000 - Dirk Koopman G1TLH
#
# $Id$
#

package WCY;

use DXVars;
use DXUtil;
use DXLog;
use Julian;
use IO::File;
use DXDebug;
use Data::Dumper;

use strict;
use vars qw($date $sfi $k $expk $a $r $sa $gmf $au  @allowed @denied $fp $node $from 
            $dirprefix $param
            %dup $duplth $dupage);

$fp = 0;						# the DXLog fcb
$date = 0;						# the unix time of the WWV (notional)
$sfi = 0;						# the current SFI value
$k = 0;							# the current K value
$a = 0;							# the current A value
$r = 0;							# the current R value
$sa = "";						# solar activity
$gmf = "";						# Geomag activity
$au = 'no';						# aurora warning
$node = "";						# originating node
$from = "";						# who this came from
@allowed = ();					# if present only these callsigns are regarded as valid WWV updators
@denied = ();					# if present ignore any wwv from these callsigns
%dup = ();						# the spot duplicates hash
$duplth = 20;					# the length of text to use in the deduping
$dupage = 12*3600;				# the length of time to hold spot dups

$dirprefix = "$main::data/wcy";
$param = "$dirprefix/param";

sub init
{
	$fp = DXLog::new('wcy', 'dat', 'm');
	do "$param" if -e "$param";
	confess $@ if $@;
}

# write the current data away
sub store
{
	my $fh = new IO::File;
	open $fh, "> $param" or confess "can't open $param $!";
	print $fh "# WCY data parameter file last mod:", scalar gmtime, "\n";
	my $dd = new Data::Dumper([ $date, $sfi, $a, $k, $expk, $r, $sa, $gmf, $au, $from, $node, \@denied, \@allowed ], [qw(date sfi a k expk r sa gmf au from node *denied *allowed)]);
	$dd->Indent(1);
	$dd->Terse(0);
	$dd->Quotekeys(0);
	$fh->print($dd->Dumpxs);
	$fh->close;
	
	# log it
	$fp->writeunix($date, "$date^$sfi^$a^$k^$expk^$r^$sa^$gmf^$au^$from^$node");
}

# update WWV info in one go (usually from a PC23)
sub update
{
	my ($mydate, $mytime, $mysfi, $mya, $myk, $myexpk, $myr, $mysa, $mygmf, $myau, $myfrom, $mynode) = @_;
	if ((@allowed && grep {$_ eq $from} @allowed) || 
		(@denied && !grep {$_ eq $from} @denied) ||
		(@allowed == 0 && @denied == 0)) {
		
		#	my $trydate = cltounix($mydate, sprintf("%02d18Z", $mytime));
		if ($mydate >= $date) {
			if ($myr) {
				$r = 0 + $myr;
			} else {
				$r = 0 unless abs ($mysfi - $sfi) > 3;
			}
			$sfi = $mysfi;
			$a = $mya;
			$k = $myk;
			$expk = $myexpk;
			$r = $myr;
			$sa = $mysa;
			$gmf = $mygmf;
			$au = $myau;
			$date = $mydate;
			$from = $myfrom;
			$node = $mynode;
			
			store();
		}
	}
}

# add or substract an allowed callsign
sub allowed
{
	my $flag = shift;
	if ($flag eq '+') {
		push @allowed, map {uc $_} @_;
	} else {
		my $c;
		foreach $c (@_) {
			@allowed = map {$_ ne uc $c} @allowed; 
		} 
	}
	store();
}

# add or substract a denied callsign
sub denied
{
	my $flag = shift;
	if ($flag eq '+') {
		push @denied, map {uc $_} @_;
	} else {
		my $c;
		foreach $c (@_) {
			@denied = map {$_ ne uc $c} @denied; 
		} 
	}
	store();
}

#
# print some items from the log backwards in time
#
# This command outputs a list of n lines starting from line $from to $to
#
sub search
{
	my $from = shift;
	my $to = shift;
	my @date = $fp->unixtoj(shift);
	my $pattern = shift;
	my $search;
	my @out;
	my $eval;
	my $count;
	
	$search = 1;
	$eval = qq(
			   my \$c;
			   my \$ref;
			   for (\$c = \$#in; \$c >= 0; \$c--) {
					\$ref = \$in[\$c];
					if ($search) {
						\$count++;
						next if \$count < \$from;
						push \@out, \$ref;
						last if \$count >= \$to; # stop after n
					}
				}
			  );
	
	$fp->close;					# close any open files
	
	my $fh = $fp->open(@date); 
	for ($count = 0; $count < $to; ) {
		my @in = ();
		if ($fh) {
			while (<$fh>) {
				chomp;
				push @in, [ split '\^' ] if length > 2;
			}
			eval $eval;			# do the search on this file
			return ("Geomag search error", $@) if $@;
			last if $count >= $to; # stop after n
		}
		$fh = $fp->openprev();	# get the next file
		last if !$fh;
	}
	
	return @out;
}

#
# the standard log printing interpreting routine.
#
# every line that is printed should call this routine to be actually visualised
#
# Don't really know whether this is the correct place to put this stuff, but where
# else is correct?
#
# I get a reference to an array of items
#
sub print_item
{
	my $r = shift;
	my $d = cldate($r->[0]);
	my $t = (gmtime($r->[0]))[2];

	return sprintf("$d   %02d %5d %3d %3d   %3d %3d %-5s %-5s     %-3s <%s>", 
				    $t, @$r[1..9]);
}

#
# read in this month's data
#
sub readfile
{
	my @date = $fp->unixtoj(shift);
	my $fh = $fp->open(@date); 
	my @spots = ();
	my @in;
	
	if ($fh) {
		while (<$fh>) {
			chomp;
			push @in, [ split '\^' ] if length > 2;
		}
	}
	return @in;
}

# enter the spot for dup checking and return true if it is already a dup
sub dup
{
	my ($d, $sfi, $a, $k, $r) = @_; 

	# dump if too old
	return 2 if $d < $main::systime - $dupage;
 
	$d /= 60;                            # to the nearest minute
#	chomp $text;
#	$text = substr($text, 0, $duplth) if length $text > $duplth; 
	my $dupkey = "$d|$sfi|$k|$a|$r";
	return 1 if exists $dup{$dupkey};
	$dup{$dupkey} = $d * 60;         # in seconds (to the nearest minute)
	return 0; 
}

# called every hour and cleans out the dup cache
sub process
{
	my $cutoff = $main::systime - $dupage;
	while (my ($key, $val) = each %dup) {
		delete $dup{$key} if $val < $cutoff;
	}
}

sub listdups
{
	my @out;
	for (sort { $dup{$a} <=> $dup{$b} } keys %dup) {
		my $val = $dup{$_};
		push @out, "$_ = $val (" . cldatetime($val) . ")";
	}
	return @out;
}
1;
__END__;
