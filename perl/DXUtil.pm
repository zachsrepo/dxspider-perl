#
# various utilities which are exported globally
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

package DXUtil;

use Date::Parse;
use IO::File;
use File::Copy;
use Data::Dumper;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/ ) || 0;
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw(@month %patmap @ISA @EXPORT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(atime ztime cldate cldatetime slat slong yesno promptf 
			 parray parraypairs phex shellregex readfilestr writefilestr
			 filecopy
             print_all_fields cltounix unpad is_callsign is_latlong
			 is_qra is_freq is_digits is_pctext is_pcflag insertitem deleteitem
            );


@month = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
%patmap = (
		   '*' => '.*',
		   '?' => '.',
		   '[' => '[',
		   ']' => ']'
);

# a full time for logging and other purposes
sub atime
{
	my $t = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = gmtime((defined $t) ? $t : time);
	$year += 1900;
	my $buf = sprintf "%02d%s%04d\@%02d:%02d:%02d", $mday, $month[$mon], $year, $hour, $min, $sec;
	return $buf;
}

# get a zulu time in cluster format (2300Z)
sub ztime
{
	my $t = shift;
	$t = defined $t ? $t : time;
	my $dst = shift;
	my ($sec,$min,$hour) = $dst ? localtime($t): gmtime($t);
	my $buf = sprintf "%02d%02d%s", $hour, $min, ($dst) ? '' : 'Z';
	return $buf;
}

# get a cluster format date (23-Jun-1998)
sub cldate
{
	my $t = shift;
	$t = defined $t ? $t : time;
	my $dst = shift;
	my ($sec,$min,$hour,$mday,$mon,$year) = $dst ? localtime($t) : gmtime($t);
	$year += 1900;
	my $buf = sprintf "%2d-%s-%04d", $mday, $month[$mon], $year;
	return $buf;
}

# return a cluster style date time
sub cldatetime
{
	my $t = shift;
	my $dst = shift;
	my $date = cldate($t, $dst);
	my $time = ztime($t, $dst);
	return "$date $time";
}

# return a unix date from a cluster date and time
sub cltounix
{
	my $date = shift;
	my $time = shift;
	my ($thisyear) = (gmtime)[5] + 1900;

	return 0 unless $date =~ /^\s*(\d+)-(\w\w\w)-([12][90]\d\d)$/;
	return 0 if $3 > 2036;
	return 0 unless abs($thisyear-$3) <= 1;
	$date = "$1 $2 $3";
	return 0 unless $time =~ /^([012]\d)([012345]\d)Z$/;
	$time = "$1:$2 +0000";
	my $r = str2time("$date $time");
	return $r unless $r;
	return $r == -1 ? undef : $r;
}

# turn a latitude in degrees into a string
sub slat
{
	my $n = shift;
	my ($deg, $min, $let);
	$let = $n >= 0 ? 'N' : 'S';
	$n = abs $n;
	$deg = int $n;
	$min = int ((($n - $deg) * 60) + 0.5);
	return "$deg $min $let";
}

# turn a longitude in degrees into a string
sub slong
{
	my $n = shift;
	my ($deg, $min, $let);
	$let = $n >= 0 ? 'E' : 'W';
	$n = abs $n;
	$deg = int $n;
	$min = int ((($n - $deg) * 60) + 0.5);
	return "$deg $min $let";
}

# turn a true into 'yes' and false into 'no'
sub yesno
{
	my $n = shift;
	return $n ? $main::yes : $main::no;
}

# format a prompt with its current value and return it with its privilege
sub promptf
{
	my ($line, $value) = @_;
	my ($priv, $prompt, $action) = split ',', $line;

	# if there is an action treat it as a subroutine and replace $value
	if ($action) {
		my $q = qq{\$value = $action(\$value)};
		eval $q;
	} elsif (ref $value) {
		my $dd = new Data::Dumper([$value]);
		$dd->Indent(0);
		$dd->Terse(1);
		$dd->Quotekeys(0);
		$value = $dd->Dumpxs;
	}
	$prompt = sprintf "%15s: %s", $prompt, $value;
	return ($priv, $prompt);
}

# turn a hex field into printed hex
sub phex
{
	my $val = shift;
	return sprintf '%X', $val;
}

# take an arg as an array list and print it
sub parray
{
	my $ref = shift;
	return join(', ', @{$ref});
}

# take the arg as an array reference and print as a list of pairs
sub parraypairs
{
	my $ref = shift;
	my $i;
	my $out;
  
	for ($i = 0; $i < @$ref; $i += 2) {
		my $r1 = @$ref[$i];
		my $r2 = @$ref[$i+1];
		$out .= "$r1-$r2, ";
	}
	chop $out;					# remove last space
	chop $out;					# remove last comma
	return $out;
}

sub _sort_fields
{
	my $ref = shift;
	my @a = split /,/, $ref->field_prompt(shift); 
	my @b = split /,/, $ref->field_prompt(shift); 
	return lc $a[1] cmp lc $b[1];
}

# print all the fields for a record according to privilege
#
# The prompt record is of the format '<priv>,<prompt>[,<action>'
# and is expanded by promptf above
#
sub print_all_fields
{
	my $self = shift;			# is a dxchan
	my $ref = shift;			# is a thingy with field_prompt and fields methods defined
	my @out;
	my @fields = $ref->fields;
	my $field;
	my $width = $self->width - 1;
	$width ||= 80;

	foreach $field (sort {_sort_fields($ref, $a, $b)} @fields) {
		if (defined $ref->{$field}) {
			my ($priv, $ans) = promptf($ref->field_prompt($field), $ref->{$field});
			my @tmp;
			if (length $ans > $width) {
				my ($p, $a) = split /: /, $ans, 2;
				my $l = (length $p) + 2;
				my $al = ($width - 1) - $l;
				my $bit;
				while (length $a > $al ) {
					($bit, $a) = unpack "A$al A*", $a;
					push @tmp, "$p: $bit";
					$p = ' ' x ($l - 2);
				}
				push @tmp, "$p: $a" if length $a;
			} else {
				push @tmp, $ans;
			}
			push @out, @tmp if ($self->priv >= $priv);
		}
	}
	return @out;
}

# generate a regex from a shell type expression 
# see 'perl cookbook' 6.9
sub shellregex
{
	my $in = shift;
	$in =~ s{(.)} { $patmap{$1} || "\Q$1" }ge;
	return '^' . $in . "\$";
}

# read in a file into a string and return it. 
# the filename can be split into a dir and file and the 
# file can be in upper or lower case.
# there can also be a suffix
sub readfilestr
{
	my ($dir, $file, $suffix) = @_;
	my $fn;
	my $f;
	if ($suffix) {
		$f = uc $file;
		$fn = "$dir/$f.$suffix";
		unless (-e $fn) {
			$f = lc $file;
			$fn = "$dir/$file.$suffix";
		}
	} elsif ($file) {
		$f = uc $file;
		$fn = "$dir/$file";
		unless (-e $fn) {
			$f = lc $file;
			$fn = "$dir/$file";
		}
	} else {
		$fn = $dir;
	}

	my $fh = new IO::File $fn;
	my $s = undef;
	if ($fh) {
		local $/ = undef;
		$s = <$fh>;
		$fh->close;
	}
	return $s;
}

# write out a file in the format required for reading
# in via readfilestr, it expects the same arguments 
# and a reference to an object
sub writefilestr
{
	my $dir = shift;
	my $file = shift;
	my $suffix = shift;
	my $obj = shift;
	my $fn;
	my $f;
	
	confess('no object to write in writefilestr') unless $obj;
	confess('object not a reference in writefilestr') unless ref $obj;
	
	if ($suffix) {
		$f = uc $file;
		$fn = "$dir/$f.$suffix";
		unless (-e $fn) {
			$f = lc $file;
			$fn = "$dir/$file.$suffix";
		}
	} elsif ($file) {
		$f = uc $file;
		$fn = "$dir/$file";
		unless (-e $fn) {
			$f = lc $file;
			$fn = "$dir/$file";
		}
	} else {
		$fn = $dir;
	}

	my $fh = new IO::File ">$fn";
	if ($fh) {
		my $dd = new Data::Dumper([ $obj ]);
		$dd->Indent(1);
		$dd->Terse(1);
		$dd->Quotekeys(0);
		#	$fh->print(@_) if @_ > 0;     # any header comments, lines etc
		$fh->print($dd->Dumpxs);
		$fh->close;
	}
}

sub filecopy
{
	copy(@_) or return $!;
}

# remove leading and trailing spaces from an input string
sub unpad
{
	my $s = shift;
	$s =~ s/\s+$//;
	$s =~ s/^\s+//;
	return $s;
}

# check that a field only has callsign characters in it
sub is_callsign
{
	return $_[0] =~ /^(?:[A-Z]{1,2}\d+|\d[A-Z]\d+)[A-Z]{1,3}(?:-\d{1,2}|\/(?:[A-Z]{1,2}\d{0,2}|\d[A-Z]\d{0,2}))?$/;
}

# check that a PC protocol field is valid text
sub is_pctext
{
	return undef if $_[0] =~ /[\x00-\x08\x0a-\x1f\xf0-\xff]/;
	return $_[0];
}

# check that a PC prot flag is fairly valid (doesn't check the difference between 1/0 and */-)
sub is_pcflag
{
	return $_[0] =~ /^[01\*\-]+$/;
}

# check that a thing is a frequency
sub is_freq
{
	return $_[0] =~ /^\d+(?:\.\d+)?$/;
}

# check that a thing is just digits
sub is_digits
{
	return $_[0] =~ /^[\d]+$/;
}

# does it look like a qra locator?
sub is_qra
{
	return $_[0] =~ /^[A-Za-z][A-Za-z]\d\d[A-Za-z][A-Za-z]$/o;
}

# does it look like a valid lat/long
sub is_latlong
{
	return $_[0] =~ /^\s*\d{1,2}\s+\d{1,2}\s*[NnSs]\s+\d{1,2}\s+\d{1,2}\s*[EeWw]\s*$/;
}

# insert an item into a list if it isn't already there returns 1 if there 0 if not
sub insertitem
{
	my $list = shift;
	my $item = shift;
	
	return 1 if grep {$_ eq $item } @$list;
	push @$list, $item;
	return 0;
}

# delete an item from a list if it is there returns no deleted 
sub deleteitem
{
	my $list = shift;
	my $item = shift;
	my $n = @$list;
	
	@$list = grep {$_ ne $item } @$list;
	return $n - @$list;
}
