#
# module to manage the band list
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
# $Id$
#

package Bands;

use DXUtil;
use DXDebug;
use DXVars;
use Carp;

use strict;
use vars qw(%bands %regions $bandsfn %valid);

%bands = ();   # the 'raw' band data
%regions = ();  # list of regions for shortcuts eg vhf ssb
$bandsfn = "$main::data/bands.pl";

%valid = (
  cw => '0,CW,parraypairs',
  ssb => '0,SSB,parraypairs',
  data => '0,DATA,parraypairs,parraypairs',
  sstv => '0,SSTV,parraypairs',
  fstv => '0,FSTV,parraypairs',
  rtty => '0,RTTY,parraypairs',
  pactor => '0,PACTOR,parraypairs',
  packet => '0,PACKET,parraypairs',
  repeater => '0,REPEATER,parraypairs',
  fax => '0,FAX,parraypairs',
  beacon => '0,BEACON,parraypairs',
  band => '0,BAND,parraypairs',
);

# load the band data
sub load
{
  %bands = ();
  do $bandsfn;
  confess $@ if $@;
}

# obtain a band object by callsign [$obj = Band::get($call)]
sub get
{
  my $call = shift;
  return $bands{$call};
}

# obtain all the band objects
sub get_all
{
  return values(%bands);
}

# get all the band keys
sub get_keys
{
  return keys(%bands);
}

# get all the frequency pairs associated with the band and sub-band offered
# the band can be a region, sub-band can be missing
# 
# called Bands::get_freq(band-label, subband-label)
sub get_freq
{
  my ($band, $subband) = @_;
  my @band;
  my $b;
  my @out;
  return () if !$band;
  $subband = 'band' if !$subband;
  
  # first look in the region
  $b = $regions{$band};
  @band = @$b if $b;
  @band = ($band) if @band == 0;
  
  # we now have a list of bands to scan for sub bands
  foreach $b (@band) {
    my $wb = $bands{$b};
	if ($wb) {
	  my $sb = $wb->{$subband};
	  push @out, @$sb if $sb;
	}
  }
  return @out;
}

#
# return a list of valid elements 
# 

sub fields
{
  return keys(%valid);
}

#
# return a prompt for a field
#

sub field_prompt
{ 
  my ($self, $ele) = @_;
  return $valid{$ele};
}

no strict;
sub AUTOLOAD
{
  my $self = shift;
  my $name = $AUTOLOAD;
  return if $name =~ /::DESTROY$/;
  $name =~ s/.*:://o;
  
  @_ ? $self->{$name} = shift : $self->{$name} ;
}

1;
