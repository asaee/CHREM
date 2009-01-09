#!/usr/bin/perl
#  
#====================================================================
# Hse_Gen.pl
# Author: Lukas Swan
# Date: Jan 2009
# Copyright: Dalhousie University
#
#
# INPUT USE:
# filename.pl [house type numbers seperated by "/"] [region numbers seperated by "/"; 0 means all]
#
#
# DESCRIPTION:
# This script generates the esp-r house files for each house of the CSDDRD.
# It uses a multithreading approach based on the house type (SD or DR) and 
# region (AT, QC, OT, PR, BC). Which types and regions are generated is 
# specified at the beginning of the script to allow for partial generation.
# 
# The script builds a directory structure for the houses which begins with 
# the house type as top level directories, regions as second level directories 
# and the house name (10 digit w/o ".HDF") for each house directory. It places 
# all house files within that directory (all house files in the same directory). 
# 
# The script reads a set of input files:
# 1) CSDDRD type and region database (csv)
# 2) esp-r file templates (template.xxx)
# 3) weather station cross reference list
# 
# The script copies the template files for each house of the CSDDRD and replaces
# and inserts within the templates based on the values of the CSDDRD house. Each 
# template file is explicitly dealt with in the main code (actually a sub) and 
# utilizes insert and replace subroutines to administer the specific house 
# information.
# 
# The script is easily extendable to addtional CSDDRD files and template files.
# Care must be taken that the appropriate lines of the template file are defined 
# and that any required changes in other template files are completed.
#
#
#===================================================================

#--------------------------------------------------------------------
# Declare modules which are used
#--------------------------------------------------------------------
use warnings;
use strict;
use CSV;	# CSV-2 (for CSV split and join, this works best)
#use Array::Compare;	#A rray-Compare-1.15
use threads;	# threads-1.71 (to multithread the program)
use File::Path;	# File-Path-2.04 (to create directory trees)
use File::Copy;	#(to copy the input.xml file)

#--------------------------------------------------------------------
# Declare the global variables
#--------------------------------------------------------------------
my @hse_types;	# declare an array to store the desired house types
my %hse_names = (1, "1-SD", 2, "2-DR");	# declare a hash with the house type names

my @regions;	# Regions to generate
my %region_names = (1, "1-AT", 2, "2-QC", 3, "3-OT", 4, "4-PR", 5, "5-BC");	# declare a hash with the region names

#--------------------------------------------------------------------
# Read the command line input arguments
#--------------------------------------------------------------------
COMMAND_LINE: {
	if ($#ARGV != 1) {die "Two arguments are required: house_types regions\n";};	# check for proper argument count

	if ($ARGV[0] eq "0") {@hse_types = (1, 2);}	# check if both house types are desired
	else {	# determine desired house types
		@hse_types = split (/\//,$ARGV[0]);	# House types to generate
		foreach my $type (@hse_types) {
			unless (defined ($hse_names{$type})) {	# check that type exists
				my @keys = sort {$a cmp $b} keys (%hse_names);	# sort house types for following error printout
				die "House type argument must be one or more of the following numeric values seperated by a \"/\": 0 @keys\n";
			};
		};
	};
	

	if ($ARGV[1] eq "0") {@regions = (1, 2, 3, 4, 5);}	# check if all regions are desired
	else {
		@regions = split (/\//,$ARGV[1]);	# regions to generate
		foreach my $region (@regions) {
			unless (defined ($region_names{$region})) {	# check that region exists
				my @keys = sort {$a cmp $b} keys (%region_names);	# sort regions for following error printout
				die "Region argument must be one or more of the following numeric values seperated by a \"/\": 0 @keys\n";
			};
		};
	};
};

#--------------------------------------------------------------------
# Initiate multi-threading to run each region simulataneously
#--------------------------------------------------------------------
MULTI_THREAD: {
	mkpath ("../summary_files");	# make a path to place files that summarize the script results
	print "PLEASE CHECK THE gen_summary.txt FILE IN THE ../summary_files DIRECTORY FOR ERROR LISTING\n";	# tell user to go look
	open (GEN_SUMMARY, '>', "../summary_files/gen_summary.txt") or die ("can't open ../summary_files/gen_summary.txt");	# open a error and summary writeout file
	my $start_time= localtime();	# note the start time of the file generation
	
	my $thread;	# Declare threads for each type and region
	my $thread_return;	# Declare a return array for collation of returning thread data
	
	foreach my $hse_type (@hse_types) {	# Multithread for each house type
		foreach my $region (@regions) {	# Multithread for each region
			$thread->[$hse_type][$region] = threads->new(\&main, $hse_type, $region);	# Spawn the threads and send to main subroutine
		};
	};
	foreach my $hse_type (@hse_types) {	# return for each house type
		foreach my $region (@regions) {	# return for each region type
			$thread_return->[$hse_type][$region] = [$thread->[$hse_type][$region]->join()];	# Return the threads together for info collation
		};
	};
	
	my $end_time= localtime();	# note the end time of the file generation
	print GEN_SUMMARY "start time $start_time; end time $end_time\n";	# print generation characteristics
	close GEN_SUMMARY;	# close the summary file
	print "PLEASE CHECK THE gen_summary.txt FILE IN THE ../summary_files DIRECTORY FOR ERROR LISTING\n";	# tell user to go look
};

#--------------------------------------------------------------------
# Main code that each thread evaluates
#--------------------------------------------------------------------
MAIN: {
	sub main () {
		my $hse_type = $_[0];	# house type number for the thread
		my $region = $_[1];	# region number for the thread
	
	
		#-----------------------------------------------
		# Declare important variables for file generation
		#-----------------------------------------------
		# The template extentions that will be used in file generation (alphabetical order)
		my %extensions = ("aim", 1, "bsm", 2, "cfg", 3, "cnn", 4, "con", 5, "ctl", 6, "geo", 7, "log", 8, "opr", 9, "tmc", 10);
	
	
		#-----------------------------------------------
		# Read in the templates
		#-----------------------------------------------
		my @template;	# declare an array to hold the original templates for use with the generation house files for each record
	
		# Open and read the template files
		foreach my $ext (keys %extensions) {	# do for each filename extention
			open (TEMPLATE, '<', "../templates/template.$ext") or die ("can't open tempate: $ext");	# open the template
			$template[$extensions{$ext}]=[<TEMPLATE>];	# Slurp the entire file with one line per array element
			close TEMPLATE;					# close the template file and loop to the next one
		}
	
	
		#-----------------------------------------------
		# Read in the CWEC weather data crosslisting
		#-----------------------------------------------	
		# Open and read the climate crosslisting (city name to CWEC file)
		open (CWEC, '<', "../climate/city_to_CWEC.csv") or die ("can't open datafile: ../climate/city_to_CWEC.csv");
		my @climate_ref;	# create an climate referece crosslisting array
		while (<CWEC>) {push (@climate_ref, [CSVsplit($_)]);};	# append the next line of data to the climate_ref array
		close CWEC;		# close the CWEC file
	
	
		#-----------------------------------------------
		# Open the CSDDRD source
		#-----------------------------------------------
		# Open the data source files from the CSDDRD - path to the correct CSDDRD type and region file
		my $input_path = "../CSDDRD/2007-10-31_EGHD-HOT2XP_dupl-chk_A-files_region_qual_pref_$hse_names{$hse_type}_subset_$region_names{$region}.csv";
		open (CSDDRD_DATA, '<', "$input_path") or die ("can't open datafile: $input_path");	# open the correct CSDDRD file to use as the data source
		$_ = <CSDDRD_DATA>;	# strip the first header row from the CSDDRD file
	
	
		#-----------------------------------------------
		# GO THROUGH EACH REMAINING LINE OF THE CSDDRD SOURCE DATAFILE
		#-----------------------------------------------
		RECORD: while (<CSDDRD_DATA>) {	# go through each line (house) of the file
			my $time= localtime();	# note the present time

			# SPLIT THE DWELLING DATA, CHECK THE FILENAME, AND CREATE THE APPROPRIATE PATH ../TYPE/REGION/RECORD
			my $CSDDRD = [CSVsplit($_)];	# split each of the comma delimited fields for use
			$CSDDRD->[1] =~ s/.HDF// or  &error_msg ("Bad record name", $hse_type, $region, $CSDDRD->[1]);	# strip the ".HDF" from the record name, check for bad filename
			my $output_path = "../$hse_names{$hse_type}/$region_names{$region}/$CSDDRD->[1]";	# path to the folder for writing the house folder
			mkpath ("$output_path");	# make the output path directory tree to store the house files
	
			# DECLARE ZONE AND PROPERTY HASHES. INITIALIZE THE MAIN ZONE TO BE TRUE AND ALL OTHER ZONES TO BE FALSE
			my $zone_indc = {"main", 1};	# hash for holding the indication of particular zone presence and its number for use with determine zones and where they are located
			my $record_indc;	# hash for holding the indication of dwelling properties

			#-----------------------------------------------
			# DETERMINE ZONE INFORMATION (NUMBER AND TYPE) FOR USE IN THE GENERATION OF ZONE TEMPLATES
			#-----------------------------------------------
			ZONE_PRESENCE: {
				# FOUNDATION CHECK TO DETERMINE IF A BSMT OR CRWL ZONES ARE REQUIRED, IF SO SET TO ZONE #2
				# ALSO SET A FOUNDATION INDICATOR EQUAL TO THE APPROPRIATE TYPE
				# FLOOR AREAS (m^2) OF FOUNDATIONS ARE LISTED IN CSDDRD[97:99]
				# FOUNDATION TYPE IS LISTED IN CSDDRD[15]- 1:6 ARE BSMT, 7:9 ARE CRWL, 10 IS SLAB (NOTE THEY DONT' ALWAYS ALIGN WITH SIZES, THEREFORE USE FLOOR AREA AS FOUNDATION TYPE DECISION
				# BSMT CHECK
				if (($CSDDRD->[97] >= $CSDDRD->[98]) && ($CSDDRD->[97] >= $CSDDRD->[99])) {	# compare the bsmt floor area to the crwl and slab
					$zone_indc->{"bsmt"} = 2;	# bsmt floor area is dominant, so there is a basement zone
					if ($CSDDRD->[15] <= 6) {$record_indc->{"foundation"} = $CSDDRD->[15];}	# the CSDDRD foundation type corresponds, use it in the record indicator description
					else {$record_indc->{"foundation"} = 1;};	# the CSDDRD foundation type doesn't correspond (but floor area was dominant), assume "full" basement
				}
				# CRWL CHECK
				elsif (($CSDDRD->[98] >= $CSDDRD->[97]) && ($CSDDRD->[98] >= $CSDDRD->[99])) {	# compare the crwl floor area to the bsmt and slab
					# crwl space floor area is dominant, but check the type prior to creating a zone
					if ($CSDDRD->[15] != 7) {	# check that the crwl space is either "ventilated" or "closed" ("open" is treated as exposed main floor)
						$zone_indc->{"crwl"} = 2;	# create the crwl zone
						if (($CSDDRD->[15] >= 8) && ($CSDDRD->[15] <= 9)) {$record_indc->{"foundation"} = $CSDDRD->[15];}	# the CSDDRD foundation type corresponds, use it in the record indicator description
						else {$record_indc->{"foundation"} = 8;};	# the CSDDRD foundation type doesn't correspond (but floor area was dominant), assume "ventilated" crawl space
					}
					else {$record_indc->{"foundation"} = 7;};	# the crwl is actually "open" with large ventilation, so treat it as an exposed main floor with no crwl zone
				}
				# SLAB CHECK
				elsif (($CSDDRD->[99] >= $CSDDRD->[97]) && ($CSDDRD->[99] >= $CSDDRD->[98])) { # compare the slab floor area to the bsmt and crwl
					$record_indc->{"foundation"} = 10;	# slab floor area is dominant, so set the foundation to 10
				}
				# FOUNDATION ERROR
				else {&error_msg ("Bad foundation determination", $hse_type, $region, $CSDDRD->[1]);};
		
				# ATTIC CHECK- COMPARE THE CEILING TYPE TO DISCERN IF THERE IS AN ATTC ZONE
				# THE FLAT CEILING TYPE IS LISTED IN CSDDRD[18] AND WILL HAVE A VALUE NOT EQUAL TO 1 (N/A) OR 5 (FLAT ROOF) IF AN ATTIC IS PRESENT
				if (($CSDDRD->[18] != 1) && ($CSDDRD->[18] != 5)) {	#set attic zone indicator unless flat ceiling is type "N/A" or "flat"
					if (defined($zone_indc->{"bsmt"}) || defined($zone_indc->{"crwl"})) {$zone_indc->{"attc"} = 3;}
					else {$zone_indc->{"attc"} = 2;};
				}
				# CEILING TYPE ERROR
				elsif (($CSDDRD->[18] < 1) || ($CSDDRD->[18] > 6)) {&error_msg ("Bad flat roof type", $hse_type, $region, $CSDDRD->[1]);};
			};
	
			#-----------------------------------------------
			# CREATE APPROPRIATE FILENAME EXTENTIONS AND FILENAMES FROM THE TEMPLATES FOR USE IN GENERATING THE ESP-r INPUT FILES
			#-----------------------------------------------

			# INITIALIZE OUTPUT FILE ARRAYS FOR THE PRESENT HOUSE RECORD BASED ON THE TEMPLATES
			my $record_extensions = {%extensions};	# new hash reference to a new hash that will hold the file extentions for this house. Initialize for use
			my $hse_file;	# new array reference to the ESP-r files for this record
		
			INITIALIZE_HOUSE_FILES: {
				# COPY THE TEMPLATES FOR USE WITH THIS HOUSE (SINGLE USE FILES WILL REMAIN, BUT ZONE FILES (e.g. geo) WILL BE AGAIN COPIED FOR EACH ZONE	
				foreach my $ext (values (%{$record_extensions})) {$hse_file->[$ext]=[@{$template[$ext]}];};
				# CREATE THE BASIC FILES FOR EACH ZONE 
				foreach my $zone (keys (%{$zone_indc})) {
					foreach my $file_type ("opr", "con", "geo") {&zone_file_create($zone, $file_type, $hse_file, $record_extensions);};	# files required for the main zone
					if (($zone eq "bsmt") || ($zone eq "crwl") || ($record_indc->{"foundation"} == 10)) {&zone_file_create($zone, "bsm", $hse_file, $record_extensions);};
				};
				# CHECK MAIN WINDOW AREA (m^2) AND CREATE A TMC FILE ([156..159] is Front, Right, Back, Left)
				if ($CSDDRD->[156] + $CSDDRD->[157] + $CSDDRD->[158] + $CSDDRD->[159] > 0) {&zone_file_create("main", "tmc", $hse_file, $record_extensions);};	# windows so generate a TMC file
				# DELETE THE REFERENCES TO THE FILES WHICH HAVE BEEN TRUMPED BY INDIVIDUAL ZONE FILES XXXX.YYY
				foreach my $ext ("tmc", "bsm", "opr", "con", "geo") { delete $record_extensions->{$ext};};
			};

			#-----------------------------------------------
			# GENERATE THE *.cfg FILE
			#-----------------------------------------------
			CFG: {
				&simple_replace ($hse_file->[$record_extensions->{"cfg"}], "#DATE", 1, 1, "*date $time");	# Put the time of file generation at the top
				&simple_replace ($hse_file->[$record_extensions->{"cfg"}], "#ROOT", 1, 1, "*root $CSDDRD->[1]");	# Label with the record name (.HSE stripped)
				CHECK_CITY: foreach my $location (1..$#climate_ref) {	# cycle through the climate reference list to find a match
					if (($climate_ref[$location][0] =~ /$CSDDRD->[4]/) && ($climate_ref[$location][1] =~ /$CSDDRD->[3]/)) {	#f ind a matching climate name and province name
						&simple_replace ($hse_file->[$record_extensions->{"cfg"}], "#LAT_LONG", 1, 1, "$climate_ref[$location][6] $climate_ref[$location][3] # $CSDDRD->[4],$CSDDRD->[3] -> $climate_ref[$location][4]");	# Use the weather station's lat (for esp-r beam purposes), use the site's long (it is correct, whereas CWEC is not), also in a comment show the CSDDRD weather site and compare to CWEC weather site.	
						&simple_replace ($hse_file->[$record_extensions->{"cfg"}], "#CLIMATE", 1, 1, "*clm ../../../climate/$climate_ref[$location][4]");	# use the CWEC city weather name
						last CHECK_CITY;	#if climate city matched jump out of the loop
					}
					elsif ($location == $#climate_ref) {&error_message ("Bad climate comparison", $hse_type, $region, $CSDDRD->[1]);};	# if climate not found print an error
				};
				&simple_replace ($hse_file->[$record_extensions->{"cfg"}], "#SITE_RHO", 1, 1, "1 0.3");	# site exposure and ground reflectivity (rho)
				&simple_replace ($hse_file->[$record_extensions->{"cfg"}], "#AIM", 1, 1, "*aim ./$CSDDRD->[1].aim");	# aim path
				&simple_replace ($hse_file->[$record_extensions->{"cfg"}], "#CTL", 1, 1, "*ctl ./$CSDDRD->[1].ctl");	# ctl path
				&simple_replace ($hse_file->[$record_extensions->{"cfg"}], "#SIM_PRESET_LINE1", 1, 1, "*sps 1 10 1 10 5 0");	# sim setup: no. data sets retained; startup days; zone_ts (step/hr); plant_ts (step/hr); ?save_lv @ each zone_ts; ?save_lv @ each zone_ts;
				&simple_replace ($hse_file->[$record_extensions->{"cfg"}], "#SIM_PRESET_LINE2", 1, 1, "1 1 31 12  default");	# simulation start day; start mo.; end day; end mo.; preset name
				&simple_replace ($hse_file->[$record_extensions->{"cfg"}], "#SIM_PRESET_LINE3", 1, 1, "*sblr $CSDDRD->[1].res");	# res file path
				&simple_replace ($hse_file->[$record_extensions->{"cfg"}], "#PROJ_LOG", 1, 2, "$CSDDRD->[1].log");	# log file path
				&simple_replace ($hse_file->[$record_extensions->{"cfg"}], "#BLD_NAME", 1, 2, "$CSDDRD->[1]");	# name of the building
				my $zone_count = keys (%{$zone_indc});	# scalar of keys, equal to the number of zones
				&simple_replace ($hse_file->[$record_extensions->{"cfg"}], "#ZONE_COUNT", 1, 1, "$zone_count");	# number of zones
				&simple_replace ($hse_file->[$record_extensions->{"cfg"}], "#CONNECT", 1, 1, "*cnn ./$CSDDRD->[1].cnn");	# cnn path
				&simple_replace ($hse_file->[$record_extensions->{"cfg"}], "#AIR", 1, 1, "0");	# air flow network path
		
				# SET THE ZONE PATHS 
				foreach my $zone (keys (%{$zone_indc})) {	# cycle through the zones
					&simple_insert ($hse_file->[$record_extensions->{"cfg"}], "#ZONE$zone_indc->{$zone}", 1, 1, 0, "*zon $zone_indc->{$zone}");	# add the top line (*zon X) for the zone
					foreach my $ext (keys (%{$record_extensions})) {if ($ext =~ /$zone.(...)/) {&simple_insert ($hse_file->[$record_extensions->{"cfg"}], "#END_ZONE$zone_indc->{$zone}", 1, 0, 0, "*$1 ./$CSDDRD->[1].$ext");};};	# insert a path for each valid zone file with the proper name (note use of regex brackets and $1)
					&simple_insert ($hse_file->[$record_extensions->{"cfg"}], "#END_ZONE$zone_indc->{$zone}", 1, 0, 0, "*zend");	# provide the *zend at the end
				};
			};

	 		#-----------------------------------------------
	 		# Generate the *.aim file
	 		#-----------------------------------------------
			AIM: {
				my $Pa_ELA;
				if ($CSDDRD->[32] == 1) {$Pa_ELA = 10} elsif ($CSDDRD->[32] == 2) {$Pa_ELA = 4} else {die ("Bad Pa_ELA: hse_type=$hse_type; region=$region; record=$CSDDRD->[1]\n")};	# set the ELA pressure
				if ($CSDDRD->[28] == 1) {	# Check air tightness type (1= blower door test)
					&simple_replace ($hse_file->[$record_extensions->{"aim"}], "#BLOWER_DOOR", 1, 1, "1 $CSDDRD->[31] $Pa_ELA 1 $CSDDRD->[33]");	# Blower door test with ACH50 and ELA specified
				}
				else { &simple_replace ($hse_file->[$record_extensions->{"aim"}], "#BLOWER_DOOR", 1, 1, "1 $CSDDRD->[31] $Pa_ELA 0 0");};	# Airtightness rating, use ACH50 only (as selected in HOT2XP)
				my $eave_height = $CSDDRD->[112] + $CSDDRD->[113] + $CSDDRD->[114] + $CSDDRD->[115];	# equal to main floor heights + wall height of basement above grade. DO NOT USE HEIGHT OF HIGHEST CEILING, it is strange
				if ($eave_height < 1) { &error_msg ("Eave < 1 m height", $hse_type, $region, $CSDDRD->[1])}	# minimum eave height in aim2_pretimestep.F
				elsif ($eave_height > 12) { &error_msg ("Eave > 12 m height", $hse_type, $region, $CSDDRD->[1])}	# maximum eave height in aim2_pretimestep.F, updated from 10 m to 12 m by LS (2008-10-06)
				&simple_replace ($hse_file->[$record_extensions->{"aim"}], "#EAVE_HEIGHT", 1, 1, "$eave_height");	# set the eave height in meters

				#PLACEHOLDER FOR MODIFICATION OF THE FLUE SIZE LINE. PRESENTLY AIM2_PRETIMESTEP.F USES HVAC FILE TO MODIFY FURNACE FLUE INPUTS FOR ON/OFF
				
				if (defined ($zone_indc->{"bsmt"})) {
					&simple_replace ($hse_file->[$record_extensions->{"aim"}], "#ZONE_INDICES", 1, 2, "2 1 2");	# main and basement recieve infiltration
					&simple_replace ($hse_file->[$record_extensions->{"aim"}], "#ZONE_INDICES", 1, 3, "2 0 0");	# identify the basement zone for AIM, do not identify the crwl or attc as these will be dealt with in the opr file
				}
				else { 
					&simple_replace ($hse_file->[$record_extensions->{"aim"}], "#ZONE_INDICES", 1, 2, "1 1");	# only main recieves infiltration
					&simple_replace ($hse_file->[$record_extensions->{"aim"}], "#ZONE_INDICES", 1, 3, "0 0 0");	# no bsmt, all additional zone infiltration is dealt with in the opr file
				};
			};


			#-----------------------------------------------
			# Control file
			#-----------------------------------------------
			CTL: {
				my $heat_watts = $CSDDRD->[79] * 1000;	# multiply kW by 1000 for watts. this is based on HOT2XP's heating sizing protocol
				my $cool_watts = 0;			# initialize a cooling variable
				if (($CSDDRD->[88] >= 1) && ($CSDDRD->[88] <= 3)) { $cool_watts = 0.25 *$heat_watts;};	# if cooling is present size it to 25% of heating capacity
				&simple_replace ($hse_file->[$record_extensions->{"ctl"}], "#DATA_LINE1", 1, 1, "$heat_watts 0 $cool_watts 0 $CSDDRD->[69] $CSDDRD->[70] 0");	# insert the data line (heat_watts_on heat_watts_off, cool_watts_on cool_watts_off heating_setpoint_C cooling_setpoint_C RH_control
				if (defined ($zone_indc->{"bsmt"})) { &simple_replace ($hse_file->[$record_extensions->{"ctl"}], "#ZONE_LINKS", 1, 1, "1,1,0");}	#l ink main and bsmt to control loop. If no attic is present the extra zero will not bomb the prj (hopefully not bomb the bps as well)
				else { &simple_replace ($hse_file->[$record_extensions->{"ctl"}], "#ZONE_LINKS", 1, 1, "1,0,0");}	# no bsmt and crwl spc is not conditioned so zeros other than main
			};

			#-----------------------------------------------
			# Operations files
			#-----------------------------------------------
			OPR: {
				foreach my $zone (keys (%{$zone_indc})) { 
					&simple_replace ($hse_file->[$record_extensions->{"$zone.opr"}], "#DATE", 1, 1, "*date $time");	# set the time/date for the main.opr file
					# if no other zones exist then do not modify the main.opr (its only use is for ventilation with the bsmt due to the aim and fcl files
					if ($zone eq "bsmt") {
						foreach my $days ("WEEKDAY", "SATURDAY", "SUNDAY") {	# do for each day type
							&simple_replace ($hse_file->[$record_extensions->{"main.opr"}], "#END_AIR_$days", 1, -1, "0 24 0 0.5 2 0");	# add 0.5 ACH ventilation to main from basement. Note they are different volumes so this technically creates imbalance. ESP-r does not seem to account for this (zonal model). This technique should be modified in the future when volumes are known for consistency
							&simple_replace ($hse_file->[$record_extensions->{"bsmt.opr"}], "#END_AIR_$days", 1, -1, "0 24 0 0.5 1 0");	# add same ACH ventilation to bsmt from main
						};
					}
					elsif ($zone eq "crwl") {
						my $crwl_ach;
						# set the crwl ACH infiltration based on tightness level. 0.5 and 0.1 ACH come from HOT2XP
						if ($record_indc->{"foundation"} == 8) {$crwl_ach = 0.5;}	# ventilated crawl	
						elsif ($record_indc->{"foundation"} == 9) {$crwl_ach = 0.1;};	# closed crawl
						foreach my $days ("WEEKDAY", "SATURDAY", "SUNDAY") {&simple_replace ($hse_file->[$record_extensions->{"crwl.opr"}], "#END_AIR_$days", 1, -1, "0 24 $crwl_ach 0 0 0");};	# add it as infiltration and not ventilation. It comes from ambient.
					};
					if ($zone eq "attc") {
						foreach my $days ("WEEKDAY", "SATURDAY", "SUNDAY") {&simple_replace ($hse_file->[$record_extensions->{"attc.opr"}], "#END_AIR_$days", 1, -1, "0 24 0.5 0 0 0");};	# fixed 0.5 ACH to attic from ambient
					};
				};
			};

			#-----------------------------------------------
			# Preliminary geo file generation
			#-----------------------------------------------
			# Window area per side ([156..159] is Window Area Front, Right, Back, Left)
			# Door1 ([137..141] Count, Type, Width (m), Height(m), RSI)
			# Door2 [142..146]
			# Basement door [147..151]
			my $window_area = [$CSDDRD->[156], $CSDDRD->[157], $CSDDRD->[158], $CSDDRD->[159]];	# declare an array equal to the total window area for each side
			my $door_width = [0, 0, 0, 0, 0, 0, 0];	# declare and intialize an array reference to hold the door WIDTHS for each side
			
			my $door_locate;	# declare hash reference to hold CSDDRD index location of doors
			%{$door_locate} = (137, 0, 142, 2, 147, 4);	# provide CSDDRD location and side location of doors. NOTE: bsmt doors are at elements [4,5]
			foreach my $index (keys(%{$door_locate})) {
				if ($CSDDRD->[$index] <= 2) {foreach my $door (1..$CSDDRD->[$index]) {$door_width->[$door_locate->{$index} + $door - 1] = $CSDDRD->[$index + 2];};}	# apply the door widths ($index+1) directly to consecutive sides
				else {foreach my $door (1..2) {$door_width->[$door_locate->{$index} + $door - 1] = sprintf("%.2f", $CSDDRD->[$index + 2] * $CSDDRD->[$index] / 2);};};	# increase the width of the doors to account for more than 2 doors
			};

			my $connections;	# array reference to hold all zones surface connections listing (5 items on each line)

			GEO: {
				foreach my $zone (sort { $zone_indc->{$a} <=> $zone_indc->{$b} } keys(%{$zone_indc})) {	# sort the keys by their value so main comes first
					my $vertex_index = 1;	# index counter
					my $surface_index = 1;	# index counter
					&simple_replace ($hse_file->[$record_extensions->{"$zone.geo"}], "#ZONE_NAME", 1, 1, "GEN $zone This file describes the $zone");	# set the time at the top of each zone geo file
					
					# DETERMINE EXTREMITY RECTANGULAR GEOMETRY (does not include windows/doors)
					my $x; my $y; my $z;	# declare the zone side lengths
					my $x1 = 0; my $y1 = 0, my $z1 = 0;	# declare and initialize the zone origin
					my $x2; my $y2; my $z2;	# declare the zone extremity
					
					# DETERMINE WIDTH AND DEPTH OF ZONE (with limitations)
					my $w_d_ratio = 1; # declare and intialize a width to depth ratio (width is front of house) 
					if ($CSDDRD->[7] == 0) {$w_d_ratio = &range($CSDDRD->[8] / $CSDDRD->[9], 0.75, 1.33);};	# If auditor input width/depth then check range NOTE: these values were chosen to meet the basesimp range and in an effort to promote enough size for windows and doors
					
					$x = sprintf("%.2f", ($CSDDRD->[100] ** 0.5) * $w_d_ratio);	# determine width of zone based upon main floor area
					$y = sprintf("%.2f", ($CSDDRD->[100] ** 0.5) / $w_d_ratio);	# determine depth of zone
					$x2 = $x1 + $x;	# set the extremity points
					$y2 = $y1 + $y;	# set the extremity points

					# DETERMINE HEIGHT OF ZONE
					if ($zone eq "main") { $z = $CSDDRD->[112] + $CSDDRD->[113] + $CSDDRD->[114]; $z1 = 0;}	# the main zone is height of three potential stories and originates at 0,0,0
					elsif ($zone eq "bsmt") { $z = $CSDDRD->[109]; $z1 = -$z;}	# basement or crwl space is offset by its height so that origin is below 0,0,0
					elsif ($zone eq "crwl") { $z = $CSDDRD->[110]; $z1 = -$z;}
					elsif ($zone eq "attc") { $z = &smallest($x, $y) / 2 * 5 / 12;  $z1 = $CSDDRD->[112] + $CSDDRD->[113] + $CSDDRD->[114];};	# attic is assumed to be 5/12 roofline with peak in parallel with long side of house. Attc is mounted to top corner of main above 0,0,0
					$z = sprintf("%.2f", $z);	# sig digits
					$z1 = sprintf("%.2f", $z1);	# sig digits
					$z2 = $z1 + $z;	#include the offet in the height to place vertices>1 at the appropriate location
					
					# DETERMINE EXTREMITY VERTICES (does not include windows/doors)
					my $vertices;	# declare an array reference for the vertices
					push (@{$vertices},	# base vertices in CCW (looking down)
						"$x1 $y1 $z1 # v1", "$x2 $y1 $z1 # v2", "$x2 $y2 $z1 # v3", "$x1 $y2 $z1 # v4");	
					if ($zone ne "attc") {push (@{$vertices},	# second level of vertices for rectangular NOTE: Rework for main sloped ceiling
						"$x1 $y1 $z2 #v 5", "$x2 $y1 $z2 # v6", "$x2 $y2 $z2 # v7", "$x1 $y2 $z2 # v8");}	
					else {	# 5/12 attic shape with NOTE: slope facing the long side of house and gable ends facing the short side
						if ($w_d_ratio >= 1) {	# the front is the long side, so peak in paralle with x
							my $peak_minus = $y1 + $y / 2 - 0.05; # not a perfect peak, create a centered flat spot to maintain 6 surfaces instead of 5
							my $peak_plus = $y1 + $y / 2 + 0.05;
							push (@{$vertices},	# second level attc vertices
								"$x1 $peak_minus $z2 # v5", "$x2 $peak_minus $z2 # v6", "$x2 $peak_plus $z2 # v7", "$x1 $peak_plus $z2 # v8");
						}
						else {	# otherwise the sides of the building are the long sides and thus the peak runs parallel to y
							my $peak_minus = $x1 + $x / 2 - 0.05; # not a perfect peak, create a centered flat spot to maintain 6 surfaces instead of 5
							my $peak_plus = $x1 + $x / 2 + 0.05;
							push (@{$vertices},	# second level attc vertices
								"$peak_minus $y1 $z2 # v5", "$peak_plus $y1 $z2 # v6", "$peak_plus $y2 $z2 # v7", "$peak_minus $y2 $z2 # v8");
						}
					};

					# CREATE THE EXTREMITY SURFACES (does not include windows/doors)
					my $surfaces;	# array reference to hold surface vertex listings
					push (@{$surfaces},	# create the floor and ceiling surfaces for all zone types (CCW from outside view)
						"4 1 4 3 2 # surf1 - floor", "4 5 6 7 8 # surf2 - ceiling");

					# DECLARE CONNECTIONS AND SURFACE ATTRIBUTES ARRAY REFERENCES FOR EXTREMITY SURFACES (does not include windows/doors)
					my $surf_attributes;	# for individual zones
					my $constructions;	# for individual zones
					
					# DETERMINE THE SURFACES, CONNECTIONS, AND SURFACE ATTRIBUTES FOR EACH ZONE (does not include windows/doors)
					if ($zone eq "attc") {	# build the floor, ceiling, and sides surfaces and attributes for the attc
						# FLOOR AND CEILING
						push (@{$constructions}, ["CNST-1", $CSDDRD->[20], $CSDDRD->[19]]);	# floor type
						push (@{$surf_attributes}, "$surface_index Floor OPAQ FLOR $constructions->[$#{$constructions}][0] ANOTHER"); # floor faces the main
						push (@{$connections}, "$zone_indc->{$zone} $surface_index 3 1 2 # $zone floor");	# floor face (3) zone main (1) surface (2)
						$surface_index++;	
						push (@{$constructions}, ["CNST-1", 1, 1]);	# ceiling type NOTE: somewhat arbitrarily set RSI = 1 and type = 1
						push (@{$surf_attributes}, "$surface_index Ceiling OPAQ CEIL $constructions->[$#{$constructions}][0] EXTERIOR"); # ceiling faces exterior
						push (@{$connections}, "$zone_indc->{$zone} $surface_index 0 0 0 # $zone ceiling");	# ceiling faces exterior (0)
						$surface_index++;
						# SIDES
						push (@{$surfaces},	# create surfaces for the sides from the vertex numbers
							"4 1 2 6 5 # surf3 - front sloped", "4 2 3 7 6 # surf4 - right side gable end", "4 3 4 8 7 # surf5 - back sloped", "4 4 1 5 8 # surf6 - left side gable end");
						# assign surface attributes for attc : note sloped sides (SLOP) versus gable ends (VERT)
						foreach my $side ("Front-slope OPAQ SLOP", "Right-gbl-end OPAQ VERT", "Back-slope OPAQ SLOP", "Left-gbl-end OPAQ VERT") {
							push (@{$constructions}, ["CNST-1", 1, 1]);	# side type NOTE: somewhat arbitrarily set RSI = 1 and type = 1
							push (@{$surf_attributes}, "$surface_index $side $constructions->[$#{$constructions}][0] EXTERIOR"); # sides face exterior
							push (@{$connections}, "$zone_indc->{$zone} $surface_index 0 0 0 $zone $side");	# add to cnn file
							$surface_index++;
						};
					}
					elsif ($zone eq "bsmt") {	# build the floor, ceiling, and sides surfaces and attributes for the bsmt
						# FLOOR AND CEILING
						push (@{$constructions}, ["CNST-1", &largest($CSDDRD->[40], $CSDDRD->[42]), $CSDDRD->[39]]);	# floor type
						push (@{$surf_attributes}, "$surface_index Floor OPAQ FLOR $constructions->[$#{$constructions}][0] BASESIMP"); # floor faces the ground
						push (@{$connections}, "$zone_indc->{$zone} $surface_index 6 1 20 # $zone floor");	# floor is basesimp (6) NOTE insul type (1) loss distribution % (20)
						$surface_index++;	
						push (@{$constructions}, ["CNST-1", 1, 1]);	# ceiling type NOTE: somewhat arbitrarily set RSI = 1 and type = 1
						push (@{$surf_attributes}, "$surface_index Ceiling OPAQ CEIL $constructions->[$#{$constructions}][0] ANOTHER"); # ceiling faces main
						push (@{$connections}, "$zone_indc->{$zone} $surface_index 3 1 1 # $zone ceiling");	# ceiling faces main (1)
						$surface_index++;
						# SIDES
						push (@{$surfaces},	# create surfaces for the sides from the vertex numbers
							"4 1 2 6 5 # surf3 - front side", "4 2 3 7 6 # surf4 - right side", "4 3 4 8 7 # surf5 - back side", "4 4 1 5 8 # surf6 - left side");
						foreach my $side ("front", "right", "back", "left") {
							push (@{$constructions}, ["CNST-1", &largest($CSDDRD->[40], $CSDDRD->[42]), $CSDDRD->[39]]);	# side type
							push (@{$surf_attributes}, "$surface_index Side-$side OPAQ VERT $constructions->[$#{$constructions}][0] BASESIMP"); # sides face ground
							push (@{$connections}, "$zone_indc->{$zone} $surface_index 6 1 20 # $zone $side side");	# add to cnn file
							$surface_index++;
						};
						
						# BASESIMP
						my $height_basesimp = &range($z, 1, 2.5);	# check crwl height for range
						&simple_replace ($hse_file->[$record_extensions->{"$zone.bsm"}], "#HEIGHT", 1, 1, "$height_basesimp");	#set height (total)
						my $depth = &range($z - $CSDDRD->[115], 0.65, 2.4);	#difference between total height and above grade, used below for insul placement as well
						if ($record_indc->{"foundation"} >= 3) {$depth = &range(($z - 0.3) / 2, 0.65, 2.4)};		#walkout basement, attribute 0.3 m above grade and divide remaining by 2 to find equivalent height below grade
						&simple_replace ($hse_file->[$record_extensions->{"$zone.bsm"}], "#DEPTH", 1, 1, "$depth");
			
						foreach my $sides ($y, $x) {&simple_insert ($hse_file->[$record_extensions->{"$zone.bsm"}], "#END_LENGTH_WIDTH", 1, 0, 0, "$sides");};

						if (($CSDDRD->[41] == 4) && ($CSDDRD->[38] > 1)) {	#insulation placed on exterior below grade and on interior
							if ($CSDDRD->[38] == 2) { &simple_replace ($hse_file->[$record_extensions->{"$zone.bsm"}], "#OVERLAP", 1, 1, "$depth")}	#full interior so overlap is equal to depth
							elsif ($CSDDRD->[38] == 3) { my $overlap = $depth - 0.2; &simple_replace ($hse_file->[$record_extensions->{"$zone.bsm"}], "#OVERLAP", 1, 1, "$overlap")}	#partial interior to within 0.2 m of slab
							elsif ($CSDDRD->[38] == 4) { &simple_replace ($hse_file->[$record_extensions->{"$zone.bsm"}], "#OVERLAP", 1, 1, "0.6")}	#partial interior to 0.6 m below grade
							else { die ("Bad basement insul overlap: hse_type=$hse_type; region=$region; record=$CSDDRD->[1]\n")};
						};

						my $insul_RSI = &range(&largest($CSDDRD->[40], $CSDDRD->[42]), 0, 9);	#set the insul value to the larger of interior/exterior insulation of basement
						&simple_replace ($hse_file->[$record_extensions->{"$zone.bsm"}], "#RSI", 1, 1, "$insul_RSI")
	
					}
					elsif ($zone eq "crwl") {	# build the floor, ceiling, and sides surfaces and attributes for the crwl
						# FLOOR AND CEILING
						push (@{$constructions}, ["CNST-1", $CSDDRD->[56], $CSDDRD->[55]]);	# floor type
						push (@{$surf_attributes}, "$surface_index Floor OPAQ FLOR $constructions->[$#{$constructions}][0] BASESIMP"); # floor faces the ground
						push (@{$connections}, "$zone_indc->{$zone} $surface_index 6 28 100 # $zone floor");	# floor is basesimp (6) NOTE insul type (28) loss distribution % (100)
						$surface_index++;	
						push (@{$constructions}, ["CNST-1", $CSDDRD->[58], $CSDDRD->[57]]);	# ceiling type
						push (@{$surf_attributes}, "$surface_index Ceiling OPAQ CEIL $constructions->[$#{$constructions}][0] ANOTHER"); # ceiling faces main
						push (@{$connections}, "$zone_indc->{$zone} $surface_index 3 1 1 # $zone ceiling");	# ceiling faces main (1)
						$surface_index++;
						# SIDES
						push (@{$surfaces},	# create surfaces for the sides from the vertex numbers
							"4 1 2 6 5 #surf3 - front side", "4 2 3 7 6 # surf4 - right side", "4 3 4 8 7 # surf5 - back side", "4 4 1 5 8 # surf6 - left side");
						foreach my $side ("front", "right", "back", "left") {
							push (@{$constructions}, ["CNST-1", $CSDDRD->[51], $CSDDRD->[50]]);	# side type
							push (@{$surf_attributes}, "$surface_index Side-$side OPAQ VERT $constructions->[$#{$constructions}][0] EXTERIOR"); # sides face exterior
							push (@{$connections}, "$zone_indc->{$zone} $surface_index 0 0 0 # $zone $side side");	# add to cnn file
							$surface_index++;
						};	
						# BASESIMP
						my $height_basesimp = &range($z, 1, 2.5);	# check crwl height for range
						&simple_replace ($hse_file->[$record_extensions->{"$zone.bsm"}], "#HEIGHT", 1, 1, "$height_basesimp");	#set height (total)
						&simple_replace ($hse_file->[$record_extensions->{"$zone.bsm"}], "#DEPTH", 1, 1, "0.05");			#consider a slab as heat transfer through walls will be dealt with later as they are above grade
			
						foreach my $sides ($y, $x) {&simple_insert ($hse_file->[$record_extensions->{"$zone.bsm"}], "#END_LENGTH_WIDTH", 1, 0, 0, "$sides");};
			
						my $insul_RSI = &range($CSDDRD->[56], 0, 9);						#set the insul value to that of the crwl space slab
						&simple_replace ($hse_file->[$record_extensions->{"$zone.bsm"}], "#RSI", 1, 1, "$insul_RSI")
					}
					elsif ($zone eq "main") {	# build the floor, ceiling, and sides surfaces and attributes for the main
						# FLOOR AND CEILING
						if (defined ($zone_indc->{"bsmt"}) || defined ($zone_indc->{"crwl"})) {	# foundation zone exists
							if (defined ($zone_indc->{"bsmt"})) {push (@{$constructions}, ["CNST-1", 1, 1]);}	# floor type NOTE: somewhat arbitrarily set RSI = 1 and type = 1
							else {push (@{$constructions}, ["CNST-1", $CSDDRD->[58], $CSDDRD->[57]]);};
							push (@{$surf_attributes}, "$surface_index Floor OPAQ FLOR $constructions->[$#{$constructions}][0] ANOTHER"); # floor faces the foundation ceiling
							push (@{$connections}, "$zone_indc->{$zone} $surface_index 3 2 2 # $zone floor");	# floor faces (3) foundation zone (2) ceiling (2)
							$surface_index++;
						}
						else {	# slab on grade
							push (@{$constructions}, ["CNST-1", $CSDDRD->[63], $CSDDRD->[62]]);	# floor type
							push (@{$surf_attributes}, "$surface_index Floor OPAQ FLOR $constructions->[$#{$constructions}][0] BASESIMP"); # floor faces the ground
							push (@{$connections}, "$zone_indc->{$zone} $surface_index 6 28 100 # $zone floor");	# floor is basesimp (6) NOTE insul type (28) loss distribution % (100)
							$surface_index++;
						};
						if (defined ($zone_indc->{"attc"})) {	# attc exists
							push (@{$constructions}, ["CNST-1", $CSDDRD->[20], $CSDDRD->[19]]);	# ceiling type
							push (@{$surf_attributes}, "$surface_index Ceiling OPAQ CEIL $constructions->[$#{$constructions}][0] ANOTHER"); # ceiling faces attc
							push (@{$connections}, "$zone_indc->{$zone} $surface_index 3 $zone_indc->{'attc'} 1 # $zone ceiling");	# ceiling faces attc (1)
							$surface_index++;
						}
						else {	# attc does not exist
							push (@{$constructions}, ["CNST-1", $CSDDRD->[20], $CSDDRD->[19]]);	# ceiling type NOTE: Flat ceiling only. Rework when implementing main sloped ceiling
							push (@{$surf_attributes}, "$surface_index Ceiling OPAQ CEIL $constructions->[$#{$constructions}][0] EXTERIOR"); # ceiling faces exterior
							push (@{$connections}, "$zone_indc->{$zone} $surface_index 0 0 0 # $zone ceiling");	# ceiling faces exterior
							$surface_index++;
						};
						# SIDES
						my @side_names = ("front", "right", "back", "left");	# names of the sides
						my $side_surface_vertices = [[4, 1, 2, 6, 5], [4, 2, 3, 7, 6], [4, 3, 4, 8, 7], [4, 4, 1, 5, 8]];	# surface vertex numbers in absence of windows and doors
						my @side_width = ($x, $y, $x, $y);	# a temporary variable to compare side lengths with window and door width
						foreach my $side (0..3) {	# loop over each side of the house
							if ($window_area->[$side] || $door_width->[$side]) {	# a window or door exists
								my $window_height = sprintf("%.2f", $window_area->[$side] ** 0.5);	# assume a square window
								my $window_width = $window_height;	# assume a square window
								if ($window_height >= ($z - 0.4)) {	# compare window height to zone height. Offset is 0.2 m at top and bottom (total 0.4 m)
									$window_height = $z - 0.4;	# readjust  window height to fit
									$window_width = sprintf("%.2f", $window_area->[$side] / $window_height);	# recalculate window width
								};
								my $window_center = $side_width[$side] / 2;	# assume window is centrally placed along wall length
								if (($window_width / 2 + $door_width->[$side] + 0.4) > ($side_width[$side] / 2)) {	# check to see that the window and a door will fit on the side. Note that the door is placed to the right side of window with 0.2 m gap between and 0.2 m gap to wall end
									if (($window_width + $door_width->[$side] + 0.6) > ($side_width[$side])) {	# window cannot be placed centrally, but see if they will fit at all, with 0.2 m gap from window to wall beginning
										&error_msg ("Window + Door width too great on $side_names[$side]", $hse_type, $region, $CSDDRD->[1]);	# window and door will not fit
									}
									else {	# window cannot be central but will fit with door
										$window_center = sprintf("%.2f",($side_width[$side] - $door_width->[$side] - 0.4) / 2);	# readjust window location to facilitate the door and correct gap spacing between window/door/wall end
									};
								};

								if ($window_area->[$side]) {	# window is true for the side so insert it into the wall (vetices, surfaces, surf attb)
									my $window_vertices;	# declare array ref to hold window vertices
									# windows for each side have different vertices (x, y, z) and no simple algorithm exists, so have explicity geometry statement for each side. Vertices are in CCW position, starting from lower left.
									if ($side == 0) {	# front
										# back and forth across window center, all at y = 0, and centered on zone height
										push (@{$window_vertices}, [$x1 + $window_center - $window_width / 2, $y1, $z1 + $z / 2 - $window_height / 2]);
										push (@{$window_vertices}, [$x1 + $window_center + $window_width / 2, $y1, $z1 + $z / 2 - $window_height / 2]);
										push (@{$window_vertices}, [$x1 + $window_center + $window_width / 2, $y1, $z1 + $z / 2 + $window_height / 2]);
										push (@{$window_vertices}, [$x1 + $window_center - $window_width / 2, $y1, $z1 + $z / 2 + $window_height / 2]);
									}
									elsif ($side == 1) {
										push (@{$window_vertices}, [$x2, $y1 + $window_center - $window_width / 2, $z1 + $z / 2 - $window_height / 2]);
										push (@{$window_vertices}, [$x2, $y1 + $window_center + $window_width / 2, $z1 + $z / 2 - $window_height / 2]);
										push (@{$window_vertices}, [$x2, $y1 + $window_center + $window_width / 2, $z1 + $z / 2 + $window_height / 2]);
										push (@{$window_vertices}, [$x2, $y1 + $window_center - $window_width / 2, $z1 + $z / 2 + $window_height / 2]);
									}
									elsif ($side == 2) {
										push (@{$window_vertices}, [$x2 - $window_center + $window_width / 2, $y2, $z1 + $z / 2 - $window_height / 2]);
										push (@{$window_vertices}, [$x2 - $window_center - $window_width / 2, $y2, $z1 + $z / 2 - $window_height / 2]);
										push (@{$window_vertices}, [$x2 - $window_center - $window_width / 2, $y2, $z1 + $z / 2 + $window_height / 2]);
										push (@{$window_vertices}, [$x2 - $window_center + $window_width / 2, $y2, $z1 + $z / 2 + $window_height / 2]);
									}
									elsif ($side == 3) {
										push (@{$window_vertices}, [$x1, $y2 - $window_center + $window_width / 2, $z1 + $z / 2 - $window_height / 2]);
										push (@{$window_vertices}, [$x1, $y2 - $window_center - $window_width / 2, $z1 + $z / 2 - $window_height / 2]);
										push (@{$window_vertices}, [$x1, $y2 - $window_center - $window_width / 2, $z1 + $z / 2 + $window_height / 2]);
										push (@{$window_vertices}, [$x1, $y2 - $window_center + $window_width / 2, $z1 + $z / 2 + $window_height / 2]);
									};
									foreach my $vertex (0..$#{$window_vertices}) {	# push the vertex information onto the actual array with a side and window comment
										push (@{$vertices}, "@{$window_vertices->[$vertex]} # $side_names[$side] window v$vertex");
									};
									push (@{$side_surface_vertices->[$side]}, $side_surface_vertices->[$side][1], $#{$vertices} - 2);	# push the return vertex of the wall onto its array, then add the first corner vertex of the window
									my @window_surface_vertices = (4);	# declare an array to hold the vertex numbers of the window, initialize with "4" as there will be four vertices to follow in the description
									foreach my $vertex (0..3) {
										push (@{$side_surface_vertices->[$side]}, $#{$vertices} + 1 - $vertex);	# push the window vertices onto the wall surface vertex list in CW order to create an enclosed surface. Return to the first window vertex and stop (final side vertex is implied)
										push (@window_surface_vertices, $#{$vertices} -2 + $vertex);	# push the window vertices onto the window surface vertex list in CCW order
									};
									push (@{$surfaces},"@window_surface_vertices # $side_names[$side] window");	# push the window surface array onto the actual surface array
									push (@{$constructions}, ["WNDW-1", 1.5, $CSDDRD->[160]]);	# side type, RSI, code
									push (@{$surf_attributes}, "$surface_index $side_names[$side]-Wndw TRAN VERT $constructions->[$#{$constructions}][0] EXTERIOR"); # sides face exterior 
									push (@{$connections}, "$zone_indc->{$zone} $surface_index 0 0 0 # $zone $side_names[$side] window");	# add to cnn file
									$surface_index++;
								};

								if ($door_width->[$side]) {	# door is true for the side so insert it into the wall (vetices, surfaces, surf attb)
									# this logic follows similar to the windows above and is therefore not commented so much
									my $door_vertices;
									if ($side == 0) {
										# door is 0.2 m from the side end and starts 0.2 m above the zone floor. Door is 2 m tall.
										push (@{$door_vertices}, [$x2 - 0.2 - $door_width->[$side], $y1, 0.2]);
										push (@{$door_vertices}, [$x2 - 0.2, $y1, 0.2]);
										push (@{$door_vertices}, [$x2 - 0.2, $y1, 0.2 + 2]);
										push (@{$door_vertices}, [$x2 - 0.2 - $door_width->[$side], $y1, 0.2 + 2]);
									}
									elsif ($side == 1) {
										push (@{$door_vertices}, [$x2, $y2 - 0.2 - $door_width->[$side], 0.2]);
										push (@{$door_vertices}, [$x2, $y2 - 0.2, 0.2]);
										push (@{$door_vertices}, [$x2, $y2 - 0.2, 0.2 + 2]);
										push (@{$door_vertices}, [$x2, $y2 - 0.2 - $door_width->[$side], 0.2 + 2]);
									}
									elsif ($side == 2) {
										push (@{$door_vertices}, [$x1 + 0.2 + $door_width->[$side], $y2, 0.2]);
										push (@{$door_vertices}, [$x1 + 0.2, $y2, 0.2]);
										push (@{$door_vertices}, [$x1 + 0.2, $y2, 0.2 + 2]);
										push (@{$door_vertices}, [$x1 + 0.2 + $door_width->[$side], $y2, 0.2 + 2]);
									}
									elsif ($side == 3) {
										push (@{$door_vertices}, [$x1, $y1 + 0.2 + $door_width->[$side], 0.2]);
										push (@{$door_vertices}, [$x1, $y1 + 0.2, 0.2]);
										push (@{$door_vertices}, [$x1, $y1 + 0.2, 0.2 + 2]);
										push (@{$door_vertices}, [$x1, $y1 + 0.2 + $door_width->[$side], 0.2 + 2]);
									};
									foreach my $vertex (0..$#{$door_vertices}) {
										push (@{$vertices}, "@{$door_vertices->[$vertex]} # $side_names[$side] door v$vertex");
									};
									push (@{$side_surface_vertices->[$side]}, $side_surface_vertices->[$side][1], $#{$vertices} - 2);
									my @door_surface_vertices = (4);
									foreach my $vertex (0..3) {
										push (@{$side_surface_vertices->[$side]}, $#{$vertices} + 1 - $vertex);
										push (@door_surface_vertices, $#{$vertices} -2 + $vertex);
									};
									push (@{$surfaces},"@door_surface_vertices # $side_names[$side] door");
									# check the side number to apply the appropriate type, RSI, etc. as there are two types of doors (main zone) listed in the CSDDRD
									if ($side == 0 || $side == 1) {
										push (@{$constructions}, ["CNST-1", $CSDDRD->[141], $CSDDRD->[138]]);	# side type, RSI, code
									}
									elsif ($side == 2 || $side == 3) {
										push (@{$constructions}, ["CNST-1", $CSDDRD->[146], $CSDDRD->[143]]);	# side type, RSI, code
									};
									push (@{$surf_attributes}, "$surface_index $side_names[$side]-Door OPAQ VERT $constructions->[$#{$constructions}][0] EXTERIOR"); # sides face exterior 
									push (@{$connections}, "$zone_indc->{$zone} $surface_index 0 0 0 # $zone $side_names[$side] door");	# add to cnn file
									$surface_index++;
								};

								$side_surface_vertices->[$side][0] = $#{$side_surface_vertices->[$side]};	# reset the count of vertices in the side surface to be representative of any additions due to windows and doors (an addition of 6 for each item)
								push (@{$surfaces},"@{$side_surface_vertices->[$side]} # $side_names[$side] side");	# push the side surface onto the actual surfaces array
								push (@{$constructions}, ["CNST-1", $CSDDRD->[25], $CSDDRD->[24]]);	# side type
								push (@{$surf_attributes}, "$surface_index $side_names[$side]-Side OPAQ VERT $constructions->[$#{$constructions}][0] EXTERIOR"); # sides face exterior 
								push (@{$connections}, "$zone_indc->{$zone} $surface_index 0 0 0 # $zone $side_names[$side] side");	# add to cnn file
								$surface_index++;

							}
							else {	# no windows or doors on this side so simply push out the appropriate information for the side
								push (@{$surfaces}, "@{$side_surface_vertices->[$side]} # $side_names[$side] side");
								push (@{$constructions}, ["CNST-1", $CSDDRD->[25], $CSDDRD->[24]]);	# side type
								push (@{$surf_attributes}, "$surface_index $side_names[$side]-Side OPAQ VERT $constructions->[$#{$constructions}][0] EXTERIOR"); # sides face exterior 
								push (@{$connections}, "$zone_indc->{$zone} $surface_index 0 0 0 # $zone $side_names[$side] side");	# add to cnn file
								$surface_index++;
							};
						};

						# BASESIMP FOR A SLAB
							if ($record_indc->{"foundation"} == 10) {
							my $height_basesimp = &range($z, 1, 2.5);	# check crwl height for range
							&simple_replace ($hse_file->[$record_extensions->{"$zone.bsm"}], "#HEIGHT", 1, 1, "$height_basesimp");	#set height (total)
							&simple_replace ($hse_file->[$record_extensions->{"$zone.bsm"}], "#DEPTH", 1, 1, "0.05");			#consider a slab as heat transfer through walls will be dealt with later as they are above grade
				
							foreach my $sides ($y, $x) {&simple_insert ($hse_file->[$record_extensions->{"$zone.bsm"}], "#END_LENGTH_WIDTH", 1, 0, 0, "$sides");};
				
							my $insul_RSI = &range($CSDDRD->[63], 0, 9);						#set the insul value to that of the crwl space slab
							&simple_replace ($hse_file->[$record_extensions->{"$zone.bsm"}], "#RSI", 1, 1, "$insul_RSI")
						};
					};
					
					&simple_replace ($hse_file->[$record_extensions->{"$zone.geo"}], "#BASE", 1, 1, "1 0 0 0 0 0 $CSDDRD->[100]");	#last line in GEO file which lists FLOR surfaces (total elements must equal 6) and floor area (m^2)
					my $rotation = ($CSDDRD->[17] - 1) * 45;	# degrees rotation (CCW looking down) from south
					my @vert_surf = ($#{$vertices} + 1, $#{$surfaces} + 1);
					&simple_replace ($hse_file->[$record_extensions->{"$zone.geo"}], "#VER_SUR_ROT", 1, 1, "@vert_surf $rotation");
					$vertex_index--;	# decrement count as it is indexed one ahead of total number
					$surface_index--;
					my @zero_array;
					foreach my $zero (1..$surface_index) {push (@zero_array, 0)};
					&simple_replace ($hse_file->[$record_extensions->{"$zone.geo"}], "#UNUSED_INDEX", 1, 1, "@zero_array");
					&simple_replace ($hse_file->[$record_extensions->{"$zone.geo"}], "#SURFACE_INDENTATION", 1, 1, "@zero_array");
					
					foreach my $vertex (@{$vertices}) {&simple_insert ($hse_file->[$record_extensions->{"$zone.geo"}], "#END_VERTICES", 1, 0, 0, "$vertex");};
					foreach my $surface (@{$surfaces}) {&simple_insert ($hse_file->[$record_extensions->{"$zone.geo"}], "#END_SURFACES", 1, 0, 0, "$surface");};
					foreach my $surf_attribute (@{$surf_attributes}) {&simple_insert ($hse_file->[$record_extensions->{"$zone.geo"}], "#END_SURFACE_ATTRIBUTES", 1, 0, 0, "$surf_attribute");};

					my @tmc_type;
					foreach my $construction (0..$#{$constructions}) {
						if ($constructions->[$construction][0] eq "CNST-1") {
							&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#END_LAYERS_GAPS", 1, 0, 0, "1 0 #CNST-1");
							my $k = 0.053;	# W/mK
							my $thickness = sprintf("%.4f", $constructions->[$construction][1] * $k);
							&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#END_PROPERTIES", 1, 0, 0, "$k 150 1169 $thickness 0 0 0 0");	#add the surface layer information ONLY 1 LAYER AT THIS POINT
							push (@tmc_type, 0);
						}
						elsif ($constructions->[$construction][0] eq "WNDW-1") {
							&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#END_LAYERS_GAPS", 1, 0, 0, "3 1 #WNDW-1");
							my $k = 0.17;	# W/mK
							&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#END_AIR_GAP_POS_AND_RES", 1, 0, 0, "2 $k");
							&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#END_PROPERTIES", 1, 0, 0, "0.76 2710 837 0.006 0 0 0 0");
							&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#END_PROPERTIES", 1, 0, 0, "0 0 0 0.012 0 0 0 0");
							&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#END_PROPERTIES", 1, 0, 0, "0.76 2710 837 0.006 0 0 0 0");	#add the surface layer information ONLY 1 LAYER AT THIS POINT
							push (@tmc_type, 1);
						};
					};
					if (($zone eq "main") && defined ($record_extensions->{"$zone.tmc"})) {
						&simple_replace ($hse_file->[$record_extensions->{"$zone.tmc"}], "#SURFACE_COUNT", 1, 1, $#tmc_type + 1);
						&simple_replace ($hse_file->[$record_extensions->{"$zone.tmc"}], "#TMC_INDEX", 1, 1, "@tmc_type");
					};


					my $emm_inside = "";	#initialize text strings for the long-wave emissivity and short wave absorbtivity on the appropriate construction side
					my $emm_outside = "";
					my $slr_abs_inside = "";
					my $slr_abs_outside = "";
					foreach my $construction (0..$#{$constructions}) {
						$emm_inside = "0.75 $emm_inside";
						$emm_outside = "0.75 $emm_outside";
						$slr_abs_inside = "0.5 $slr_abs_inside";
						$slr_abs_outside = "0.5 $slr_abs_outside";
					};
					&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#EMM_INSIDE", 1, 1, 0, "$emm_inside");	#write out the emm/abs of the surfaces for each zone
					&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#EMM_OUTSIDE", 1, 1, 0, "$emm_outside");
					&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#SLR_ABS_INSIDE", 1, 1, 0, "$slr_abs_inside");
					&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#SLR_ABS_OUTSIDE", 1, 1, 0, "$slr_abs_outside");					
				};
			};	
			
			my $cnn_count = $#{$connections} + 1;
			&simple_replace ($hse_file->[$record_extensions->{"cnn"}], "#CNN_COUNT", 1, 1, "$cnn_count");
#			$connections = [sort ({$a cmp $b} @{$connections})];
			foreach my $connection (@{$connections}) {&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#END_CONNECTIONS", 1, 0, 0, "$connection");};


# 			#-----------------------------------------------
# 			# Connections file
# 			#-----------------------------------------------
# 			CNN: {
# 				&simple_replace ($hse_file->[$record_extensions->{"cnn"}], "#DATE", 1, 1, "*date $time");	#add the date stamp
# 
# 				$cnn_count = keys(%{$zone_indc}) * 6;	#total the number of connections, THIS IS SIMPLIFIED (no windows)
# 				&simple_replace ($hse_file->[$record_extensions->{"cnn"}], "#CNN_COUNT", 1, 1, "$cnn_count");
# 				if (defined ($zone_indc->{"attc"}) && (defined ($zone_indc->{"bsmt"}) || defined($zone_indc->{"crwl"}))) {	#make attic the third zone
# 					&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "3 6 3 1 5");	#attach floor of attic to main ceiling
# 					foreach my $side (5, 4, 3, 2, 1) {&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "3 $side 0 0 0");};	#all remaining attc to ambient
# 				}
# 				elsif (defined ($zone_indc->{"attc"})) {	#there is no bsmt or crwl so attc is zone #2
# 					&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "2 6 3 1 5");
# 					foreach my $side (5, 4, 3, 2, 1) {&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "2 $side 0 0 0");};
# 				};
# 				if (defined ($zone_indc->{"bsmt"})) {	#bsmt exists
# 					&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "2 6 6 1 20");	#attach slab to basesimp, assume inside wall insul, 20% heat loss
# 					&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "2 5 3 1 6");	#attach bsmt ceiling to main floor
# 					foreach my $side (4, 3, 2, 1) {&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "2 $side 6 1 20");};	#remaining sides of bsmt to basesimp, same assumptions
# 				}
# 				elsif (defined ($zone_indc->{"crwl"})) {	#bsmt exists
# 					&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "2 6 6 28 100");	#attach slab to basesimp, assume ino slab insul, 100% heat loss
# 					&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "2 5 3 1 6");	#attach crwl ceiling to main floor
# 					foreach my $side (4, 3, 2, 1) {&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "2 $side 0 0 0");};	#remaining sides of crwl to ambient
# 				};
# 				if (defined ($zone_indc->{"bsmt"}) || defined($zone_indc->{"crwl"})) {
# 					&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "1 6 3 2 5");	#check if main is attached to a bsmt or crwl
# 					if (defined ($zone_indc->{"attc"})) {&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "1 5 3 3 6");};	#if attc exist then it is zone 3
# 				}
# 				elsif ($record_indc->{"foundation"} == 10) {
# 					&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "1 6 6 28 100");	#main slab so use basesimp
# 					if ($zone_indc->{"attc"}) {&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "1 5 3 2 6");};	#if attc exists then it is zone 2
# 				}
# 				else {
# 					&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "1 6 0 0 0");	#main has exposed floor
# 					if (defined ($zone_indc->{"attc"})) {&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "1 5 3 2 6");};	#if attc exists then it is zone 2
# 				};
# 				if (!defined ($zone_indc->{"attc"})) {&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "1 5 0 0 0");};	#attc was not filled out so expose main ceiling to ambient
# 				foreach my $side (4, 3, 2, 1) {&simple_insert ($hse_file->[$record_extensions->{"cnn"}], "#CONNECTIONS", 1, 1, 0, "1 $side 0 0 0");};	#expose main walls to ambient
# 			};

# 			#-----------------------------------------------
# 			# Constructions file
# 			#-----------------------------------------------
# 			CON: {
# 				foreach my $zone (keys (%{$zone_indc})) {	#for each zone of the hosue
# 					my $surface_count = 6;		#assume eight vertices and six side TEMPORARY
# 					foreach (1..$surface_count) {&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#END_LAYERS_GAPS", 1, 0, 0, "1 0");};	#number of layers for each surface, number of air gaps for each surface
# 					my $k = 0.053;	# W/mK
# 					my $thickness = $CSDDRD->[27] * $k;
# 					# FLOOR
# 					&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#END_PROPERTIES", 1, 0, 0, "$k 150 1169 $thickness 0 0 0 0");	#add the surface layer information ONLY 1 LAYER AT THIS POINT
# 					# CEILING
# 					if ($CSDDRD->[20] > $CSDDRD->[23]) {$thickness = $CSDDRD->[20] * $k;}
# 					else {$thickness = $CSDDRD->[23] * $k;};
# 					&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#END_PROPERTIES", 1, 0, 0, "$k 150 1169 $thickness 0 0 0 0");	#add the surface layer information ONLY 1 LAYER AT THIS POINT
# 					# WALLS
# 					$thickness = $CSDDRD->[25] * $k;
# 					foreach (1..($surface_count-2)) {&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#END_PROPERTIES", 1, 0, 0, "$k 150 1169 $thickness 0 0 0 0");};	#add the surface layer information ONLY 1 LAYER AT THIS POINT
# 
# 					
# 					my $emm_inside = "";	#initialize text strings for the long-wave emissivity and short wave absorbtivity on the appropriate construction side
# 					my $emm_outside = "";
# 					my $slr_abs_inside = "";
# 					my $slr_abs_outside = "";
# 			
# 					foreach (1..$surface_count) {		#add an emm/abs for each surface of a zone
# 						$emm_inside = "0.75 $emm_inside";
# 						$emm_outside = "0.75 $emm_outside";
# 						$slr_abs_inside = "0.5 $slr_abs_inside";
# 						$slr_abs_outside = "0.5 $slr_abs_outside";
# 					};
# 					&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#EMM_INSIDE", 1, 1, 0, "$emm_inside");	#write out the emm/abs of the surfaces for each zone
# 					&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#EMM_OUTSIDE", 1, 1, 0, "$emm_outside");
# 					&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#SLR_ABS_INSIDE", 1, 1, 0, "$slr_abs_inside");
# 					&simple_insert ($hse_file->[$record_extensions->{"$zone.con"}], "#SLR_ABS_OUTSIDE", 1, 1, 0, "$slr_abs_outside");
# 				};
# 			};

			#-----------------------------------------------
			# Print out each esp-r house file for the house record
			#-----------------------------------------------
			FILE_PRINTOUT: {
				foreach my $ext (keys %{$record_extensions}) {				#go through each extention inclusive of the zones for this particular record
					open (FILE, '>', "$output_path/$CSDDRD->[1].$ext") or die ("can't open datafile: $output_path/$CSDDRD->[1].$ext");	#open a file on the hard drive in the directory tree
					foreach my $line (@{$hse_file->[$record_extensions->{$ext}]}) {print FILE "$line";};	#loop through each element of the array (i.e. line of the final file) and print each line out
					close FILE;
				};
				copy ("../templates/input.xml", "$output_path/input.xml") or die ("can't copy file: input.xml");	#add an input.xml file to the house for XML reporting of results
			};

		};	#end of the while loop through the CSDDRD->
	};	#end of main code
};

#-----------------------------------------------
# Subroutines
#-----------------------------------------------
SUBROUTINES: {
	sub zone_file_create() {				#subroutine to add and appropriately name another copy of a template file to support multiple zones (i.e. main.geo, bsmt.geo) and then notes it in the cross reference hash
		my $zone = shift (@_);			#the zone title
		my $ext = shift (@_);			#the extension title
		my $hse_file = shift (@_);		#array of house esp-r files to add too
		my $record_extensions = shift (@_);	#array of house extentions to add too for the zone and extension
		push (@{$hse_file},[@{$hse_file->[$record_extensions->{$ext}]}]);	#copy the template file to the new location
		$record_extensions->{"$zone.$ext"} = $#{$hse_file};			#use the hash to record the zone's file and extension and cross reference its location in the array
	};
	
	
	sub simple_replace () {			#subroutine to perform a simple element replace (house file to read/write, keyword to identify row, rows below keyword to replace, replacement text)
		my $hse_file = shift (@_);	#the house file to read/write
		my $find = shift (@_);		#the word to identify
		my $location = shift (@_);	#where to identify the word: 1=start of line, 2=anywhere within the line, 3=end of line
		my $beyond = shift (@_);	#rows below the identified word to operate on
		my $replace = shift (@_);	#replacement text for the operated element
		CHECK_LINES: foreach my $line (0..$#{$hse_file}) {		#pass through the array holding each line of the house file
			if ((($location == 1) && ($hse_file->[$line] =~ /^$find/)) || (($location == 2) && ($hse_file->[$line] =~ /$find/)) || (($location == 3) && ($hse_file->[$line] =~ /$find$/))) {	#search for the identification word at the appropriate position in the line
				$hse_file->[$line+$beyond] = "$replace\n";	#replace the element that is $beyond that where the identification word was found
				last CHECK_LINES;				#If matched, then jump out to save time and additional matching
			};
		};
	};
	
	sub simple_insert () {			#subroutine to perform a simple element insert after (specified) the identified element (house file to read/write, keyword to identify row, number of elements after to do insert, replacement text)
		my $hse_file = shift (@_);	#the house file to read/write
		my $find = shift (@_);		#the word to identify
		my $location = shift (@_);	#1=start of line, 2=anywhere within the line, 3=end of line
		my $beyond = shift (@_);	#rows below the identified word to remove from and insert too
		my $remove = shift (@_);	#rows to remove
		my $replace = shift (@_);	#replacement text for the operated element
		CHECK_LINES: foreach my $line (0..$#{$hse_file}) {		#pass through the array holding each line of the house file
			if ((($location == 1) && ($hse_file->[$line] =~ /^$find/)) || (($location == 2) && ($hse_file->[$line] =~ /$find/)) || (($location == 3) && ($hse_file->[$line] =~ /$find$/))) {	#search for the identification word at the appropriate position in the line
				if (($find eq "#END_SURFACE_ATTRIBUTES") || ($find eq "#END_SURFACE_ATTRIBUTES")) {
					my @split = split (/\s+/, $replace);
					$split[0] = sprintf ("%3s", $split[0]);
					$split[1] = sprintf ("%-13s", $split[1]);
					$split[2] = sprintf ("%-5s", $split[2]);
					$split[3] = sprintf ("%-5s", $split[3]);
					$split[4] = sprintf ("%-12s", $split[4]);
					$split[5] = sprintf ("%-15s", $split[5]);
					$replace = "$split[0], $split[1] $split[2] $split[3] $split[4] $split[5]";
					splice (@{$hse_file}, $line + $beyond, $remove, "$replace\n");
				}
				else {splice (@{$hse_file}, $line + $beyond, $remove, "$replace\n");};	#replace the element that is $beyond that where the identification word was found
				last CHECK_LINES;				#If matched, then jump out to save time and additional matching
			};
		};
	};
	
	sub error_msg () {	#subroutine to perform a simple element insert after (specified) the identified element (house file to read/write, keyword to identify row, number of elements after to do insert, replacement text)
		my $msg = shift (@_);	#the error message to print
		my $hse_type = shift (@_);	#the house type
		my $region = shift (@_);	#the region
		my $record = shift (@_);	#the house record
		print GEN_SUMMARY "$msg: hse_type=$hse_type; region=$region; record=$record\n";
		next RECORD;
	};

	sub range () {	#subroutine to perform a range check and modify as required
		my $value = shift (@_);	#the original value
		my $min = shift (@_);	#the range minimum
		my $max = shift (@_);	#the range maximum
		if ($value < $min) {$value = $min;}
		elsif ($value > $max) {$value = $max;};
		return ($value)
	};
	
	sub largest () {	#subroutine to perform a range check and modify as required
		my $value = $_[0];	# placeholder for the value
		foreach my $test (@_) {if ($test > $value) {$value = $test;};};
		return ($value)
	};

	sub smallest () {	#subroutine to perform a range check and modify as required
		my $value = $_[0];	# placeholder for the value
		foreach my $test (@_) {if ($test < $value) {$value = $test;};};
		return ($value)
	};
};