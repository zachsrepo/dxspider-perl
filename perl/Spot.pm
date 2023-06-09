#
# the dx spot handler
#
# Copyright (c) - 1998 Dirk Koopman G1TLH
#
#
#

package Spot;

use IO::File;
use DXVars;
use DXDebug;
use DXUtil;
use DXLog;
use Julian;
use Prefix;
use DXDupe;
use Data::Dumper;
use QSL;

use strict;

use vars qw($fp $statp $maxspots $defaultspots $maxdays $dirprefix $duplth $dupage $filterdef
			$totalspots $hfspots $vhfspots $maxcalllth $can_encode $use_db_for_search);

$fp = undef;
$statp = undef;
$maxspots = 100;					# maximum spots to return
$defaultspots = 10;				# normal number of spots to return
$maxdays = 100;				# normal maximum no of days to go back
$dirprefix = "spots";
$duplth = 20;					# the length of text to use in the deduping
$dupage = 1*3600;               # the length of time to hold spot dups
$maxcalllth = 12;                               # the max length of call to take into account for dupes
$filterdef = bless ([
			  # tag, sort, field, priv, special parser 
			  ['freq', 'r', 0, 0, \&decodefreq],
			  ['on', 'r', 0, 0, \&decodefreq],
			  ['call', 'c', 1],
			  ['info', 't', 3],
			  ['by', 'c', 4],
			  ['call_dxcc', 'nc', 5],
			  ['by_dxcc', 'nc', 6],
			  ['origin', 'c', 7, 9],
			  ['call_itu', 'ni', 8],
			  ['call_zone', 'nz', 9],
			  ['by_itu', 'ni', 10],
			  ['by_zone', 'nz', 11],
			  ['call_state', 'ns', 12],
			  ['by_state', 'ns', 13],
			  ['channel', 'c', 14],
			  ['ip', 'c', 15],
					 
			 ], 'Filter::Cmd');
$totalspots = $hfspots = $vhfspots = 0;
$use_db_for_search = 0;

# create a Spot Object
sub new
{
	my $class = shift;
	my $self = [ @_ ];
	return bless $self, $class;
}

sub decodefreq
{
	my $dxchan = shift;
	my $l = shift;
	my @f = split /,/, $l;
	my @out;
	my $f;
	
	foreach $f (@f) {
		my ($a, $b); 
		if (m{^\d+/\d+$}) {
			push @out, $f;
		} elsif (($a, $b) = $f =~ m{^(\w+)(?:/(\w+))?$}) {
			$b = lc $b if $b;
			my @fr = Bands::get_freq(lc $a, $b);
			if (@fr) {
				while (@fr) {
					$a = shift @fr;
					$b = shift @fr;
					push @out, "$a/$b";  # add them as ranges
				}
			} else {
				return ('dfreq', $dxchan->msg('dfreq1', $f));
			}
		} else {
			return ('dfreq', $dxchan->msg('e20', $f));
		}
	}
	return (0, join(',', @out));			 
}

sub init
{
	mkdir "$dirprefix", 0777 if !-e "$dirprefix";
	$fp = DXLog::new($dirprefix, "dat", 'd');
	$statp = DXLog::new($dirprefix, "dys", 'd');

	# load up any old spots 
	if ($main::dbh) {
		unless (grep $_ eq 'spot', $main::dbh->show_tables) {
			dbg('initialising spot tables');
			my $t = time;
			my $total;
			$main::dbh->spot_create_table;
			
			my $now = Julian::Day->alloc(1995, 0);
			my $today = Julian::Day->new(time);
			my $sth = $main::dbh->spot_insert_prepare;
			while ($now->cmp($today) <= 0) {
				my $fh = $fp->open($now);
				if ($fh) {
#					$main::dbh->{RaiseError} = 0;
					$main::dbh->begin_work;
					my $count = 0;
					while (<$fh>) {
						chomp;
						my @s = split /\^/;
						if (@s < 12) {
							my @a = (Prefix::cty_data($s[1]))[1..3];
							my @b = (Prefix::cty_data($s[4]))[1..3];
							push @s, $b[1] if @s < 7;
							push @s, '' if @s < 8;
							push @s, @a[0,1], @b[0,1] if @s < 12;
							push @s,  $a[2], $a[2] if @s < 14;
						} 
						
						$main::dbh->spot_insert(\@s, $sth);
						$count++;
					}
					$main::dbh->commit;
					dbg("inserted $count spots from $now->[0] $now->[1]");
					$fh->close;
					$total += $count;
				}
				$now = $now->add(1);
			}
			$main::dbh->begin_work;
			$main::dbh->spot_add_indexes;
			$main::dbh->commit;
#			$main::dbh->{RaiseError} = 1;
			$t = time - $t;
			my $min = int($t / 60);
			my $sec = $t % 60;
			dbg("$total spots converted in $min:$sec");
		}
		unless ($main::dbh->has_ipaddr) {
			$main::dbh->add_ipaddr;
			dbg("added ipaddr field to spot table");
		}
	}
}

sub prefix
{
	return $fp->{prefix};
}

# fix up the full spot data from the basic spot data
sub prepare
{
	# $freq, $call, $t, $comment, $spotter, node, ip address = @_
	my @out = @_[0..4];      # just up to the spotter

	# normalise frequency
	$out[0] = sprintf "%.1f", $out[0];
  
	# remove ssids and /xxx if present on spotter
	$out[4] =~ s/-\d+$//o;

	# remove leading and trailing spaces
	$out[3] = unpad($out[3]);
	
	
	# add the 'dxcc' country on the end for both spotted and spotter, then the cluster call
	my @spd = Prefix::cty_data($out[1]);
	push @out, $spd[0];
	my @spt = Prefix::cty_data($out[4]);
	push @out, $spt[0];
	push @out, $_[5];
	push @out, @spd[1,2], @spt[1,2], $spd[3], $spt[3];
	push @out, $_[6] if $_[6] && is_ipaddr($_[6]);
	return @out;
}

sub add
{
	my $buf = join('^', @_);
	$fp->writeunix($_[2], $buf);
	if ($main::dbh) {
		$main::dbh->begin_work;
		$main::dbh->spot_insert(\@_);
		$main::dbh->commit;
	}
	$totalspots++;
	if ($_[0] <= 30000) {
		$hfspots++;
	} else {
		$vhfspots++;
	}
	if ($_[3] =~ /(?:QSL|VIA)/i) {
		my $q = QSL::get($_[1]) || new QSL $_[1];
		$q->update($_[3], $_[2], $_[4]);
	}
}

# search the spot database for records based on the field no and an expression
# this returns a set of references to the spots
#
# the expression is a legal perl 'if' statement with the possible fields indicated
# by $f<n> where :-
#
#   $f0 = frequency
#   $f1 = call
#   $f2 = date in unix format
#   $f3 = comment
#   $f4 = spotter
#   $f5 = spotted dxcc country
#   $f6 = spotter dxcc country
#   $f7 = origin
#   $f8 = ip address
#
# In addition you can specify a range of days, this means that it will start searching
# from <n> days less than today to <m> days less than today
#
# Also you can select a range of entries so normally you would get the 0th (latest) entry
# back to the 5th latest, you can specify a range from the <x>th to the <y>the oldest.
#
# This routine is designed to be called as Spot::search(..)
#

sub search
{
	my ($expr, $dayfrom, $dayto, $from, $to, $hint, $dxchan) = @_;
	my $eval;
	my @out;
	my $ref;
	my $i;
	my $count;
	my $today = Julian::Day->new(time());
	my $fromdate;
	my $todate;

	$dayfrom = 0 if !$dayfrom;
	$dayto = $maxdays unless $dayto;
	$dayto = $dayfrom + $maxdays if $dayto < $dayfrom;
	$fromdate = $today->sub($dayfrom);
	$todate = $fromdate->sub($dayto);
	$from = 0 unless $from;
	$to = $defaultspots unless $to;
	$hint = $hint ? "next unless $hint" : "";
	$expr = "1" unless $expr;
	
	$to = $from + $maxspots if $to - $from > $maxspots || $to - $from <= 0;

	if ($main::dbh && $use_db_for_search) {
		return $main::dbh->spot_search($expr, $dayfrom, $dayto, $to-$from, $dxchan);
	}

	$expr =~ s/\$f(\d\d?)/\$ref->[$1]/g; # swap the letter n for the correct field name
	#  $expr =~ s/\$f(\d)/\$spots[$1]/g;               # swap the letter n for the correct field name
  
	my $checkfilter;
	$checkfilter = qq (
                      if (\@s < 9) {
                          my \@a = (Prefix::cty_data(\$s[1]))[1..3];
                          my \@b = (Prefix::cty_data(\$s[4]))[1..3];
                          push \@s, \@a[0,1], \@b[0,1], \$a[2], \$a[2];  
                      } else {
                          \$s[12] ||= ' ';
                          \$s[13] ||= ' ';
                      }
	                  my (\$filter, \$hops) = \$dxchan->{spotsfilter}->it(\@s);
	                  next unless (\$filter);
                      ) if $dxchan;
	$checkfilter ||= ' ';
	
	dbg("hint='$hint', expr='$expr', spotno=$from-$to, day=$dayfrom-$dayto\n") if isdbg('search');
  
	# build up eval to execute
	$eval = qq(
			   while (<\$fh>) {
				   $hint;
				   chomp;
				   my \@s = split /\\^/;
                   $checkfilter;
                   push \@spots, \\\@s;
			   }
			   my \$c;
			   my \$ref;
			   for (\$c = \$#spots; \$c >= 0; \$c--) {
					\$ref = \$spots[\$c];
					if ($expr) {
						\$count++;
						next if \$count < \$from; # wait until from 
						push(\@out, \$ref);
						last if \$count >= \$to; # stop after to
					}
				}
			  );
	
    
	dbg("Spot eval: $eval") if isdbg('searcheval');
	

	$fp->close;					# close any open files

	for ($i = $count = 0; $i < $maxdays; ++$i) {	# look thru $maxdays worth of files only
		my $now = $fromdate->sub($i); # but you can pick which $maxdays worth
		last if $now->cmp($todate) <= 0;         
	
		my @spots = ();
		my $fh = $fp->open($now); # get the next file
		if ($fh) {
			my $in;
			eval $eval;			# do the search on this file
			last if $count >= $to; # stop after to
			return ("Spot search error", $@) if $@;
		}
	}

	return @out;
}

# change a freq range->regular expression
sub ftor
{
	my ($a, $b) = @_;
	return undef unless $a < $b;
	$b--;
	my $d = $b - $a;
	my @a = split //, $a;
	my @b = split //, $b;
	my $out;
	while (@b > @a) {
		$out .= shift @b;
	}
	while (@b) {
		my $aa = shift @a;
		my $bb = shift @b;
		if (@b < (length $d)) {
			$out .= '\\d';
		} elsif ($aa eq $bb) {
			$out .= $aa;
		} elsif ($aa < $bb) {
			$out .= "[$aa-$bb]";
		} else {
			$out .= "[0-$bb$aa-9]";
		}
	}
	return $out;
}

# format a spot for user output in list mode
sub formatl
{
	my $t = ztime($_[2]);
	my $d = cldate($_[2]);
	return sprintf "%8.1f  %-11s %s %s  %-28.28s%7s>", $_[0], $_[1], $d, $t, ($_[3]||''), "<$_[4]" ;
}

#
# return all the spots from a day's file as an array of references
# the parameter passed is a julian day
sub readfile($)
{
	my @spots;
	
	my $fh = $fp->open(shift); 
	if ($fh) {
		my $in;
		while (<$fh>) {
			chomp;
			push @spots, [ split '\^' ];
		}
	}
	return @spots;
}

# enter the spot for dup checking and return true if it is already a dup
sub dup {
	my ($freq, $call, $d, $text, $by, $node) = @_; 

	# dump if too old
	return 2 if $d < $main::systime - $dupage;
	
	# turn the time into minutes (should be already but...)
	$d = int ($d / 60);
	$d *= 60;

	# remove SSID or area
	$by =~ s|[-/]\d+$||;
	
#	$freq = sprintf "%.1f", $freq;       # normalise frequency
	$freq = int $freq;       # normalise frequency
	$call = substr($call, 0, $maxcalllth) if length $call > $maxcalllth;

	chomp $text;
	$text =~ s/\%([0-9A-F][0-9A-F])/chr(hex($1))/eg;
	$text = uc unpad($text);
	my $otext = $text;
#	$text = Encode::encode("iso-8859-1", $text) if $main::can_encode && Encode::is_utf8($text, 1);
	$text =~ s/^\+\w+\s*//;			# remove leading LoTW callsign
	$text =~ s/\s{2,}[\dA-Z]?[A-Z]\d?$// if length $text > 24;
	$text =~ s/[\W\x00-\x2F\x7B-\xFF]//g; # tautology, just to make quite sure!
	$text = substr($text, 0, $duplth) if length $text > $duplth; 
	my $ldupkey = "X$|$call|$by|$node|$freq|$d|$text";
	my $t = DXDupe::find($ldupkey);
	return 1 if $t && $t - $main::systime > 0;
	
	DXDupe::add($ldupkey, $main::systime+$dupage);
	$otext = substr($otext, 0, $duplth) if length $otext > $duplth; 
	$otext =~ s/\s+$//;
	if (length $otext && $otext ne $text) {
		$ldupkey = "X$freq|$call|$by|$otext";
		$t = DXDupe::find($ldupkey);
		return 1 if $t && $t - $main::systime > 0;
		DXDupe::add($ldupkey, $main::systime+$dupage);
	}
	return 0;
}

sub listdups
{
	return DXDupe::listdups('X', $dupage, @_);
}

sub genstats($)
{
	my $date = shift;
	my $in = $fp->open($date);
	my $out = $statp->open($date, 'w');
	my @freq;
	my %list;
	my @tot;
	
	if ($in && $out) {
		my $i = 0;
		@freq = map {[$i++, Bands::get_freq($_)]} qw(136khz 160m 80m 60m 40m 30m 20m 17m 15m 12m 10m 6m 4m 2m 220 70cm 23cm 13cm 9cm 6cm 3cm 12mm 6mm);
		while (<$in>) {
			chomp;
			my ($freq, $by, $dxcc) = (split /\^/)[0,4,6];
			my $ref = $list{$by} || [0, $dxcc];
			for (@freq) {
				next unless defined $_;
				if ($freq >= $_->[1] && $freq <= $_->[2]) {
					$$ref[$_->[0]+2]++;
					$tot[$_->[0]+2]++;
					$$ref[0]++;
					$tot[0]++;
					$list{$by} = $ref;
					last;
				}
			}
		}

		for ($i = 0; $i < @freq+2; $i++) {
			$tot[$i] ||= 0;
		}
		$statp->write($date, join('^', 'TOTALS', @tot));

		for (sort {$list{$b}->[0] <=> $list{$a}->[0]} keys %list) {
			my $ref = $list{$_};
			my $call = $_;
			for ($i = 0; $i < @freq+2; ++$i) {
				$ref->[$i] ||= 0;
			}
			$statp->write($date, join('^', $call, @$ref));
		}
		$statp->close;
	}
}

# return true if the stat file is newer than than the spot file
sub checkstats($)
{
	my $date = shift;
	my $in = $fp->mtime($date);
	my $out = $statp->mtime($date);
	return defined $out && defined $in && $out >= $in;
}

# daily processing
sub daily
{
	my $date = Julian::Day->new($main::systime)->sub(1);
	genstats($date) unless checkstats($date);
}
1;




