#!perl

use 5.008001;

use strict;
use warnings;

use File::Temp 'tempfile';
use Net::NNTP;
use Test::More;

my $debug = 0; # Net::NNTP Debug => ..

my $parent = 0;

plan skip_all => "no SSL support found in Net::NNTP" if ! Net::NNTP->can_ssl;

plan skip_all => "fork not supported on this platform"
  if grep { $^O =~m{$_} } qw(MacOS VOS vmesa riscos amigaos);

plan skip_all => "incomplete or version of IO::Socket::SSL"
  if ! eval { require IO::Socket::SSL::Utils };

my $srv = IO::Socket::INET->new(
  LocalAddr => '127.0.0.1',
  Listen => 10
);
plan skip_all => "cannot create listener on localhost: $!" if ! $srv;
my $host = $srv->sockhost;
my $port = $srv->sockport;

plan tests => 2;

my ($ca,$key) = IO::Socket::SSL::Utils::CERT_create( CA => 1 );
my ($fh,$cafile) = tempfile();
print $fh IO::Socket::SSL::Utils::PEM_cert2string($ca);
close($fh);

$parent = $$;
END { unlink($cafile) if $$ == $parent }

my ($cert) = IO::Socket::SSL::Utils::CERT_create(
  subject => { CN => 'nntp.example.com' },
  issuer_cert => $ca, issuer_key => $key,
  key => $key
);

test(1); # direct ssl
test(0); # starttls


sub test {
  my $ssl = shift;
  defined( my $pid = fork()) or die "fork failed: $!";
  exit(nntp_server($ssl)) if ! $pid;
  nntp_client($ssl);
  wait;
}


sub nntp_client {
  my $ssl = shift;
  my %sslopt = (
    SSL_verifycn_name => 'nntp.example.com',
    SSL_ca_file => $cafile
  );
  $sslopt{SSL} = 1 if $ssl;
  my $cl = Net::NNTP->new(
    Host => $host,
    Port => $port,
    Debug => $debug,
    %sslopt,
  );
  diag("created Net::NNTP object");
  if (!$cl) {
    fail( ($ssl ? "SSL ":"" )."NNTP connect failed");
  } elsif ($ssl) {
    $cl->quit;
    pass("SSL NNTP connect success");
  } elsif ( ! $cl->starttls ) {
    no warnings 'once';
    fail("starttls failed: $IO::Socket::SSL::SSL_ERROR");
  } else {
    $cl->quit;
    pass("starttls success");
  }
}

sub nntp_server {
  my $ssl = shift;
  my $cl = $srv->accept or die "accept failed: $!";
  my %sslargs = (
    SSL_server => 1,
    SSL_cert => $cert,
    SSL_key => $key,
  );
  if ( $ssl ) {
    if ( ! IO::Socket::SSL->start_SSL($cl, %sslargs)) {
      diag("initial ssl handshake with client failed");
      return;
    }
  }

  print $cl "200 nntp.example.com\r\n";
  while (<$cl>) {
    my ($cmd,$arg) = m{^(\S+)(?: +(.*))?\r\n} or die $_;
    $cmd = uc($cmd);
    if ($cmd eq 'QUIT' ) {
      print $cl "205 bye\r\n";
      last;
    } elsif ( $cmd eq 'MODE' ) {
      print $cl "201 Posting denied\r\n";
    } elsif ( ! $ssl and $cmd eq 'STARTTLS' ) {
      print $cl "382 Continue with TLS negotiation\r\n";
      if ( ! IO::Socket::SSL->start_SSL($cl, %sslargs)) {
	diag("initial ssl handshake with client failed");
	return;
      }
      $ssl = 1;
    } else {
      diag("received unknown command: $cmd");
      print "500 unknown cmd\r\n";
    }
  }

  diag("NNTP dialog done");
}
