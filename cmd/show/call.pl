#
# Query the PineKnot Database server for a callsign
#
# from an idea by Steve Franke K9AN and information from Angel EA7WA
#
# $Id$
#
my ($self, $line) = @_;
my @list = split /\s+/, $line;		      # generate a list of callsigns
my $l;
my @out;

use Net::Telnet;

my $t = new Net::Telnet;

push @out, $self->msg('call1');
foreach $l (@list) {
	$t->open(Host     =>  "jeifer.pineknot.com",
			 Port     =>  1235,
			 Timeout  =>  5);
	if ($t) {
		$t->print(uc $l);
		while (my $result = $t->getline) {
			push @out,$result;
		}
		$t->close;
	} else {
		push @out, $self->msg('e18', 'PineKnot');
	}
}

return (1, @out);