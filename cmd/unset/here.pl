#
# unset the here flag
#
# Copyright (c) 1998 - Dirk Koopman
#
# $Id$
#

my ($self, $line) = @_;
my @args = split /\s+/, $line;
my $call;
my @out;

@args = $self->call if (!@args || $self->priv < 9);

foreach $call (@args) {
  $call = uc $call;
  my $dxchan = DXChannel->get($call);
  my $ref = DXCluster->get($call);
  if ($dxchan && $ref) {
	$dxchan->here(0);
    $ref->here(0);
	DXProt::broadcast_all_ak1a(DXProt::pc24($ref), $DXProt::me);
	push @out, $self->msg('hereu', $call);
  } else {
    push @out, $self->msg('e3', "Unset Here", $call);
  }
}
return (1, @out);
