#
# show a list of all the outstanding wwv dups
# for debugging really
#
# Copyright (c) 2000 Dirk Koopman G1TLH
#
# $Id$
#
my $self = shift;
my $line = shift;
return (1, $self->msg('e5')) unless $self->priv >= 9; 
return (1, Geomag::listdups $line);
