#
# set the name of the user
#
# Copyright (c) 1998 - Dirk Koopman
#
# $Id$
#

my ($self, $line) = @_;
my $call = $self->call;
my $user;

# remove leading and trailing spaces
$line =~ s/^\s+//;
$line =~ s/\s+$//;
$line =~ s/[{}]//g;   # no braces allowed

return (1, $self->msg('qthe1')) if !$line;

$user = DXUser->get_current($call);
if ($user) {
	$user->qth($line);
	$user->put();
	DXProt::broadcast_all_ak1a(DXProt::pc41($call, 2, $line), $DXProt::me);
	return (1, $self->msg('qth', $line));
} else {
	return (1, $self->msg('namee2', $call));
}

