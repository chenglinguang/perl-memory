#!/usr/bin/perl
# Create SSH tunnel through RSG to remote machine
# Author£ºCheng LinGuang
# Date: 2012-10-15 

# rtunnel [-p <localport>] [-rp <rsgport>] <remotehost>

use strict;
use Expect;
use Getopt::Long;
use Fcntl ':mode';

#------------------------Config--------------------------
my $ssh_cmd="/usr/bin/ssh";
my $default_localport = 8022;
my $default_rsgport = 19486;
my $ssh_port       = 22;                # Destination port (22 for SSH)
my $t1             = 30;           # Timeout between commands
my $keepalivetimer = 180;          # Number of seconds between keepalive transmissions to ssg
my %hostinfo;
#------------------------Subs----------------------------
sub usage {
        my $msg = shift;
        print "ERROR: $msg\n" if $msg;
        print <<_EOT_;

rtunnel: Establish SSH tunnel through RSG

Usage:

rtunnel [-p <localport>] [-rp <rsgport>] [-q] [-g] [-logrem] [-exec <cmd>] [-d] <remotehost>

<remotehost>  : Host in target network
-p <localport>: Port on local machine that will be forwarded
                Default: $default_localport

-rp <rsgport> : Port on RSG that will be forwarded (use 'auto' since RSG 5.0)
                Default: $default_rsgport

-h, -help     : Print this message

-q            : Quiet mode, no output

-g            : Allows remote hosts to connect to local forwarded ports

-logrem       : Logs into the remote host before going to sleep

-exec <cmd>   : Executes the given command after the tunnel has been
                established, and then close the tunnel and quit.

-d            : Debug mode, ssh session is logged to stdout

-pidfile <file>: Output PID to given file (useful for later killing)

Remote host details (IP address, username and password) will be read from
.rsg_hosts in the users home directory. This file should contain one line
per host, with the following fields separated by whitespace:
<Name> <Type> <Path> <IP> <username> <password> [<prompt>]
Where:
  - Type = egw, ssg or host
  - Path = <egw>:<ssg> for a host, otherwise use -
  - Prompt is a regular expression inside double quotes ("") that matches
    the prompt for egw and ssg. If not specified defaults will be used.
  - If the password is '-' then you will be prompted for it (useful for networks
    using one time password generators / tokens)
  - If the SSG password is '"' then the EGW password will be used for the SSG
Any line starting with '#' is assumed to be a comment.

_EOT_
        exit ($msg ? -1 : 0);
}

sub readCfg {
        my $cfg_file=shift;
        #Handling for issue #1677 - don't allow execution unless config file is ONLY accessible
        #by this user (as with .ssh/authorized_keys)
        my $mode = (stat($cfg_file))[2];
        if ($mode & S_IRWXG or $mode & S_IRWXO) {  #if accessible by anyone apart from this user
#               die "Access refused: bad ownership or modes for file $cfg_file\n";
                print "WARN: Configuration error: bad ownership or modes for file $cfg_file\n";
        }
        my ($host,$type,$path,$ip,$usr,$pwd, $prompt);
        open CFG,"<$cfg_file" or die "Failed to open $cfg_file\n";
        while (<CFG>) {
                next if (/^\s*#/);
                next if (/^\s*$/);
                if (not (($host, $type, $path, $ip, $usr, $pwd, $prompt) = /(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+"(.+)"/)) {
                        ($host, $type, $path, $ip, $usr, $pwd, $prompt) = split;
                }
                die "Error in config file: bad type $type on line $., $cfg_file\n" unless ($type =~ /egw|ssg|host/);

                # Default prompts
                if (not $prompt) {
                        $prompt="egw >" if ($type eq 'egw');
                        $prompt="$host >" if ($type eq 'ssg');
                }

                $hostinfo{lc $host}={
                        'type'=>$type,
                        'path'=>$path,
                        'ip'=>$ip,
                        'user'=>$usr,
                        'password'=>$pwd,
                        'prompt' => $prompt
                };
        }
        close CFG;
}

sub getNodeConnectionDetails {
        my $target = shift;
        my ($rsg,$ssg);

        die "Unknown Host: $target\n" unless exists $hostinfo{$target};
        die "Target $target is not a remote host (type=$hostinfo{$target}->{type})\n" if $hostinfo{$target}->{type} ne 'host';
        (($rsg,$ssg) = split ":",$hostinfo{$target}->{path}) or die "Bad path specification for $target: $hostinfo{$target}->{path}\n";
        die "Unknown RSG $rsg for $target\n" unless exists $hostinfo{$rsg};
        die "Unknown SSG $rsg for $target\n" unless exists $hostinfo{$ssg};
        return ($rsg, $hostinfo{$rsg}->{ip}, $hostinfo{$rsg}->{user}, $hostinfo{$rsg}->{password}, $hostinfo{$rsg}->{prompt},
                $ssg, $hostinfo{$ssg}->{ip}, $hostinfo{$ssg}->{user}, $hostinfo{$ssg}->{password}, $hostinfo{$ssg}->{prompt},
                $hostinfo{$target}->{ip}, $hostinfo{$target}->{user}, $hostinfo{$target}->{password}, $hostinfo{$target}->{prompt});
}

sub getPasswd {
        my $prompt=shift;
        print $prompt;
        system "stty -echo";
        my $word;
        chomp($word = <STDIN>);
        print "\n";
        system "stty echo";
        return $word;
}
#------------------------------------------------------------------------------
# MAIN
#------------------------------------------------------------------------------
my ($help, $localport, $rsgport, $quiet, $debug, $pidfile, $allowrh, $execCmd, $logrem);
GetOptions(
        "h|help"        => \$help,
        "p=s"           => \$localport,
        "rp=s"          => \$rsgport,
        "q"             => \$quiet,
        "d"             => \$debug,
        "exec=s"        => \$execCmd,
        "g"             => \$allowrh,
        "logrem"        => \$logrem,
        "pidfile=s"     => \$pidfile
) or usage("Invalid Options");

usage if $help;

my $rem_host = shift @ARGV;
usage "Remote Host must be specified." unless ($rem_host);
$localport = $default_localport unless ($localport);
$rsgport = $default_rsgport unless ($rsgport);

my $cfg_file="$ENV{'HOME'}/.rsg_hosts";
readCfg($cfg_file);

if ($pidfile) {
        open PIDFILE,">$pidfile" or die "Could not write to pidfile $pidfile\n";
        print PIDFILE "$$\n";
        close PIDFILE;
}

my ($rsg, $rsg_ip, $rsg_usr, $rsg_pwd, $rsg_prompt, $ssg, $ssg_host, $ssg_usr, $ssg_pwd, $ssg_prompt,
        $rem_ip, $rem_usr, $rem_pwd, $rem_prompt) = getNodeConnectionDetails($rem_host);

#------------------------------------------------------------------------------
# Stage 1: Log into EGW
#------------------------------------------------------------------------------
$rsg_pwd=getPasswd("Enter RSG Password: ") if ($rsg_pwd eq '-');
my $sshPortFwdArg;
if ($rsgport eq 'auto') {
        # Since RSG 5.0, dynamic port forwarding allows for an easier setup.
        # We just specify the local port and the final customer address/port,
        # and RSG sets up the EGW/SSG mappings as appropriate.
        $sshPortFwdArg = "-L$localport:$rem_ip:$ssh_port";
} else {
        $sshPortFwdArg = "-L$localport:localhost:$rsgport"
}
my @expectArgs = ($ssh_cmd,$sshPortFwdArg,"$rsg_usr\@$rsg_ip");
push(@expectArgs, '-g') if $allowrh;
my $ssh = new Expect(@expectArgs) or die "Could not spawn SSH process ($ssh_cmd)\n";
$ssh->log_stdout($debug ? 1 : 0);
$ssh->expect($t1,

        # First case comes up if this is the first time you have connected to this
        # RSG. SSH will ask if you want to add the key to knownhosts
        [ qr/Are you sure you want to continue connecting \(yes\/no\)\?/, sub {
                my $self=shift;
                $self->send("yes\n");
                print STDERR "EGW added to known hosts\n" unless $quiet;
                exp_continue;
                } ],

        [ qr/word:|CODE:/, sub {
                my $self=shift;
                $self->send("$rsg_pwd\n");
                exp_continue;
                } ],
        -re, $rsg_prompt
) or die("Failed logging into EGW!");
print STDERR "Logged into EGW\n" if (! $quiet);

unless ($rsgport eq 'auto') {
        # Add port forwarding!
        $ssh->send("add $rsgport $rem_ip $ssh_port\n");
        $ssh->expect($t1,$rsg_prompt) or die("Could not add port forwardings into EGW\n");
}

#------------------------------------------------------------------------------
# Stage 2: Log into SSG
#------------------------------------------------------------------------------
$ssg_pwd=getPasswd("Enter SSG Password: ") if ($ssg_pwd eq '-');
$ssg_pwd=$rsg_pwd if ($ssg_pwd eq '"');
$ssh->send("ssh $ssg_host\n");
$ssh->expect($t1,

        [ qr/\(yes\/no\)\s\[no\]:/, sub {
                my $self=shift;
                $self->send("yes\n");
                exp_continue;
                } ],

        [ qr/word:|CODE:/, sub {
                my $self=shift;
                $ssh->send("$ssg_pwd\n");
                exp_continue;
        } ],

        [ qr/(Wait.*tokencode:)/s, sub {
                my $self=shift;
                $ssg_pwd=getPasswd($1);
                $ssh->send("$ssg_pwd\n");
                exp_continue;
        } ],

        -re, $ssg_prompt
) or die("Failed logging into SSG");
print STDERR "Logged into SSG\n" if (! $quiet);

#------------------------------------------------------------------------------
# Stage 3: Log into REM HOST
#------------------------------------------------------------------------------
if ($logrem) {
        $ssh->send("ssh $rem_ip $rem_usr\n");
        $ssh->expect($t1,

                [ qr/\(yes\/no\)\s\[no\]:/, sub {
                        my $self=shift;
                        $self->send("yes\n");
                        exp_continue;
                } ],

                [ qr/word:|CODE:/, sub {
                        my $self=shift;
                        $ssh->send("$rem_pwd\n");
                        exp_continue;
                } ],

                -re, $rem_prompt
        ) or die("Failed logging into Rem Host");
        print STDERR "Logged into Rem Host\n" if (! $quiet);
}

if ($execCmd) {  #if just running a command
        print STDERR "Executing '$execCmd'\n" unless $quiet;
        system($execCmd);
} else {  #wait here until further notice
        # Set a null handler for SIGINT
        # then go to sleep - we will wake up if any signal is recieved
        print STDERR "Going to sleep..\n" unless $quiet;
        my $interrupted = 0;
        $SIG{'INT'} = sub { $interrupted=1; };
        while (! $interrupted) {
                sleep $keepalivetimer;
                $ssh->send("\n");
        }
        $SIG{'INT'} = 'DEFAULT'; # restore default signal handling so user can interrupt us
}

if ($logrem) {
        $ssh->send("exit\n");
        $ssh->expect($t1, " >") or die("Failed to exit from Remote Host");
}

$ssh->send("exit\n");
$ssh->expect($t1, " >") or die("Failed to exit from SSG");
$ssh->send("exit\n");
print "Exited from RSG\n" unless $quiet;
unlink $pidfile if $pidfile;


