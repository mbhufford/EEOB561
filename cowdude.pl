#!/usr/bin/perl

 ########################################################################
#                                                                        #                                
#  Copyright (C) 2010 Jeffrey Ross-Ibarra <rossibarra@ucdavis.edu>       #
#                                                                        #
#  This program is free software: you can redistribute it and/or modify  #
#  it under the terms of the GNU General Public License as published by  #
#  the Free Software Foundation, either version 3 of the License, or     #
#  (at your option) any later version.                                   #
#                                                                        #
#  This program is distributed in the hope that it will be useful,       #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of        #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         #
#  GNU General Public License <http://www.gnu.org/licenses/>             #
#  for more details.                                                     #
#                                                                        #                                  
 ########################################################################

##TO DO

#CHANGELOG since v1.0
# fixed bug in reading tab-delim text files from excel
# moos with version number
# now checks to see if inserted IDs are already in database
# prints out wrongly formatted IDs
# finds and returns most recent ID numbers
# minor change to errors -- no longer dies but just skips bad IDs
# strip spaces at end of IDs from barcode reader
# added ability to update coldboxes/drybags

use strict;
#use warnings;
use DBD::mysql;
use DBI;

#COWDUDE Version
my $version="1.1";
if ( $ARGV[0] eq "-v" ){
	'say Moo';
	die "This is version $version of cowdude.\n\n";
}
my $table="Samples";
$table="toy" if $ARGV[0] eq "--toy";

#gets user desktop directory
my $udir=`cd ~; pwd`; 
chomp $udir; 
$udir = $udir . "/Desktop";
print "\nWelcome to COWDUDE!  You can exit at any time by pressing Ctrl-C.\n";
my $done="Y";

while( $done eq "Y"){
	my $choice=&promptUser("\nDo you want to insert samples (I), update samples (U), query IDs (Q), or make barcodes (B)?",qq/I,U,B,Q/);
	
	#update
	if( $choice eq "U" ){
		my $dnas=&promptUser("Do you want to update sample status (S) or DNA values (D)?",qq/S,D/);
		&update if $dnas eq "S";
		&dna if $dnas eq "D";	
	}
	
	#barcode
	if( $choice eq "B" ){
		print "\nPaste in the list of accessions or IDs for which you want to generate barcodes (then hit return and press Ctrl-D):\n\n";
		my @text = <STDIN>;
		&barcode(\@text);
	}
	
	#query
	if( $choice eq "Q" ){
		print "\nPaste in the list of accessions or IDs for which you want to query to find the most recent ID (then hit return and press Ctrl-D):\n\n";
		my @text = <STDIN>;
		print "\nAccession\tMost Recent\n---------\t-----------\n";

		foreach my $i (@text){
			chomp $i;
			$i=~s/\s//g;
			my $recent=&recent($i);
			if ($recent == -1 ){ print "$i\tnot in database\n"; }
			else{ print "$i\t$recent\n"; }
		}
	}
	
	#insert
	if( $choice eq "I" ){
		my $which=&promptUser("\nDo you want to paste (P) a list of IDs or generate (G) IDs from a list of accessions?",qq/P,G/);

		#paste in accessions
		if( $which eq "P" ){
			print "\nPaste in the list of IDs you want to insert. Then hit return and press Ctrl-D\n\n";
			my @text = <STDIN>;
			&insert(\@text);
		}
		
		#generate IDs
		if( $which eq "G" ){
			my $how=&promptUser("\nDo you want to generate IDs for each accession in batch (B) or individually (I)?",qq/B,I/);
			
			#generate in batch
			my @text=();
			
			if( $how eq "B" ){
				print "\nPaste in the list of accessions for which you want to generate IDs.\nThen hit return and press Ctrl-D\n\n";
				@text = <STDIN>;
				my $num=&promptUser("\nHow many individuals do you want to generate for each accession?", 999);
				my @oldtext=@text;
				@text=();
				
				# find most recent #.	
				foreach my $ri (@oldtext){
					chomp $ri; 	$ri=~s/\s//g;
					my $rec=&recent($ri);
					$rec++;
					$rec++ if $rec == 0;
					for my $k ($rec..$rec+$num-1){
						push(@text,"$ri.$k");
					}
				}
			}	
			if( $how eq "I" ){
				my $numi=&promptUser("\nHow many accessions do you want to generate IDs for?", 999);
				for my $k (1..$numi){
					print "\nWhat is the name of accession $k? ";
					my $name=<STDIN>; chomp $name; $name=~tr/a-z/A-Z/;
					my $numk=&promptUser("\nHow many IDs do you want to generate for $name?", 999);
					my $recent=&recent($name);
					$recent++;
					$recent++ if $recent == 0;
					
					for my $z ($recent..$numk+$recent-1){
						push(@text,"$name.$z");
					}
				}
			}
			&insert(\@text);
		}
	}
	$done=&promptUser("\nWould you like to do more with COWDUDE (Y/N)?",qq/Y,N/);
}
print "Thanks for using COWDUDE.\n\n"; 
my $moo=rand();
if( $moo<0.05 ){ `afplay /usr/local/bin/dbase_cowdude/BULL.WAV`; }
elsif( $moo<0.1 ){ `afplay /usr/local/bin/dbase_cowdude/COW.WAV`; }
elsif( $moo<0.15 ){ `afplay /usr/local/bin/dbase_cowdude/MOOO.WAV`; }
elsif( $moo<0.2 ){ `say -v Vicki Mooooo`; }
else{ `say Mooooo`; }

#####SUBROUTINES

#INSERT TO TABLE
sub insert{
	my @text = @{@_[0]};

	#choose to update to germinated
	my $g=&promptUser("Would you like to update these individuals as germinated (Y/N)?",qq/Y,N/);
	
	#connect to mysql
	print "\n\nPlease enter your mysql username:\n";
	my $user=<STDIN>; chomp $user;
	print "\n\nPlease enter your mysql password:\n";
	my $pass=<STDIN>; chomp $pass;
	my $dbh = DBI->connect("DBI:mysql:riplasm", $user , $pass ) || die "Could not connect to database: $DBI::errstr";
	
	#do insertion
	my @existing=();
	foreach my $i (@text){
		chomp $i;
		$i=~s/\s//g;
		my $sql;
		
		#get RI number
		if ($i!~m/\w+\d\d\d\d\S*/){ print "***ERROR: Please check the formatting ID $i. This ID has not been inserted\n"; next; }
		$i=~m/(\w+\d\d\d\d)\S*/;
		my $rinum=$1;
		
		#check if already exists
		$sql=qq/select ID from samples where ID like "$i"/;
		my $check = $dbh->prepare($sql);
		$check->execute();
		my @row; 
		while( @row = $check->fetchrow_array()){
			my $idd=$row[0];
			push(@existing,$i) if $idd eq "$i";
		}
	
		if( $g eq "Y" ){ # update status to germinated
			#get time for updates
			my @timeData = localtime(time);
			my $yime = ( $timeData[5]+1900 ) . "-" . ($timeData[4]+1) . "-" . $timeData[3];
			$sql=qq/insert $table (ri_accession,ID,status,germinated_by,germinated_date) values ("$rinum","$i","germinated","$user","$yime")/;
		}
		else{
			$sql=qq/insert $table (ri_accession,ID) values ("$rinum","$i")/;
		}
		$dbh->do($sql);
	}

	#print out existing IDs
	print "\nYour individuals have been inserted into the database.\n";
	if( $#existing > -1 ){
		print "But the following IDs already exist in the database and were not added:\n";
		print "$_\n" foreach( @existing );
	}
	
	# choose to barcode also
	my $yn=&promptUser("\nWould you like to barcode the inserted individuals (Y/N)?",qq/Y,N/);
	if( $yn eq "Y" ){ &barcode(\@text); }
}

#UPDATE DNAS
sub dna{
	print "\nCOWDUDE can read in DNA values from a tab delimited text file on your Desktop.\n",
	"Please make sure the first row starts with the column ID and has one or more of ng_ul, 260_280, or gel_test.\n",
	"ng_ul should be the actual concentration, not the dilute solution measured.\n",
	"gel_test should only be pass or fail.\n\nPlease enter the full name of the file: ";
	my $handle=<STDIN>;
	chomp $handle;
	open DNA, "<$udir/$handle" or die "***ERROR: File $udir/$handle does not exist or cannot be read.\n";
	my @dna=<DNA>;
	close DNA;
	open DNA, ">$udir/$handle" or die "***ERROR: File $udir/$handle does not exist or cannot be read.\n";
	foreach( @dna ){  $_=~s/\r/\n/g; print DNA $_; }
	close DNA;
	open DNA, "<$udir/$handle" or die "***ERROR: File $udir/$handle does not exist or cannot be read.\n";
	my @dna=<DNA>;
	close DNA;
	
	my @columns=split(/\t/,$dna[0]);
	die "***ERROR: File $udir/$handle does not seem to have ID numbers\n" unless $columns[0] eq "ID";

	#connect to mysql
	print "\n\nPlease enter your mysql username:\n";
	my $user=<STDIN>; chomp $user;
	print "\n\nPlease enter your mysql password:\n";
	my $pass=<STDIN>; chomp $pass;
	my $dbh = DBI->connect("DBI:mysql:riplasm", $user , $pass ) || die "Could not connect to database: $DBI::errstr";
	
	#get data
	my %errors;
	for my $line (1..$#dna){
		chomp $dna[$line];
		my @info=split(/\t/,$dna[$line]);
		for my $d (1..$#info){
			my $sql=qq/update $table set $columns[$d] = "$info[$d]" where ID like "$info[0]"/;
			my $rows=$dbh->do($sql);		
			$errors{ $info[0] } = 1 if $rows eq "0E0";
		}
	}
	if( %errors ){
		print "Problems were encountered updating the following IDs; they do not exist in the database.\nPlease check your IDs (note that whitespace characters can cause problems).\n\n";
		foreach my $e (keys (%errors)){
			print "$e\n";
		}
	}
	else{
		print "\nYour DNA data has been successfully updated.\n";
	}
}

#UPDATE STATUS
sub update{
	
	my $stat=&promptUser("What is the status you are updating: germinated (G), planted (P), harvestd (H), lyophilized (L), extracted (E), box/bag (B), or dead (D)?",qq/B,G,P,H,L,E,D/);		
	my $status=$stat eq "L" ? "lyophilized" : ( $stat eq "E" ? "extracted" : ( $stat eq "D" ? "dead" : ( $stat eq "G" ? "germinated" : ( $stat eq "B" ? "box" : ( $stat eq "H" ? "harvested" : "planted" )))));
	my $statdate=$status . "_date";
	my $statby=$status . "_by";
		
	my @text=(); my %hbox; my $box = "drybag"; 
	
	#box/bag question
	if( $status eq "box" ){
			my $b=&promptUser("Do you want to update coldboxes (C) or drybags (D)?",qq/C,D/);
			$box=$b eq "C" ? "coldbox" : "drybag";
	}
	
	if ( $status eq "lyophilized" || $status eq "extracted" || $status eq "box" ){
		$box = "coldbox" if $status eq "extracted";
		print "Please paste in accessions one container at a time so we can update which $box they are in.\n";
		my $num=&promptUser("\nHow many $box containers do you want to enter?", 999);
		for my $j (1..$num){
			print "\nPaste in the list of IDs to update (then hit return and press Ctrl-D):\n\n";
			my @temp=<STDIN>;
			my $n=&promptUser("\nWhat is the number/label of this $box?", 999);
			foreach my $x ( @temp ){
				chomp $x; 	$x=~s/\s//g;
				$hbox{$x}=$n;
			}
			push(@text,@temp);
		}
	}
	else{
		print "\nPaste in the list of IDs to update (then hit return and press Ctrl-D):\n\n";
		@text = <STDIN>;
	}
	
	#connect to mysql
	print "\n\nPlease enter your mysql username:\n";
	my $user=<STDIN>; chomp $user;
	print "\n\nPlease enter your mysql password:\n";
	my $pass=<STDIN>; chomp $pass;
	my $dbh = DBI->connect("DBI:mysql:riplasm", $user , $pass ) || die "Could not connect to database: $DBI::errstr";

	#get time for updates
	my @timeData = localtime(time);
	my $yime = ( $timeData[5]+1900 ) . "-" . ($timeData[4]+1) . "-" . $timeData[3];
	
	my %errors=();
	foreach my $i (@text){
		chomp $i;
		$i=~s/\s//g;
		if ($i!~m/\w+\d\d\d\d\S*/){ print "***ERROR: Please check the formatting ID $i. This ID has not been updated\n"; next; }
		
		#if box only
		if( $status eq "box" ){
			my $bsql=qq/update $table set $box = "$hbox{$i}" where ID like "$i"/;
			my $brows=$dbh->do($bsql);
			$errors{ $i } = 1 if $brows eq "0E0";
			next;
		}
		
		#status
		my $sql=qq/update $table set status = "$status" where ID like "$i"/;
		my $rows = $dbh->do($sql);
		$errors{ $i } = 1 if $rows eq "0E0";
		next if $status eq "dead";
		
		#user
		$sql=qq/update $table set $statby = "$user" where ID like "$i"/;
		$rows=$dbh->do($sql);
		$errors{ $i } = 1 if $rows eq "0E0";

		#date
		$sql=qq/update $table set $statdate = "$yime" where ID like "$i"/;
		$rows=$dbh->do($sql);
		$errors{ $i } = 1 if $rows eq "0E0";

		#container
		if ( $status eq "lyophilized" || $status eq "extracted" ){
			$sql=qq/update $table set $box = "$hbox{$i}" where ID like "$i"/;
			$rows=$dbh->do($sql);
			$errors{ $i } = 1 if $rows eq "0E0";
		}
	}
	
	#updates nonharvested IDs of same accession to dead
	my $killall=0;
	if( $status eq "harvested" ){
		my $killem = &promptUser("Do you want to mark ALL other IDs from the same accessions as 'dead' (Y/N)?",qq/Y,N/);
		$killall=1 if $killem eq "Y";
		if($killall){
			my %ris;
			foreach my $i (@text){
				$i=~s/\s//g;
				$i=~m/(\w+\d\d\d\d)\S*/;
				$ris{$1}=1;
			}
			foreach my $ri (keys(%ris)){
				my $sql=qq/update $table set status = "dead" where ri_accession like "$ri" and status not like "harvested"/;
				my $rows=$dbh->do($sql);
				$errors{ $ri } = 1 if $rows eq "0E0";		
			}
		}
	}	
	$dbh->disconnect();
	if( %errors ){
		print "Problems were encountered updating the following IDs; they do not exist in the database.\nPlease check your IDs (note that whitespace characters can cause problems).\n\n";
		foreach my $e (keys (%errors)){
			print "$e\n";
		}
	}
	else{
		print "\nYour IDs have been successfully updated to $status.\n";
	}
}

#PRINT BARCODES
sub barcode {
	my @text = @{@_[0]};
	foreach my $t (@text){ chomp $t; $t=~s/\s//g; }

	#open template file, write header and first value to postscript file
	open TEMPLATE, "</usr/local/bin/dbase_cowdude/template.ps"  or die "Can't find the barcode template\n";
	print "\nYour barcodes have been generated to the file labels.ps on the Desktop.\nPlease open in Preview and print.\n";
	
	my @temp=<TEMPLATE>;
	close TEMPLATE;	
	open FILE, ">$udir/labels.ps";
	print FILE "@temp\n\n.6 .3 scale\n\n40 145 moveto (^104$text[0]) ", " (includetext textyoffset=-12 textfont=Courier textsize=18)  /code128 /uk.co.terryburton.bwipp findresource exec\n";
	
	#write subsequent labels
	my $col=2; my $errors=0;
	for my $i (1..$#text){
		if ($text[$i]!~m/\w+\d\d\d\d\S*/){ print "***ERROR: Please check the formatting ID $text[$i]. No barcode will be printed for this ID.\n"; $errors++; next; }
		if( ($i-$errors)%80 == 0 ){  # because sticker sheet has 80 labels (Avery 8167)
			print FILE "\n\nshowpage\n.6 .3 scale\n\n40 145 moveto (^104$text[$i]) ", " (includetext textyoffset=-12 textfont=Courier textsize=18)  /code128 /uk.co.terryburton.bwipp findresource exec\n";
			$col=2;
			next;
		}
		my $bob="(^104$text[$i] ) (includetext textyoffset=-12 textfont=Courier textsize=18)  /code128 /uk.co.terryburton.bwipp findresource exec";
		my $sue="245 0 rmoveto ";
		$sue="-740 120 rmoveto " if $col==1;
		$sue="250 0 rmoveto " if $col==3;
		print FILE  "$sue $bob\n";
		$col++;
		$col=1 if $col==5;
	}
	print FILE "showpage\n\n% --END SAMPLE--";
	close FILE;
}

#PROMPT FOR INPUT
sub promptUser {
   my($promptString,$options) = @_;
  	my $input="";
	my $times=0;

   if( $options=~m/\d+/ ){
   	until( $input>0 ){
			print "\nPlease choose a number greater than zero.\n" if $times > 0;
	   	print $promptString, ": ";
  	 		$| = 1;               # force a flush after our print
   		$input = <STDIN>;         # get the input from STDIN (presumably the keyboard)
	   	chomp $input;
			$times++;
		}
	}
   else{
		my @options = split(/,/,$options);
		my %options;
		foreach my $o (@options){
			$options{$o}=1;
		}
		until( $options{$input} ){
			if( $times > 0){ print "\nPlease choose an option from ", join(",",@options), ".\n"; }
			print $promptString, ": ";
			$| = 1;               # force a flush after our print
			$input = <STDIN>;         # get the input from STDIN (presumably the keyboard)
			chomp $input;
			$input=~tr/a-z/A-Z/;
			$times++;
		}
	}
   return $input;
}

# find recent number
sub recent {
	my $acc=@_[0];
	chomp $acc;
	$acc=~s/\s//g;
	my $dbh = DBI->connect("DBI:mysql:riplasm", "reader" , "riplasm" ) || die "Could not connect to database: $DBI::errstr";
	my $sql;

	#check if  exists
	$sql=qq/select ID from samples where ri_accession like "$acc"/;
	my $check = $dbh->prepare($sql);
	$check->execute();
	my @row; 
	my $recent=-1;
	while( @row = $check->fetchrow_array()){
		my $idd=$row[0];
		$idd=~m/\w+\d+\.(\d+)/;
		my $num=$1;
		$recent=$num if $num>$recent;
	}
	return($recent);
}