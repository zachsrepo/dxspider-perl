#
# Polled Timer handling
#
# This uses callbacks. BE CAREFUL!!!!
#
#
#
# Copyright (c) 2001 Dirk Koopman G1TLH
#

package Timer;

use vars qw(@timerchain $notimers $lasttime);
use DXDebug;

@timerchain = ();
$notimers = 0;

$lasttime = 0;

sub new
{
    my ($pkg, $time, $proc, $recur) = @_;
	my $obj = ref($pkg);
	my $class = $obj || $pkg;
	my $self = bless { t=>$time + time, proc=>$proc }, $class;
	$self->{interval} = $time if $recur;
	push @timerchain, $self;
	$notimers++;
	dbg("Timer created ($notimers)") if isdbg('connll');
	return $self;
}

sub del
{
	my $self = shift;
	delete $self->{proc};
	@timerchain = grep {$_ != $self} @timerchain;
}

sub handler
{
	my $now = time;

	return unless $now != $lasttime;

	# handle things on the timer chain
	my $t;
	foreach $t (@timerchain) {
		if ($now >= $t->{t}) {
			&{$t->{proc}}();
			$t->{t} = $now + $t->{interval} if exists $t->{interval};
		}
	}

	$lasttime = $now;
}

sub DESTROY
{
	dbg("timer destroyed ($Timer::notimers)") if isdbg('connll');
	$Timer::notimers--;
}
1;
