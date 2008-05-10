#
# set list of bad dx spotters
#
# Copyright (c) 1998 - Dirk Koopman G1TLH
#
#
#
my ($self, $line) = @_;
return (1, $self->msg('e5')) if $self->remotecmd;
# are we permitted?
return (1, $self->msg('e5')) if $self->priv < 6;
$line = join(' ', map {s|[/-]\d+$||; $_} split(/\s+/, $line));
return $DXProt::badspotter->set(8, $self->msg('e6'), $self, $line);

