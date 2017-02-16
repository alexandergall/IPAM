#!/usr/bin/perl -w

use strict;
use CGI;
use FileHandle;

my $IPAM_BASE = '/home/noc/IPAM';
my (@handles, @output);
my $cmd;
my $content_type = 'text/plain';
sub error($;$);
sub error_400(;$);
sub error_500(;$);
sub error_501(;$);

my $q = CGI->new();
for (my $i = 0; $i < 2; $i++) {
  open($handles[$i], '+>', undef) or error_500("Can't open temporary file: $!");
}
$ENV{REQUEST_METHOD} eq 'GET' or error_501();
my @parms = $q->param();
$parms[0] eq 'cmd' or error_400('Missing cmd parameter');
shift(@parms);
if ($parms[0] eq 'base') {
  my $path = $q->param('base');
  $IPAM_BASE = $path;
  shift(@parms);
}
$ENV{IPAM_BASE} = $IPAM_BASE;
my $IPAM_BIN = $IPAM_BASE.'/bin';
my @args;
foreach my $parm (@parms) {
  my $arg = $q->param($parm);
  push(@args, "$parm".($arg ? "=$arg" : ''));
}

if ($q->param('cmd') eq 'dump') {
  $cmd = "cd $IPAM_BASE && make dump-from-archive";
  $content_type = 'application/xml';
} else {
  if ($q->param('--json')) {
    $content_type = 'application/json';
  }
  $cmd = $IPAM_BIN.'/'.'ipam-'.$q->param('cmd');
  -x $cmd or error_400("Command $cmd does not exist or is not executable");
}

open(OLDOUT, ">&STDOUT");
open(OLDERR, ">&STDERR");
open(STDOUT, '>&'.$handles[0]->fileno());
open(STDERR, '>&'.$handles[1]->fileno());
my $rc = system($cmd, @args) & 0xffff;
open(STDOUT, ">&OLDOUT");
open(STDERR, ">&OLDERR");
close(OLDOUT);
close(OLDERR);
for (my $i = 0; $i < 2; $i++) {
  $handles[$i]->seek(0, 0);
  @{$output[$i]} = $handles[$i]->getlines();
  $handles[$i]->close()
}
if ($rc != 0) {
  my $reason;
  if ($rc == 0xffff) {
    $reason = "$!";
  } else {
    if (($rc & 0xff) == 0) {
      $rc >>= 8;
      $reason = "exit code $rc";
    } else {
      $rc &= ~0x80;
      $reason = "signal $rc";
    }
  }
  error_400(sprintf("Command \"%s\" failed (%s)\n%s%s",
  		    $cmd.' '.join(' ', @parms), $reason,
  		    join('', @{$output[0]}),
  		    join('', @{$output[1]})));
}
print $q->header($content_type);
print @{$output[0]};
exit(0);

sub error($;$) {
  my ($status, $msg) = @_;
  print $q->header(-type => 'text/plain',
		   -status => $status);
  $msg && print $msg;
  exit(1);
}

sub error_400(;$) {
  my ($msg) = @_;
  error('400 Bad Request', $msg);
}

sub error_500(;$) {
  my ($msg) = @_;
  error('500 Internal Server Error', $msg);
}

sub error_501(;$) {
  my ($msg) = @_;
  error('501 Not Implemented', $msg);
}

## Local Variables:
## mode: CPerl
## End:
