#!/usr/bin/perl
#
# pretend that you are another user, useful for reseting
# those silly things that people insist on getting wrong
# like set/homenode et al
#
# Copyright (c) 1999 Dirk Koopman G1TLH
#
my ($self, $line) = @_;

my $mycall = $self->call;
my $myuser = $self->user;

my ($call, $newline) = split /\s+/, $line, 2;
return (1, $self->msg('nodee1', $call)) if DXChannel->get($call);

if ($self->remotecmd) {
	Log('DXCommand', "$mycall is trying to spoof $call remotely");
	return (1, $self->msg('e5'));
}
if ($self->priv < 9) {
	Log('DXCommand', "$mycall is trying to spoof $call locally");
	return (1, $self->msg('e5'));
}

my @out;
$call = uc $call;
my $user = DXUser->get($call);
unless ($user) {
	$user = DXUser->new($call);
	push @out, $self->msg('spf1', $call);
}

# set up basic environment
$self->call($call);
$self->user($user);
Log('DXCommand', "spoof '$newline' as $call by $mycall");
my @in = $self->run_cmd($newline);
push @out, map {"spoof $call: $_"} @in;
$self->call($mycall);
$self->user($myuser);

return (1, @out);