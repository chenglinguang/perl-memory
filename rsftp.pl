#!/usr/bin/perl
###----------------------------------------------------------------------------
#
# Tool to download files via FTP and SFTP
#
#
# Author: Cheng Linguang
#rsftp 2014-05-26 06:39:17Z

use strict;
use Itk::Logger;

use Getopt::Long;
use Cwd 'abs_path','getcwd';
use Itk::Server;
use Itk::Utils::FileTransfer;

our $srv = Itk::Server->new(admincheck=>0);

sub usage {
        my $msg = shift;
        print "ERROR: $msg\n" if $msg;
        print <<_EOT_;
rsftp: Automate an [S]FTP file download using URI

Usage:
  rsftp [-dir <directory>] [-q] [-delete] [-timeout] <url>

    <url> : URL to the files to fetch
     -dir : Directory to store files
       -q : Quiet.  Suppress output
  -delete : Delete the files if they are successfully fetched.
       -d : Debug mode
 -timeout : Timeout (secs)

URL details are of the form:
  protocol://username:password\@host:port//dir/file

Example
  sftp://test:test987\@127.0.0.1:2220//home/itk/spool/xmlspool/*.gz

_EOT_
        exit ($msg ? -1 : 0);
}

#------------------------------------------------------------------------------
# MAIN
#------------------------------------------------------------------------------
my ($help, $out_dir, $delete, $quiet, $debug, $timeout);
GetOptions(
        "h|help"        => \$help,
        "dir=s"         => \$out_dir,
        "q"                     => \$quiet,
        "d"                     => \$debug,
        "delete"                => \$delete,
        "timeout=s"             => \$timeout,
) or usage("Invalid Options");

usage if $help;

my $url = shift @ARGV;
usage "URL must be specified." unless ($url);

$out_dir = getcwd() unless ($out_dir);
$out_dir = abs_path($out_dir);

unless ($url =~ m'^(sftp|ftp|file)://([^/]*)/(.*)$'i) {
        logError("Invalid URL: $url");
        die();
}
my ($scheme, $server, $path) = (lc($1), $2, $3);

unless ($path =~ m'^((.+)/)?([^/]+)$') {
        logError("Invalid path: $path");
        die();
}
my ($ssh_dir, $ssh_file) = ($2, $3);

unless ($server =~ m'^(([^:]+)(:([^@]+))?@)?([^:]+)(:(.+))?$') {
        logError("Invalid login info: $server");
        die();
}
my ($ssh_user, $ssh_pass, $ssh_host, $ssh_port) = ($2, $4, $5, $7);

$ssh_port = 22 if (not $ssh_port and $scheme eq 'sftp');
$ssh_port = 21 if (not $ssh_port and $scheme eq 'ftp');
$timeout = 90 unless defined $timeout;

$ssh_file =~ s/^\*/^\.\*/;
$ssh_file =~ s/([^\.])\*/$1\.\*/g;
$ssh_file = '.*' unless $ssh_file;

logInfo("Username: $ssh_user  Password: $ssh_pass  Host: $ssh_host   Port:  $ssh_port") if $debug;
logInfo("Remote Directory: $ssh_dir") if $debug;
logInfo("Local Directory: $out_dir") if $debug;
logInfo("Using $ssh_file regex file match") if $debug;

my $ssh_file_re = qr/$ssh_file/i;

my $num_transferred = 0;
my $file_count = 0;
eval {
        my $sftpObject;
        if($scheme eq 'sftp') {
                $sftpObject = new Itk::Utils::SFTP(host => $ssh_host,  port => $ssh_port, timeout => $timeout) or die "Failed to connect to $ssh_host\n";
        }elsif($scheme eq 'ftp') {
                $sftpObject = new Itk::Utils::FTP(host => $ssh_host,  port => $ssh_port, timeout => $timeout) or die "Failed to connect to $ssh_host\n";
        }

        $sftpObject->login("$ssh_user","$ssh_pass");
        my $filelist = $sftpObject->dirStat("$ssh_dir");
        use Data::Dumper;
        #logInfo("File list = " . Dumper($filelist)) if $debug;
        logInfo("Retreiving file list") if $debug;
        foreach my $file (@$filelist) {
                next unless $file->{name} =~ $ssh_file_re;
                next if $file->{name} =~ /^\.?\.$/;
                $file_count++;
                logInfo("Adding $file->{name}") if $debug;
                logInfo("$ssh_dir/$file->{name} => $out_dir/$file->{name}") if $debug;
                my $fetchResult = $sftpObject->get("$ssh_dir/$file->{name}","$out_dir/$file->{name}");
                if ($fetchResult) {
                        $num_transferred++;
                        logInfo("$file->{name} transferred successfully") unless $quiet;
                        if($delete) {
                                if($sftpObject->delete("$ssh_dir/$file->{name}")) {
                                        logInfo("$file->{name} deleted successfully") if $debug;
                                } else {
                                        logError("$file->{name} delete failed") unless $quiet;
                                }
                        }
                }
        }
        $sftpObject->quit();
};
if ($@) {
        logError("FileFetching failed: $@");
} else {
        logInfo("Files transferred: $num_transferred / $file_count") unless $quiet;
}

