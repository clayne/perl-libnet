#!perl

use 5.008001;

use strict;
use warnings;

use File::Temp 'tempfile';
use Net::POP3;
use Test::More;

my $debug = 0; # Net::POP3->new( Debug => .. )

my $inet6class = Net::POP3->can_inet6;
plan skip_all => "no IPv6 support found in Net::POP3" if ! $inet6class;

plan skip_all => "fork not supported on this platform"
  if grep { $^O =~m{$_} } qw(MacOS VOS vmesa riscos amigaos);

my $srv = $inet6class->new(
  LocalAddr => '::1',
  Listen => 10
);
plan skip_all => "cannot create listener on ::1: $!" if ! $srv;
my $saddr = "[".$srv->sockhost."]".':'.$srv->sockport;
diag("server on $saddr");

plan tests => 1;

defined( my $pid = fork()) or die "fork failed: $!";
exit(pop3_server()) if ! $pid;

my $cl = Net::POP3->new($saddr, Debug => $debug);
diag("created Net::POP3 object");
if (!$cl) {
  fail("IPv6 POP3 connect failed");
} else {
  $cl->quit;
  pass("IPv6 success");
}
wait;

sub pop3_server {
  my $cl = $srv->accept or die "accept failed: $!";
  print $cl "+OK localhost ready\r\n";
  while (<$cl>) {
    my ($cmd,$arg) = m{^(\S+)(?: +(.*))?\r\n} or die $_;
    $cmd = uc($cmd);
    if ($cmd eq 'QUIT' ) {
      print $cl "+OK bye\r\n";
      last;
    } elsif ( $cmd eq 'CAPA' ) {
      print $cl "+OK\r\n".
	".\r\n";
    } else {
      diag("received unknown command: $cmd");
      print "-ERR unknown cmd\r\n";
    }
  }

  diag("POP3 dialog done");
}
