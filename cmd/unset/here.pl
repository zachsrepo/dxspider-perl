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
  my $ref = DXCluster->get($call);
  if ($ref) {
    $ref->here(0);
	DXProt::broadcast_ak1a(DXProt::pc24($ref));
	push @out, DXM::msg('hereu', $call);
  } else {
    push @out, DXM::msg('e3', "Unset Here", $call);
  }
}
return (1, @out);
