#
# User routing routines
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#
# $Id$
# 

package Route::User;

use DXDebug;
use Route;

use strict;

use vars qw($VERSION $BRANCH);
$VERSION = sprintf( "%d.%03d", q$Revision$ =~ /(\d+)\.(\d+)/ );
$BRANCH = sprintf( "%d.%03d", q$Revision$ =~ /\d+\.\d+\.(\d+)\.(\d+)/ ) || 0;
$main::build += $VERSION;
$main::branch += $BRANCH;

use vars qw(%list %valid @ISA $max $filterdef);
@ISA = qw(Route);

%valid = (
		  parent => '0,Parent Calls,parray',
);

$filterdef = $Route::filterdef;
%list = ();
$max = 0;

sub count
{
	my $n = scalar(keys %list);
	$max = $n if $n > $max;
	return $n;
}

sub max
{
	count();
	return $max;
}

sub new
{
	my $pkg = shift;
	my $call = uc shift;
	my $ncall = uc shift;
	my $flags = shift;
	confess "already have $call in $pkg" if $list{$call};
	
	my $self = $pkg->SUPER::new($call);
	$self->{parent} = [ $ncall ];
	$self->{flags} = $flags;
	$list{$call} = $self;

	return $self;
}

sub get_all
{
	return values %list;
}

sub del
{
	my $self = shift;
	my $pref = shift;
	$self->delparent($pref);
	unless (@{$self->{parent}}) {
		delete $list{$self->{call}};
		return $self;
	}
	return undef;
}

sub get
{
	my $call = shift;
	$call = shift if ref $call;
	my $ref = $list{uc $call};
	dbg("Failed to get User $call" ) if !$ref && isdbg('routerr');
	return $ref;
}

sub addparent
{
	my $self = shift;
    return $self->_addlist('parent', @_);
}

sub delparent
{
	my $self = shift;
    return $self->_dellist('parent', @_);
}

#
# generic AUTOLOAD for accessors
#

sub AUTOLOAD
{
	no strict;

	my $self = shift;
	$name = $AUTOLOAD;
	return if $name =~ /::DESTROY$/;
	$name =~ s/.*:://o;
  
	confess "Non-existant field '$AUTOLOAD'" unless $valid{$name} || $Route::valid{$name};

	# this clever line of code creates a subroutine which takes over from autoload
	# from OO Perl - Conway
#	*{$AUTOLOAD} = sub {@_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name}} ;
    @_ ? $self->{$name} = shift : $self->{$name} ;
}

1;
