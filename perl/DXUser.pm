#
# DX cluster user routines
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

package DXUser;

require Exporter;
@ISA = qw(Exporter);

use DXLog;
use DB_File;
use Data::Dumper;
use Fcntl;
use IO::File;
use DXDebug;

use strict;
use vars qw(%u $dbm $filename %valid);

%u = ();
$dbm = undef;
$filename = undef;

# hash of valid elements and a simple prompt
%valid = (
		  call => '0,Callsign',
		  alias => '0,Real Callsign',
		  name => '0,Name',
		  qth => '0,Home QTH',
		  lat => '0,Latitude,slat',
		  long => '0,Longitude,slong',
		  qra => '0,Locator',
		  email => '0,E-mail Address',
		  priv => '9,Privilege Level',
		  lastin => '0,Last Time in,cldatetime',
		  passwd => '9,Password',
		  addr => '0,Full Address',
		  'sort' => '0,Type of User', # A - ak1a, U - User, S - spider cluster, B - BBS
		  xpert => '0,Expert Status,yesno',
		  bbs => '0,Home BBS',
		  node => '0,Last Node',
		  homenode => '0,Home Node',
		  lockout => '9,Locked out?,yesno',	# won't let them in at all
		  dxok => '9,Accept DX Spots?,yesno', # accept his dx spots?
		  annok => '9,Accept Announces?,yesno', # accept his announces?
		  reg => '0,Registered?,yesno',	# is this user registered?
		  lang => '0,Language',
		  hmsgno => '0,Highest Msgno',
		  group => '0,Access Group,parray',	# used to create a group of users/nodes for some purpose or other
		  isolate => '9,Isolate network,yesno',
		  wantbeep => '0,Rec Beep,yesno',
		  wantann => '0,Rec Announce,yesno',
		  wantwwv => '0,Rec WWV,yesno',
		  wantwcy => '0,Rec WCY,yesno',
		  wantecho => '0,Rec Echo,yesno',
		  wanttalk => '0,Rec Talk,yesno',
		  wantwx => '0,Rec WX,yesno',
		  wantdx => '0,Rec DX Spots,yesno',
		  pagelth => '0,Current Pagelth',
		  pingint => '9,Node Ping interval',
		  nopings => '9,Ping Obs Count',
		  wantlogininfo => '9,Login info req,yesno',
	          wantgrid => '0,DX Grid Info,yesno',
		  lastoper => '9,Last for/oper,cldatetime',
		 );

no strict;
sub AUTOLOAD
{
	my $self = shift;
	my $name = $AUTOLOAD;
  
	return if $name =~ /::DESTROY$/;
	$name =~ s/.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" if !$valid{$name};
	if (@_) {
		$self->{$name} = shift;
	}
	return $self->{$name};
}

#
# initialise the system
#
sub init
{
	my ($pkg, $fn, $mode) = @_;
  
	confess "need a filename in User" if !$fn;
	$fn .= ".v2";
	if ($mode) {
		$dbm = tie (%u, 'DB_File', $fn, O_CREAT|O_RDWR, 0666, $DB_BTREE) or confess "can't open user file: $fn ($!)";
	} else {
		$dbm = tie (%u, 'DB_File', $fn, O_RDONLY, 0666, $DB_BTREE) or confess "can't open user file: $fn ($!)";
	}
	
	$filename = $fn;
}

use strict;

#
# close the system
#

sub finish
{
	undef $dbm;
	untie %u;
}

#
# new - create a new user
#

sub new
{
	my $pkg = shift;
	my $call = uc shift;
	#  $call =~ s/-\d+$//o;
  
#	confess "can't create existing call $call in User\n!" if $u{$call};

	my $self = bless {}, $pkg;
	$self->{call} = $call;
	$self->{'sort'} = 'U';
	$self->put;
	return $self;
}

#
# get - get an existing user - this seems to return a different reference everytime it is
#       called - see below
#

sub get
{
	my $pkg = shift;
	my $call = uc shift;
	#  $call =~ s/-\d+$//o;       # strip ssid
	my $s = $u{$call};
	return $s ?  decode($s) : undef;
}

#
# get all callsigns in the database 
#

sub get_all_calls
{
	return (sort keys %u);
}

#
# get an existing either from the channel (if there is one) or from the database
#
# It is important to note that if you have done a get (for the channel say) and you
# want access or modify that you must use this call (and you must NOT use get's all
# over the place willy nilly!)
#

sub get_current
{
	my $pkg = shift;
	my $call = uc shift;
	#  $call =~ s/-\d+$//o;       # strip ssid
  
	my $dxchan = DXChannel->get($call);
	return $dxchan->user if $dxchan;
	return get($pkg, $call);
}

#
# put - put a user
#

sub put
{
	my $self = shift;
	confess "Trying to put nothing!" unless $self && ref $self;
	my $call = $self->{call};
	# delete all instances of this 
	for ($dbm->get_dup($call)) {
		$dbm->del_dup($call, $_);
	}
	delete $self->{annok} if $self->{annok};
	delete $self->{dxok} if $self->{dxok};
	$u{$call} = $self->encode();
	$dbm->sync;
}

# 
# create a string from a user reference
#
sub encode
{
	my $self = shift;
	my $dd = new Data::Dumper([$self]);
	$dd->Indent(0);
	$dd->Terse(1);
    $dd->Quotekeys($] < 5.005 ? 1 : 0);
	return $dd->Dumpxs;
}

#
# create a hash from a string
#
sub decode
{
	my $s = shift;
	my $ref;
	$s = '$ref = ' . $s;
	eval $s;
	Log('DXUser', $@) if $@;
	$ref = undef if $@;
	return $ref;
}

#
# del - delete a user
#

sub del
{
	my $self = shift;
	my $call = $self->{call};
	# delete all instances of this 
	for ($dbm->get_dup($call)) {
		$dbm->del_dup($call, $_);
	}
	$dbm->sync;
}

#
# close - close down a user
#

sub close
{
	my $self = shift;
	$self->{lastin} = time;
	$self->put();
}

#
# return a list of valid elements 
# 

sub fields
{
	return keys(%valid);
}


#
# export the database to an ascii file
#

sub export
{
	my $fn = shift;
	
	# save old ones
        rename "$fn.oooo", "$fn.ooooo" if -e "$fn.oooo";
        rename "$fn.ooo", "$fn.oooo" if -e "$fn.ooo";
        rename "$fn.oo", "$fn.ooo" if -e "$fn.oo";
        rename "$fn.o", "$fn.oo" if -e "$fn.o";
        rename "$fn", "$fn.o" if -e "$fn";

	my $count = 0;
	my $fh = new IO::File ">$fn" or return "cannot open $fn ($!)";
	if ($fh) {
		my $ref;
		my $key;
		my $action;
		my $t = scalar localtime;
		print $fh "#!/usr/bin/perl
#
# The exported userfile for a DXSpider System
#
# Input file: $filename
#       Time: $t
#

package DXUser;

%u = (
";

		for ($action = R_FIRST; !$dbm->seq($key, $ref, $action); $action = R_NEXT) {
			print $fh "'$key' => $ref,\n";
			++$count;
		} 
		print $fh ");\n#\n# there were $count records\n#\n";
		$fh->close;
	} 
	return $count;
}

#
# group handling
#

# add one or more groups
sub add_group
{
	my $self = shift;
	my $ref = $self->{group} || [ 'local' ];
	$self->{group} = $ref if !$self->{group};
	push @$ref, @_ if @_;
}

# remove one or more groups
sub del_group
{
	my $self = shift;
	my $ref = $self->{group} || [ 'local' ];
	my @in = @_;
	
	$self->{group} = $ref if !$self->{group};
	
	@$ref = map { my $a = $_; return (grep { $_ eq $a } @in) ? () : $a } @$ref;
}

# does this thing contain all the groups listed?
sub union
{
	my $self = shift;
	my $ref = $self->{group};
	my $n;
	
	return 0 if !$ref || @_ == 0;
	return 1 if @$ref == 0 && @_ == 0;
	for ($n = 0; $n < @_; ) {
		for (@$ref) {
			my $a = $_;
			$n++ if grep $_ eq $a, @_; 
		}
	}
	return $n >= @_;
}

# simplified group test just for one group
sub in_group
{
	my $self = shift;
	my $s = shift;
	my $ref = $self->{group};
	
	return 0 if !$ref;
	return grep $_ eq $s, $ref;
}

# set up a default group (only happens for them's that connect direct)
sub new_group
{
	my $self = shift;
	$self->{group} = [ 'local' ];
}

#
# return a prompt for a field
#

sub field_prompt
{ 
	my ($self, $ele) = @_;
	return $valid{$ele};
}

# some variable accessors
sub sort
{
	my $self = shift;
	@_ ? $self->{'sort'} = shift : $self->{'sort'} ;
}

# some accessors
sub _want
{
	my $n = shift;
	my $self = shift;
	my $val = shift;
	my $s = "want$n";
	$self->{$s} = $val if defined $val;
	return exists $self->{$s} ? $self->{$s} : 1;
}

sub wantbeep
{
	return _want('beep', @_);
}

sub wantann
{
	return _want('ann', @_);
}

sub wantwwv
{
	return _want('wwv', @_);
}

sub wantwcy
{
	return _want('wcy', @_);
}

sub wantecho
{
	return _want('echo', @_);
}

sub wantwx
{
	return _want('wx', @_);
}

sub wantdx
{
	return _want('dx', @_);
}

sub wanttalk
{
	return _want('talk', @_);
}

sub wantgrid
{
	return _want('grid', @_);
}

sub wantlogininfo
{
	my $self = shift;
	my $n = shift;
	$self->{wantlogininfo} = $n if $n;
	return exists $self->{wantlogininfo} ? $self->{wantlogininfo} : 0;
}

sub is_node
{
	my $self = shift;
	return $self->{sort} =~ /[ACRSX]/;
}

sub is_user
{
	my $self = shift;
	return $self->{sort} eq 'U';
}

sub is_bbs
{
	my $self = shift;
	return $self->{sort} eq 'B';
}

sub is_spider
{
	my $self = shift;
	return $self->{sort} eq 'S';
}

sub is_clx
{
	my $self = shift;
	return $self->{sort} eq 'C';
}

sub is_dxnet
{
	my $self = shift;
	return $self->{sort} eq 'X';
}

sub is_arcluster
{
	my $self = shift;
	return $self->{sort} eq 'R';
}

sub is_ak1a
{
	my $self = shift;
	return $self->{sort} eq 'A';
}
1;
__END__





