#!/usr/bin/perl

#####Auther: Cheng Lin Guang 
####Date:2015-09-28


use strict;
use warnings;
use MIME::Lite;


my $result_1="";
my $result_2="";
my $line="";
my @result_1_arr;
my @result_2_arr;
my $result_1_com="";
my $result_2_com="";
my $count=0;
my $file_count=0;
my @minute_count;
$minute_count[0]=0;
$minute_count[1]=0;
$minute_count[2]=0;
#my $contactSMS = '+6593576719';
my $contactEmail = 'yktay@singtel.com,stevenyong@singtel.com,swee.keng.aw@ericsson.com,kenny.k.wong@ericsson.com,david.yip@ericsson.com,patrick.pabeda@ericsson.com,lorical.goh@ericsson.com,eric.z.yin@ericsson.com,+6597806544@sms.ericsson.com';
#my $contactEmail='853059006@qq.com,chris.l.cheng@ericsson.com';
#my $contactEmail = 'david.yip@ericsson.com,chris.l.cheng@ericsson.com';
my $subject="[PMA Alert] PMA service issue detected";
my $message="";
my $message_re="";
my @new_lines;
my $time_stamp;
my $rsftp = "/opt/ericsson/itk/bin/rsftp";


sub get_localtime{
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime time;
        $mon++;
        $year += 1900;
        $mon = sprintf("%02d", $mon);
        $mday = sprintf("%02d", $mday);
        $hour = sprintf("%02d", $hour);
        $min = sprintf("%02d", $min);
        my $local_time="$year$mon$mday$hour$min";
        my $local_date="$year$mon$mday";
#        return ($local_time,$local_date);
        return $local_time;
}

$time_stamp=get_localtime();
print "time_stamp is $time_stamp\n";
my $file_dir="/home/itk/echglig/ossmon/file/$time_stamp";
if(-d $file_dir){
	print("folder already exits\n");	
}else{
	mkdir $file_dir;
}
sub getfiles{
	my $cmd="$rsftp -d -delete -dir $file_dir  sftp://eca:ecastm\@localhost:20023//home/eca/echglig/OSSMONITOR/log/2*.txt";
	open FH, "$cmd 2>&1 |" or die "Failed to open pipeline";
	while(<FH>) {
        	print;
        	next unless /(INFO:) ([^ ]+) transferred successfully/;
        	#open(IN,"/home/itk/echglig/ossmon/file/$2");
        	#close(IN);
	}
	close FH;
}
sub analyzefiles{
	my $folder=shift;
	my $result_1;
	my $result_2;
	my @result_1_arr;
	my @result_2_arr;
	my $result_1_com;
	my $result_2_com;
	my @result_1_com_arr;
	my @result_2_com_arr;
	my $sub_count=0;
	my $sub_message;
	chdir($folder);
	my @files=glob "*";
	#print "@files";
	foreach my $file(@files){
		open(IN,$file);
		my @lines=<IN>;
		foreach $line(@lines){
			if($line=~/nmsadm/ and $line!~/AlarmReceptionFile/i){
				$result_1=$line;
				chomp($result_1);	
			}elsif($line=~/nmsadm/ and $line=~/AlarmReceptionFile/i){
				$result_2=$line;
				chomp($result_2);	
			}	
		}
		@result_1_arr=split(/\s+/,$result_1);
		@result_2_arr=split(/\s+/,$result_2);
		$result_1_com="$result_1_arr[5]"."-"."$result_1_arr[6]"."-"."$result_1_arr[7]";
	       	$result_2_com="$result_2_arr[5]"."-"."$result_2_arr[6]"."-"."$result_2_arr[7]";
		@result_1_com_arr=split(/\:/,$result_1_arr[7]);
		@result_2_com_arr=split(/\:/,$result_2_arr[7]);
		if($result_1_com ne $result_2_com){
			$minute_count[$file_count]=($result_2_com_arr[0]-$result_1_com_arr[0])*60+($result_2_com_arr[1]-$result_1_com_arr[1]);
			$sub_count=$sub_count+1;	
			$message="/var/opt/ericsson/pmData/alarmData"."\n"."$result_1"."\n"."/etc/opt/ericsson/fm/txf/Process/txf_ENIQ_adapt_1/Interface"."\n"."$result_2"."\n";
		}			
		close(IN);
	$file_count=$file_count+1;
	}	
	return $sub_count;
	
}


sub SendMessage{
	my $eMail = MIME::Lite->new(From => 'Auto OSS check', To => $_[0], Subject => $_[1], Type => 'text/html', Data => $_[2]);
	$eMail->send('smtp', 'smtp.eamcs.ericsson.se', Timeout => 60);
}


getfiles();
$count=analyzefiles("$file_dir");

if(($count>2)&&(($minute_count[0]>1)||($minute_count[0]<-1))&&(($minute_count[1]>1)||($minute_count[1]<-1))&&(($minute_count[2]>1)||($minute_count[2]<-1))){
	print("Sending Message to users\n");
	SendMessage($contactEmail,$subject,$message);		
}else{
	print "count=$count\n";
}




