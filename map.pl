#!/usr/bin/perl

###
#map EXPR, LIST
#map BLOCK list
###


use strict;
use warnings;

my @myNames=('jacob','alexander','ethen','andrew');
my $len=scalar(@myNames);
print("The array length is $len\n");

my @ucnames=map(ucfirst,@myNames);
foreach my $name(@ucnames){
	print "$name\n";
}

$len=@ucnames;
print("$len\n");


my @books = ('Prideand Prejudice','Emma', 'Masfield Park','Senseand Sensibility','Nothanger Abbey',
'Persuasion',  'Lady Susan','Sanditon','The Watsons');
my @words=map{split(/\s+/,$_)}@books;
my @upperwords=map(uc,@words);
foreach my $ucword(@upperwords){
	print "$ucword\n";
}





