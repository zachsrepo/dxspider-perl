#
# This has been taken from the 'Advanced Perl Programming' book by Sriram Srinivasan 
#
# I am presuming that the code is distributed on the same basis as perl itself.
#
# I have modified it to suit my devious purposes (Dirk Koopman G1TLH)
#
# $Id$
#

package Msg;

use strict;
use IO::Select;
use IO::Socket;
#use DXDebug;

use vars qw(%rd_callbacks %wt_callbacks $rd_handles $wt_handles);

%rd_callbacks = ();
%wt_callbacks = ();
$rd_handles   = IO::Select->new();
$wt_handles   = IO::Select->new();
my $blocking_supported = 0;

BEGIN {
    # Checks if blocking is supported
    eval {
        require POSIX; POSIX->import(qw (F_SETFL O_NONBLOCK EAGAIN));
    };
    $blocking_supported = 1 unless $@;
}

#-----------------------------------------------------------------
# Send side routines
sub connect {
    my ($pkg, $to_host, $to_port,$rcvd_notification_proc) = @_;
    
    # Create a new internet socket
    
    my $sock = IO::Socket::INET->new (
                                      PeerAddr => $to_host,
                                      PeerPort => $to_port,
                                      Proto    => 'tcp',
                                      Reuse    => 1);

    return undef unless $sock;

    # Create a connection end-point object
    my $conn = {
        sock                   => $sock,
        rcvd_notification_proc => $rcvd_notification_proc,
    };
    
    if ($rcvd_notification_proc) {
        my $callback = sub {_rcv($conn)};
        set_event_handler ($sock, "read" => $callback);
    }
    return bless $conn, $pkg;
}

sub disconnect {
    my $conn = shift;
    my $sock = delete $conn->{sock};
    return unless defined($sock);
    set_event_handler ($sock, "read" => undef, "write" => undef);
    shutdown($sock, 3);
	close($sock);
}

sub send_now {
    my ($conn, $msg) = @_;
    _enqueue ($conn, $msg);
    $conn->_send (1); # 1 ==> flush
}

sub send_later {
    my ($conn, $msg) = @_;
    _enqueue($conn, $msg);
    my $sock = $conn->{sock};
    return unless defined($sock);
    set_event_handler ($sock, "write" => sub {$conn->_send(0)});
}

sub _enqueue {
    my ($conn, $msg) = @_;
    # prepend length (encoded as network long)
    my $len = length($msg);
	$msg =~ s/([\%\x00-\x1f\x7f-\xff])/sprintf("%%%02X", ord($1))/eg; 
    push (@{$conn->{queue}}, $msg . "\n");
}

sub _send {
    my ($conn, $flush) = @_;
    my $sock = $conn->{sock};
    return unless defined($sock);
    my ($rq) = $conn->{queue};

    # If $flush is set, set the socket to blocking, and send all
    # messages in the queue - return only if there's an error
    # If $flush is 0 (deferred mode) make the socket non-blocking, and
    # return to the event loop only after every message, or if it
    # is likely to block in the middle of a message.

    $flush ? $conn->set_blocking() : $conn->set_non_blocking();
    my $offset = (exists $conn->{send_offset}) ? $conn->{send_offset} : 0;

    while (@$rq) {
        my $msg            = $rq->[0];
		my $mlth           = length($msg);
        my $bytes_to_write = $mlth - $offset;
        my $bytes_written  = 0;
		confess("Negative Length! msg: '$msg' lth: $mlth offset: $offset") if $bytes_to_write < 0;
        while ($bytes_to_write > 0) {
            $bytes_written = syswrite ($sock, $msg,
                                       $bytes_to_write, $offset);
            if (!defined($bytes_written)) {
                if (_err_will_block($!)) {
                    # Should happen only in deferred mode. Record how
                    # much we have already sent.
                    $conn->{send_offset} = $offset;
                    # Event handler should already be set, so we will
                    # be called back eventually, and will resume sending
                    return 1;
                } else {    # Uh, oh
					delete $conn->{send_offset};
                    $conn->handle_send_err($!);
					$conn->disconnect;
                    return 0; # fail. Message remains in queue ..
                }
            }
            $offset         += $bytes_written;
            $bytes_to_write -= $bytes_written;
        }
        delete $conn->{send_offset};
        $offset = 0;
        shift @$rq;
        last unless $flush; # Go back to select and wait
                            # for it to fire again.
    }
    # Call me back if queue has not been drained.
    if (@$rq) {
        set_event_handler ($sock, "write" => sub {$conn->_send(0)});
    } else {
        set_event_handler ($sock, "write" => undef);
    }
    1;  # Success
}

sub _err_will_block {
    if ($blocking_supported) {
        return ($_[0] == EAGAIN());
    }
    return 0;
}
sub set_non_blocking {                        # $conn->set_blocking
    if ($blocking_supported) {
        # preserve other fcntl flags
        my $flags = fcntl ($_[0], F_GETFL(), 0);
        fcntl ($_[0], F_SETFL(), $flags | O_NONBLOCK());
    }
}
sub set_blocking {
    if ($blocking_supported) {
        my $flags = fcntl ($_[0], F_GETFL(), 0);
        $flags  &= ~O_NONBLOCK(); # Clear blocking, but preserve other flags
        fcntl ($_[0], F_SETFL(), $flags);
    }
}

sub handle_send_err {
   # For more meaningful handling of send errors, subclass Msg and
   # rebless $conn.  
   my ($conn, $err_msg) = @_;
   warn "Error while sending: $err_msg \n";
   set_event_handler ($conn->{sock}, "write" => undef);
}

#-----------------------------------------------------------------
# Receive side routines

my ($g_login_proc,$g_pkg);
my $main_socket = 0;
sub new_server {
    @_ == 4 || die "Msg->new_server (myhost, myport, login_proc)\n";
    my ($pkg, $my_host, $my_port, $login_proc) = @_;
    
    $main_socket = IO::Socket::INET->new (
                                          LocalAddr => $my_host,
                                          LocalPort => $my_port,
                                          Listen    => 5,
                                          Proto     => 'tcp',
                                          Reuse     => 1);
    die "Could not create socket: $! \n" unless $main_socket;
    set_event_handler ($main_socket, "read" => \&_new_client);
    $g_login_proc = $login_proc; $g_pkg = $pkg;
}

sub _rcv {                     # Complement to _send
    my $conn = shift; # $rcv_now complement of $flush
    # Find out how much has already been received, if at all
    my ($msg, $offset, $bytes_to_read, $bytes_read);
    my $sock = $conn->{sock};
    return unless defined($sock);

	my @lines;
    $conn->set_non_blocking();
	$bytes_read = sysread ($sock, $msg, 1024, 0);
	if (defined ($bytes_read)) {
		if ($bytes_read > 0) {
			if ($msg =~ /\n/) {
				@lines = split /\n/, $msg;
				$lines[0] = $conn->{msg} . $lines[0] if $conn->{msg};
				if ($msg =~ /\n$/) {
					delete $conn->{msg};
				} else {
					$conn->{msg} = pop @lines;
				}
			} else {
				$conn->{msg} .= $msg;
			}
		} 
	} else {
		if (_err_will_block($!)) {
			return ; 
		} else {
			$bytes_read = 0;
		}
    }

FINISH:
    if (defined $bytes_read && $bytes_read == 0) {
#		$conn->disconnect();
		&{$conn->{rcvd_notification_proc}}($conn, undef, $!);
		@lines = ();
    } 

	while (@lines){
		$msg = shift @lines;
		$msg =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
		&{$conn->{rcvd_notification_proc}}($conn, $msg, $!);
		$! = 0;
	}
}

sub _new_client {
    my $sock = $main_socket->accept();
    my $conn = bless {
        'sock' =>  $sock,
        'state' => 'connected'
    }, $g_pkg;
    my $rcvd_notification_proc =
        &$g_login_proc ($conn, $sock->peerhost(), $sock->peerport());
    if ($rcvd_notification_proc) {
        $conn->{rcvd_notification_proc} = $rcvd_notification_proc;
        my $callback = sub {_rcv($conn)};
        set_event_handler ($sock, "read" => $callback);
    } else {  # Login failed
        $conn->disconnect();
    }
}

sub close_server
{
	set_event_handler ($main_socket, "read" => undef);
	$main_socket->close;
	$main_socket = 0;
}

#----------------------------------------------------
# Event loop routines used by both client and server

sub set_event_handler {
    shift unless ref($_[0]); # shift if first arg is package name
    my ($handle, %args) = @_;
    my $callback;
    if (exists $args{'write'}) {
        $callback = $args{'write'};
        if ($callback) {
            $wt_callbacks{$handle} = $callback;
            $wt_handles->add($handle);
        } else {
            delete $wt_callbacks{$handle};
            $wt_handles->remove($handle);
        }
    }
    if (exists $args{'read'}) {
        $callback = $args{'read'};
        if ($callback) {
            $rd_callbacks{$handle} = $callback;
            $rd_handles->add($handle);
        } else {
            delete $rd_callbacks{$handle};
            $rd_handles->remove($handle);
       }
    }
}

sub event_loop {
    my ($pkg, $loop_count, $timeout) = @_; # event_loop(1) to process events once
    my ($conn, $r, $w, $rset, $wset);
    while (1) {
        # Quit the loop if no handles left to process
        last unless ($rd_handles->count() || $wt_handles->count());
        ($rset, $wset) =
            IO::Select->select ($rd_handles, $wt_handles, undef, $timeout);
        foreach $r (@$rset) {
            &{$rd_callbacks{$r}} ($r) if exists $rd_callbacks{$r};
        }
        foreach $w (@$wset) {
            &{$wt_callbacks{$w}}($w) if exists $wt_callbacks{$w};
        }
        if (defined($loop_count)) {
            last unless --$loop_count;
        }
    }
}

1;

__END__

