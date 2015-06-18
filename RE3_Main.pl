#!C:/usr/bin/env perl
#use lib 'Y:/weisenthal/perl64/site/lib';
#use lib 'Y:/weisenthal/perl64/lib';
use File::Find;
use File::Copy;
use XML::Simple;
use Data::Dumper;
use Time::HiRes qw(gettimeofday tv_interval);
use File::Path qw(remove_tree);
use Win32::OLE qw(in with);
use POSIX qw (strftime);
use POSIX qw <mktime>;
use Win32::Job;
use List::Util qw(min max);
use List::MoreUtils qw/ uniq /;
use MakeRegression;
use File::Copy "mv";
use RE3reportFigureGeneratorFix;
use DetectOutliers;
use PDF::API2;
use PDF::Table;
use Math::Round;
use File::Slurp qw(slurp);
use Encode;


#Everything in this script respects 'use strict' except the call to the CAD system. I was unable to figure out a way to call it so that it timed out and respected strict, hence the comments. 
use strict;
use warnings;
#no strict "subs";

#This is RE3, the radiation exposure outlier detection/monitoring system.
#Author: SJW (samweisenthal@gmail.com)
#perltidied
#Configuration contains everything for interacting with PACS and directories as well as switches


my $NumbArguments =@ARGV;

if ( $NumbArguments < 1 ) {

    print "Please specify the location of the configuration file as an argument; your command should look like this: 'perl RE3.pl C:/Users/config.xml'.\n";
    exit;
}

# read argument
my $config_file     = $ARGV[0];

#my $config_file = "C:/Users/cipsadmin/desktop/weisenthal/radiation/config.xml";

print "-RE3-\n";
my $timestamp = &get_time;
print "$timestamp\n";
print "Configuration file:$config_file.\n";



#all of these options are described in the configuration file
my $config               = new XML::Simple->XMLin($config_file);
my $prog_path            = $config->{program_path};
my $aet_title            = $config->{aet_title};
my $aet_ip               = $config->{aet_ip};                      #LOCAL
my $aet_port             = $config->{aet_port};
my $aec_title            = $config->{aec_title};
my $aec_ip               = $config->{aec_ip};                      #PACS
my $aec_port             = $config->{aec_port};
my $study_modality       = $config->{study_modality};
my $study_description    = $config->{study_description};
my $study_date           = $config->{study_date};
my $CAD_path             = $config->{CAD_path};
my $retrospective        = $config->{retrospective};
my $time_between_queries = $config->{time_between_queries};
my $body_volume          = $config->{body_volume};
my $nightly              = $config->{nightly};
my $console_path         = $config->{console_path};
my $perl_path            = $config->{perl_path};
my $console_exit         = $config->{console_exit};
my $delete_DICOM_im      = $config->{delete_DICOM_im};
my $use_scheduler        = $config->{use_scheduler};
my $terminate            = $config->{terminate};
my $end_date             = $config->{end_date};
my $end_hour             = $config->{end_hour};
my $slice_data           = $config->{slice_data};
my $list_switch          = $config->{list_switch};
my $run_specific_exam    = $config->{run_specific_exam};
my $specific_accession   = $config->{specific_accession};
my $list_accession       = $config->{list_accession};
my $min_images_for_calc  = $config->{min_images_for_processing};
my $max_images_for_calc  = $config->{max_images_for_processing};
my $BV_min               = $config->{BV_min};
my $BV_max               = $config->{BV_max};
my $updateModel          = $config->{update_model};
my $updateData           = $config->{update_data};
my $makeFigures          = $config->{make_figures};
my $figureCutoffAge      = $config->{age_Cutoff};
my $figureWeekly         = $config->{figure_weekly};
my $figureStart          = $config->{figure_start_date};
my $figureEnd            = $config->{figure_end_date};
my $dlpVariable          = $config->{dlp_variable};
my $histogramVariable    = $config->{histogram_variable};
my $figureDaily          = $config->{figure_daily};
my $reportProtocol       = $config->{report_protocol};
my $reportPeds           = $config->{report_peds};
my $exceptions           = $config->{exceptions};
my $missingAcq           = $config->{missing_acq};
my $onlyReport           = $config->{only_report};
my $kfactorFile          = $config->{k_factor_file};
my $kfactorBodyFile      = $config->{k_factor_body_file};
my $checkDupeStudy       = $config->{check_Dupe_Study};
my $encoding             = $config->{encoding};
my $secureOn             = $config->{secureOn};
my $delete_dumped_data   = $config->{delete_dumped_data};

#The following sectoin takes care of any tags that are added to the command line, so that people don't have to change the config file every time.
my $report_path="$prog_path/reports";
my $public;
my $dateReport;
my $repArg;
my $retroDate;
my $needExam;
for(@ARGV){
    if($_ eq "-p"){
        print "Only looking at peds patients \n";
        $reportPeds =1;
    }
    if($_ eq "-public"){
        print "From server, putting report into public folder\n";
        remove_tree("$prog_path/public", {keep_root=>1});
        $report_path="$prog_path/public";
        
    }
    elsif($_ eq "-nospec"){
        $run_specific_exam=0;
    }
    elsif($_ eq "-r"){
        print "Only making a report for the specified date: ";
        $onlyReport =1;
        $dateReport = 1;
    }
    elsif ($_ eq "-prot"){
        print "Will be making a report for the following protocol: ";
        $repArg=1;
    }
    elsif($_ eq "-retro"){
        print "Will run retrospectively for the specifed date: ";
        $retrospective = 1;
        $retroDate =1;
    }
    elsif($_ eq "-prospective"){
        print "Will be running it prospectively\n";
        $retrospective = 0;
    }
    elsif($_ eq "-fd"){
        print "Making it a daily figure\n";
        $figureDaily = 1;
        $figureWeekly =0;
    }
    elsif($_ eq "-fw"){
        print "Making only weekly figures/report\n";
        $figureWeekly =1;
        $figureDaily =0;
    }
    elsif($_ eq "-night"){
        print "Running it nightly\n";
        $use_scheduler =1;
        $nightly =1;
    }
    elsif($_ eq "-day"){
        print "Running it during the day\n";
        $nightly =0;
        $use_scheduler=1;
    }
    elsif($_ eq "-exam"){
        print "Running a specific exam: ";
        $run_specific_exam = 1;
        $needExam =1;
    }
    elsif($_ eq "-ud"){
        print "Going to update data!";
        $updateData=1;
        $updateModel=1;
    }
    elsif($_ eq "-nud"){
        print "No updating data...";
        $updateData=0;
        $updateModel=0;
    }
    elsif($dateReport){
        my @dates = split('-',$_);
        if (scalar @dates == 1){
            print "$_\n";
            $figureStart=$dates[0];
            $figureEnd = $dates[0];
        }
        elsif(scalar @dates ==2){
            print "$_\n";
            $figureStart = $dates[0];
            $figureEnd=$dates[1];
            $figureDaily=0;
        }
        else{
            print "That is not a properly formatted date: $_. Please retry. \n";
            exit;
        }
        $dateReport=0;
       
    }
    
    elsif($repArg){
        print "$_\n";
        $reportProtocol=$_;
        $repArg=0;
    }
    elsif($retroDate){
        print ("$_\n");
        $retroDate =0;
        $study_date = $_;
    }
    elsif($needExam){
        print("$_\n");
        $needExam =0;
        $specific_accession = $_;
    }
    
}
if ($dateReport){
    print "You have not inputted a date... exiting";
    exit;
}
if($repArg){
    print "You have not specified a protocol to make a report on... exiting";
    exit;
}
if($retroDate){
    print "Missing the dates to run the exam on... exiting";
    exit;
}
if($needExam){
    print "Missing the exam... exiting...";
    exit;
}


if ( $updateModel == 1 ) {
    print
      "You're going to be updating the model! Reconfigure in $config_file\n";
}
elsif ( $updateModel == 0 ) {
    print "Not updating model. Reconfigure in $config_file\n";
}

my %kfactorStudy = &setUpStudyKfactor;
my %kfactorBody = &setUpBodyKfactor;

#start a hash to keep track of processed exams and not reprocess already processed exams. This is mainly for prospective use.
my %processed_exams = ();

#Scheduler can be set up in the configuration file so that it only runs at night, for example. This is a newer add-on, so it is beta
if ( $use_scheduler == 1 ) {
    print
"Using scheduler since scheduler switch = $use_scheduler. Change this switch in $config_file.\n";
    print "Nightly switch value:'$nightly'.\n";
}
else {
    print
"Running continously since scheduler switch = $use_scheduler.Change this switch in $config_file.\n";
}
print
"ONLY processing all series with more than $min_images_for_calc images and fewer than $max_images_for_calc images. To reconfigure, go to $config_file.\n";



#file where the final results will be printed at the study-level
my $one_to_one_study = "$prog_path/one-to-one_study.csv";

#file where the final results will be printed at the series-level
my $one_to_one_series = "$prog_path/one-to-one_series.csv";

#File where the series results without duplicate exams with different accession numbers are.
my $seriesNoDupes = "$prog_path/seriesNoDupes.csv";

#File where the study results without duplicate exams with different accession numbers are.
my $studyNoDupes = "$prog_path/studyNoDupes.csv"; 

#log directory -there is currently no clean-up script since these logs are cleared with each run
my $log_dir = "$prog_path/logs";


#DICOM images will be retrieved to this directory
my $image_path = "$prog_path/PATIENTS";

#those images will be dumped and then put here
my $dump_path = "$prog_path/dcmdump.exe";

#DCMTK--assumes they are in the program path.
print "This script depends on DCMTK executables findscu.exe and movescu.exe. Download them from http://dicom.offis.de/dcmtk.php.en. Once you have them, put them in $prog_path\n";
my $query_path    = "$prog_path/findscu.exe";
my $retrieve_path = "$prog_path/movescu.exe";

#These logs are vital since they are printed to and accessed later in the program
my $tmp_query_log    = "$log_dir/tmp_query_log.txt";
my $tmp_retrieve_log = "$log_dir/tmp_ret_log.txt";

#These logs are not vital.
my $query_log = "$log_dir/query_log.txt";
my $move_log  = "$log_dir/move_log.txt";

#my $tmp_search       = "$prog_path/tmp_search_parameters.csv";
my $final_search = "$prog_path/search_parameters.csv";

#make directory for model
my $ModelDirectory = "$prog_path/Model";
unless ( -e $ModelDirectory ) { mkdir $ModelDirectory; }

if($onlyReport){
    my $numPatients;
    my $numExams;
    print "Not acquiring new data; only generating a report";
    my @missingExams;
    #Can move this to a method, so not repeated so many times throught this all...
    if(!($run_specific_exam)){
     opendir(DIR, $ModelDirectory);
            while (readdir(DIR)){
                
                if ($_ ne "." && $_ ne ".." && $_ =~ m/ModelData/g && (!($reportProtocol)|| $_=~ m/$reportProtocol.csv/g)){
                    my $studyDesc=substr($_,19);
                    $studyDesc=substr($studyDesc,0,-4);
                    #print "DESC: $studyDesc\n";
                    my $regFeature = "$ModelDirectory/$_";
                    $regFeature =~ s/ModelData/Features/;
                    if(-e $regFeature){
                        print "REG FEATUY: $regFeature\n";
                        RE3reportFigureGeneratorFix::genRegFig("$ModelDirectory/$_",$figureCutoffAge,$figureStart,$figureEnd,$regFeature, $studyDesc,$prog_path);
                    }
                    else{
                        RE3reportFigureGeneratorFix::genRegFig("$ModelDirectory/$_",$figureCutoffAge,$figureStart,$figureEnd,"$ModelDirectory/RegressionFeaturesDefault.csv", $studyDesc,$prog_path);
                    }
                }
            }
            #Use plotdlpboxbyage with format ("address to data", "cutoff age for two box plots", starting date yearmonthday, end date yearmonthday);
            ($numPatients, $numExams,@missingExams) = RE3reportFigureGeneratorFix::plotdlpboxbyage($one_to_one_study,$figureCutoffAge,$figureStart,$figureEnd, $reportProtocol, $reportPeds,$missingAcq);

            #Use plotoutlieragepie with format ("address to data", starting date yearmonthday, end date yearmonthday);
            RE3reportFigureGeneratorFix::plotoutlieragepie($one_to_one_study,$figureStart,$figureEnd, $reportProtocol, $reportPeds);

            #Use plotdlpscatter with format ("address to data", "variable: Age or DLP or Dw or Scan Length or Scan Volume or Predicted or Residual, starting date yearmonthday, end date yearmonthday);
            RE3reportFigureGeneratorFix::plotdlpscatter($one_to_one_study,$dlpVariable,$figureStart,$figureEnd, $reportProtocol, $reportPeds);
            
            RE3reportFigureGeneratorFix::plothistogram($one_to_one_study,$histogramVariable,$figureStart,$figureEnd, $reportProtocol, $reportPeds);
            
           }
    
    
    genReport($figureStart, $figureEnd, $numPatients, $numExams, @missingExams);
    exit;
}


#file to record exams that have NoValue, NoIm, or NoAx and therefore arent't included in model.
my $NoValueFile = "$ModelDirectory/ExamsMissingValues.csv";

#define some variables
my $total_series;
my $retrieval;
my $retrieval_series;
my $file;
my $cmd_dmp;
my $sec;
my $min;
my $hour;
my $mday;
my $mon;
my $year;
my $time;
my $value;
my $worked;
my $time_of_series;
my $studytime;
my $exit_flag;
my %exceptions;

#make log directory if doesn't already exist
unless ( -e $log_dir ) { mkdir $log_dir; }

my $CorrCheck = "$prog_path/1_1_correspondencer_new_ON_FLY.pl";
my $DeteCheck = "$prog_path/DetectOutliers.pm";
my $MakeCheck = "$prog_path/MakeRegression.pm";

print
"The script $CorrCheck and modules $DeteCheck and $MakeCheck MUST be in $prog_path\n";
print "Checking that they are there...\n";
if (-e $CorrCheck and -e $DeteCheck and -e $MakeCheck){
    print "Found $CorrCheck, found $DeteCheck, and found $MakeCheck. Looks good!\n";
}else{
    print "Missing one of these in $prog_path: $CorrCheck or $DeteCheck or $MakeCheck...Consult the source code (around line 183) to turn this check off, but dying for now.\n";
    die;
}

print "Also, if you plan to segment the body volume, make sure that the location of the CAD system is correct in $config_file (your current path is $CAD_path). If you do not have this CAD system, set the switch body_volume to 0 in the configuration file\n";


    $timestamp = &get_time;
    print "Timestamp $timestamp\n";
    my ( $starttime, $startdate ) = split ' ', $timestamp;
    my ( $m, $d, $y ) = split '\\.', $startdate;
    $m = sprintf( "%2d", $m );
    $m =~ tr/ /0/;
    $d = sprintf( "%2d", $d );
    $d =~ tr/ /0/;
    my $today = "$y$m$d";
    
    
#Record all the configurations for this run to a file

my $Configuration_Log = "$log_dir/Configurations";
unless ( -e $Configuration_Log ) { mkdir $Configuration_Log; }
open(CF,"<$config_file") or die "Couldn't open $config_file\n";
my @Configs = <CF>;
close CF;
my $configLog = "$Configuration_Log/ConfigurationFrom$y$m$d.txt";
if($secureOn){$configLog = "$Configuration_Log/ConfigurationEncryptFrom$y$m$d.txt";}
open(CL,">>$configLog") or die "Couldn't open $configLog\n";
if(!$secureOn){
    print CL "Start Time: $starttime.\n*************************************************************\n";
    print CL @Configs;
    print CL "*************************************************************\n";
}
else{
    my $encryptedLine = encode($encoding, $starttime);
    print CL "$encryptedLine\n";
    for (@Configs){
        $encryptedLine = encode($encoding, $_);
        print CL "$encryptedLine\n";
    }
    print CL "\n\n\n";
}
close CL;

#File used to force certain protocols into a study description, useful to separate triphsae vs biphase multiphase exams.
open(EXCEP,"<",$exceptions);
while(<EXCEP>){
    my @values = split(',', $_);
    chomp $values[1];
    $exceptions{$values[0]}=$values[1];
}
close EXCEP;
    
if ( $list_switch == 0 ) {

    if ( $run_specific_exam == 1 ) {
        print "Running only exam $specific_accession\n";

    }
    else {
        if ( $retrospective == 1 ) {

            print "Retrospectively running for $study_date\n";
        }
        elsif ( $retrospective != 1 ) {

            $study_date = $today;
            print "Prospectively running for $study_date\n";
        }

    }

}
elsif ( $list_switch == 1 ) {
    print "Running from the list $prog_path/$list_accession";
}

#exit child consoles? For 1_1_correspondencer
if ( $console_exit == 1 ) {
    $exit_flag = "/c";
}
elsif ( $console_exit == '0' ) {
    $exit_flag = "/k";
}

#A checkpoint before running to allow the user to check their settings.
print "Would you like to continue (Y/N) ? ";
my $userword = <STDIN>; # 
chomp $userword; 
if ($userword eq "" or ($userword ne "Y" and $userword ne "y")){print "Your answer ($userword) was not 'y' or 'Y'. Exiting.\n";}
exit 0 if ($userword eq "" or ($userword ne "Y" and $userword ne "y")); # unless y or Y exit
print "Continuing...\n";




#if list switch is on, find the list and find each exam
my $list;
my $Acc_from_list;
if ( $list_switch == 1 ) {

    #this switch is also referenced in the get_IM sub.

    $list = "$prog_path/$list_accession";
    open( LIST, "<$list" ) or die "Can't open $list because $!\n";

    #print the labels to the results
    &printLabels( $one_to_one_series, $one_to_one_study );

    my @WholeList = <LIST>;
    chomp @WholeList;

    #print @WholeList;
    my $ListSize    = @WholeList;
    my $ListCounter = 1;
    foreach (@WholeList) {

        #print "$_\n";
        $Acc_from_list = $_;
        $Acc_from_list =~ s/\s*//g;
        chomp $Acc_from_list;

        print "Looking for $Acc_from_list ($ListCounter/$ListSize)\n";

        #get_IM is the main subroutine that calls all others
        &get_IM;
        $ListCounter++;

    }
    close LIST;

    print "\n\n If you are missing an accession number in the results from your list and there are other ones processed that were not included in your list, 
        then the ones you had listed may have been duplicates of the originals that are located in the results. \n\n";

#if the list switch is off, then just run it continuously. NOTE: now, the logs might get large. It's good to start and stop it sometimes so they clear. Prospectively, if stopped and started it will pick up on that DAY.
#retro and prospectively, it will be run like this. Retrospectively, if stopped, it will start at the beginning of the date range again.
}
else {
    &printLabels( $one_to_one_series, $one_to_one_study );
    my $prog_count = 2;
    while ( $prog_count > 1 ) {

        &get_IM;

    }
}

#Used to print the field names in the results files
sub printLabels {
    my ( $one_to_one_series, $one_to_one_study ) = ( $_[0], $_[1] );

    open( OTO, ">>$one_to_one_series" )
      or die "Can't open $one_to_one_series because $!\n";
    print OTO
"MRN,accession,protocol,protocol no,series no,# images,scanner_type,scanner_maker,series_description,average_ctdindices,DLP_from_indices,pitch,single_collimation_width,total_collimation_width,kvp,scanlength (last location - first location),end_of_uid,age,exposure time,avg exposure,sum exposure,kernel,study date,image_type,acq date,acq time,acq number,acq date_time,slice loc 0, slice location,body part,length from thickness (imagecounter*thick),slice thickness,table_speed,body volume,start time,end time,scan time,exp 0,exp f, studydes,name,gender,scannedvol,Dw,StudyTime,StartConTime,EndConTime,Est Dose,Physician,Filter,irradiationUID\n";
    close OTO;

    open( OTO2, ">>$one_to_one_study" )
      or die "Can't open $one_to_one_study because $!\n";
    print OTO2
"Accession,Study Description,Gender,Age,F?,PED?,SBV_exam,Dw_exam,ScanLength_exam,DLP_exam,predicted DLP, residual,acq,contributing series, protocol name, protocol_no,scanner model, scanner maker, date,outlier?,DLP difference?,Study Time, MRN, Est Dose,Physician,Filter\n";

    close OTO2;

}

#The subroutine that performs all of the actions (previous was getting things set up)
sub get_IM {

    open( MLOG, ">$move_log" ) or die "Can't open $move_log because $!\n";


    # Reformat to work with DCMTK executables
    my $description = "$study_description";
    $description = q{="} . $description . q{"};
    my $modality = "$study_modality";


    $timestamp = &get_time;
    my ( $starttime, $startdate ) = split ' ', $timestamp;

    #print "The start date and start time is $startdate, $starttime\n";
    my ( $m, $d, $y ) = split '\\.', $startdate;
    $m = sprintf( "%2d", $m );
    $m =~ tr/ /0/;
    $d = sprintf( "%2d", $d );
    $d =~ tr/ /0/;
    my $today = "$y$m$d";

    #$study_date is specified by the user (or it can just be name tag)

    my $dumped_data    = "$prog_path/dumped_data";
    my $tmp_image_path = "$prog_path/DICOM_images";
    print "Making '$tmp_image_path' and '$dumped_data' if necessary\n";
    unless ( -e $tmp_image_path ) { mkdir $tmp_image_path; }
    unless ( -e $dumped_data )    { mkdir $dumped_data; }

    print "Querying and retrieving from $aec_title.\n";
    print "Target: studies of description '$description' and modality '$study_modality'.\n";

  #Find number of patients on $study_date
  #if the list switch is on just put a specific accession in the findscu command, as it loops above to get through all of them
    if ( $list_switch == 1 ) {

        print "Querying exclusively for $Acc_from_list\n";
         exe_query( '', '', '=STUDY', '', '', '', '', '', '', '',
            "=$Acc_from_list", '' );
        
    }
    else {
        if($run_specific_exam != 1 ){
            exe_query( '', '', '=STUDY', "=$study_date", "$description",
                "=$modality", '', '', '', '', "=*CT*", '' );
        }

        if ( $run_specific_exam == 1 ) {
            exe_query( '', '', '=STUDY', '', "$description", "=$modality", '',
                '', '', '', "=$specific_accession", '' );
        #Need to check if there are any other acquisitions that are duplicates of the listed one. Not necessary, if looking for a specific one
        
        # open(QLOG, '<', $tmp_query_log ) or print QLOG "Can't open $_[0] because $!\n";
        # my $studyID;
        # my $mrnCheck;
        # while ( my $line = <QLOG> ) {
           
            # if($line =~ m/0020,0010/g){        #Study ID
            
                # ($studyID) = $line =~ /\[(.+?)\]/;
            # }
            # elsif ( $line =~ m/0010,0020/g ) {    #get MRN
                # ($mrnCheck) = $line =~ /\[(.+?)\]/;
                
            # }
        # }
        # close QLOG;
        # print "ID: $studyID \n\n";
        # exe_query( "=$mrnCheck", '', '=STUDY', '', '', '', '', '', '', '',
            # '', '','','','',"=$studyID" );
        }

    }


#these are all returned from get_exam_info, where the script reads the query log. get_exam_info is EXAM-LEVEL
    my (
        $total_exams,   $StudyDate_study_ref, $study_UIDs_ref,
        $MRN_study_ref, $modality_study_ref,  $Studytime_ref,
        $instances_ref, $accession_study_ref, $studyIDRef                               
    ) = get_exam_info($tmp_query_log);


    my $exam_counter;
    my %dupeCheckedExams;
    #Hash of the series that have already been chosen not to be included, as specified in checkContentTime.
    my %seriesNotInclude;
    #for all exams found in get_exam_info...
    for ( my $i = 0 ; $i < $total_exams ; $i++ ) {

        #if it's a certain date (set in configuration), stop
        &terminate_if_date( $_[0] );

        if($i != 0){
            my @dates=@$StudyDate_study_ref;
            #Since the series are given in chronological order, can check to see if it's looking at a different day, then it's impossible to have 
            #any more duplicate studies, so can clear the hash.
            if($dates[$i-1] != $dates[$i]){
                %seriesNotInclude = ();
            }
        }

        #use scheduler?
        if ( $use_scheduler == 1 ) {
            print "Since use_scheduler switch is '$use_scheduler', running engine scheduler sub between studies.\n";
            &schedule_engine;
        }

        #These are just things that are printed to command line so the user knows what's going on
        my $tracKer   = $i + 1;
        my $starttime = time;
        print "_________________________________________________________________\n\n";
        print "Exam: $tracKer/$total_exams. To see the list of exams, consult $query_log.\n";
        my $root_dumped_data;

        print "Looking for $accession_study_ref->[$i]\n";      
       
        #if the exam hasn't already been processed...
        if ( !$processed_exams{ $accession_study_ref->[$i] } ) {

            #These are log files that keep track of all downloaded series (even those that are blocked by 1-1 correspondencer).
            #The first one gets cleared with every study, while the second one (Log) keeps track of all of them.
            my $calc_results =
              "$prog_path/calcResults.csv";   
            my $calcResultsLog;
            if(!$secureOn){  
                $calcResultsLog =
                "$prog_path/calcResultsLog.csv"; 
            }
            else{
                $calc_results = "$prog_path/calcResultsEncrypt.csv";
                $calcResultsLog = "$prog_path/calcResultsLogEncrypt.csv"; 
            }
              
            print "Calclog $calcResultsLog\n";
            open( CALCRES, ">",$calc_results )
              or die "Couldn't open $calc_results $!\n";
            print CALCRES
                "MRN,accession,protocol,protocol no,series no,# images,scanner_type,scanner_maker,series_description,",
                "average_ctdindices,DLP_from_indices,pitch,single_collimation_width,total_collimation_width,",
                "kvp,scanlength (last location - first location),end_of_uid,age,exposure time,avg exposure,sum exposure,kernel,",
                "study date,image_type,acq date,acq time,acq number,acq date_time,slice loc 0, slice location,body part,",
                "length from thickness (imagecounter*thick),slice thickness,table_speed,body volume,start time,end time,",
                "scan time,exp 0,exp f, studydes,name,gender,scannedvol,Dw,StudyTime,StartConTime,EndConTime,EstDose\n";
            close CALCRES;
            open( CALCRESL, ">>",$calcResultsLog )
              or die "Couldn't open the $calcResultsLog $!\n";
            print CALCRESL
                "MRN,accession,protocol,protocol no,series no,# images,scanner_type,scanner_maker,series_description,",
                "average_ctdindices,DLP_from_indices,pitch,single_collimation_width,total_collimation_width,",
                "kvp,scanlength (last location - first location),end_of_uid,age,exposure time,avg exposure,sum exposure,kernel,",
                "study date,image_type,acq date,acq time,acq number,acq date_time,slice loc 0, slice location,body part,",
                "length from thickness (imagecounter*thick),slice thickness,table_speed,body volume,start time,end time,",
                "scan time,exp 0,exp f, studydes,name,gender,scannedvol,Dw,StudyTime,StartConTime,EndConTime,EstDose\n";
            close CALCRESL;
            my $calc_results_slice;

            #if the user wanted slice data, then prepare that file
            if ( $slice_data == 1 ) {
                print "Printed slice-specific data $calc_results_slice to since switch 'slice data' = $slice_data. To change, see $config_file.\n";
                $calc_results_slice = "$prog_path/calcResultsSlice.csv"
                  ;    #where calc(sum) prints its slice-specific output
                open( CALCRESS, ">$calc_results_slice" )
                  or die "Couldn't open $calc_results_slice $!\n";
                print CALCRESS
                    "MRN,accession,protocol,protocol no,series no,# images,scanner_type,scanner_maker,series_description,",
                    "ctdindices,DLP_from_indices,pitch,single_collimation_width,total_collimation_width,",
                    "kvp,scanlength (last location - first location),end_of_uid,age,exposure time,avg exposure,exposure,kernel,",
                    "study date,image_type,acq date,acq time,acq number,acq date_time,slice loc 0, slice location,body part,",
                    "length from thickness (imagecounter*thick),slice thickness,table_speed,body volume,start time,end time,",
                    "scan time,exp 0,exp f, studydes,name,gender,scannedvol,Dw,StudyTime,StartConTime,EndConTime,EstDose\n";
                close CALCRESS;

            }

            print "_________________________________________________________________\n";

            #check that all images are there before going on. This is done at the study level.
            image_check( $accession_study_ref->[$i] );
            $exam_counter = $i + 1;

            print "Exam: $exam_counter/$total_exams. MRN: $MRN_study_ref->[$i]; Accession number: $accession_study_ref->[$i].\n";

            $processed_exams{ $accession_study_ref->[$i] } = 1;

            print "Added $accession_study_ref->[$i] to daily 'processed_exams' hash as $processed_exams{$accession_study_ref->[$i]}.\n";

            #MRN usually contains an extra space in header
            $MRN_study_ref->[$i] =~ s/^\s*(.*?)\s*$/$1/;
            $accession_study_ref->[$i] =~ s/^\s*(.*?)\s*$/$1/;

            #get the study UID since sometimes 2 studies are under the same accession number (extremely rare)
            my $end_of_study_uid = substr( $study_UIDs_ref->[$i], -8 );

            my $tmp_image_path =
              "$tmp_image_path\\$accession_study_ref->[$i]_$end_of_study_uid";
            my $rootImagePath = $tmp_image_path;

            my $dumped_data =
              "$dumped_data\\$accession_study_ref->[$i]_$end_of_study_uid";

            #make these directories if they don't exist
            mkdir($tmp_image_path) unless ( -e $tmp_image_path );
            mkdir($dumped_data)    unless ( -e $dumped_data );

            #Get the number of series for each patient and make a subdirectory tmp_image_path/MRN/studydate_seriesnumber_accessionnumber
            #and dumped_data/MRN/studydate_seriesnumber_accessionnumber
            
            $retrieval = "IMAGE";
            #####################################
            #####################################
            #####################################
            #####################################

            exe_query( '', '', "=$retrieval", '', '', '', '', '', '', '',
                "=$accession_study_ref->[$i]", '', '', '', '', '', "=1" );

            #now, after the series query, get all of the series-level info. This sub is almost identical to get_exam_info
            my (
                $total_series,                 $StudyDate_series_ref,
                $Accession_series_ref,         $Series_times_ref,
                $Modality_series_ref,          $StudyDescription_series_ref,
                $SeriesDescription_series_ref, $PatientName_series_ref,
                $MRN_series_ref,               $SeriesNumber_series_ref,
                $ImagesInSeries_series_ref,    $Birthday_series_ref,
                $series_UIDs_ref,              $contentTime_ref,
                $sLoc_ref,                     $imageTypes_ref 
            ) = get_series_info( $tmp_query_log, "$retrieval" );

            #Look for series whose times indicate that they were performed at fully overlapping times (this does not prevent those that 
            #only have partial overlapping)
            
            my ($deleteRef,$hashDelRef) = checkContentTime($contentTime_ref,$series_UIDs_ref,$ImagesInSeries_series_ref,$Accession_series_ref,$sLoc_ref, $imageTypes_ref,$MRN_study_ref->[$i],$StudyDate_study_ref->[$i], $total_series,\%seriesNotInclude);
            my @deleting = @{$deleteRef};
            %seriesNotInclude=%{$hashDelRef};            
            
            #Sometimes a dose structured report with more accurate dose information will be available, so grabs that.
            my $SRfile = getStructuredReport("=$retrieval",$accession_study_ref->[$i],$tmp_image_path, $dumped_data);
            
            
            # For every discovered series retrieved, process with the CAD, process with getData (which just takes all the DICOM tags).

            for ( my $a = 0 ; $a < $total_series ; $a++ ) {
                my $series_start = time;
                my $tracker      = $a + 1;
                print "\t_____________\n";
                print "\n\tSeries $tracker/$total_series; Exam $tracKer/$total_exams. Exam date: $StudyDate_series_ref->[$a].\n";

                #For each series, we want a volume and a Dw that we will get from running the body volume CAD
                my $series_scanned_volume;
                my $series_Dw;

                $retrieval_series = "SERIES";

                if(!$deleting[$a]){
                    #Note that this image filter makes it avoid the topograms. Those usually contribute about 10 mGy*cm, which is negligable.
                    if (
                        $ImagesInSeries_series_ref->[$a] >= $min_images_for_calc
                        and $ImagesInSeries_series_ref->[$a] <=
                        $max_images_for_calc )
                    {
                        $SeriesNumber_series_ref->[$a] =~ s/\s*//g;
                        $Accession_series_ref->[$a] =~ s/\s*//g;
                        $Accession_series_ref->[$a] =~ s/"//g;

                        #identify by series UID instead of series number, since sometimes there are two series under the same series number but not uid
                        my $end_of_uid = substr( $series_UIDs_ref->[$a], -8 );
                        chomp( $Series_times_ref->[$a] );

                        #make directories for the series
                        my $tmp_image_path = "$tmp_image_path\\$SeriesNumber_series_ref->[$a]_$end_of_uid\_$Series_times_ref->[$a]";
                        $root_dumped_data = $dumped_data;
                        my $dumped_data = "$dumped_data\\$SeriesNumber_series_ref->[$a]_$end_of_uid\_$Series_times_ref->[$a]";

                        #make the next folders in these directory trees
                        unless ( -e $tmp_image_path ) {
                            mkdir($tmp_image_path);
                            print "\tMade $tmp_image_path\n";
                        }
                        unless ( -e $dumped_data ) {
                            mkdir($dumped_data);
                            print "\tMade $dumped_data\n";
                        }
                        print "\tRetrieving series number $SeriesNumber_series_ref->[$a], $SeriesDescription_series_ref->[$a]...\n";
                                             
                        #retrieve images
                        exe_retrieve(
                            '',
                            "=$retrieval_series",
                            "=$Accession_series_ref->[$a]",
                            '',
                            '',
                            '',
                            "=$SeriesNumber_series_ref->[$a]",
                            "=$series_UIDs_ref->[$a]",
                            '',
                            $tmp_image_path,
                            '',
                            '',
                            '',
                            '',
                            ''
                        );

                        #open each directory containing the images, dump header data into corresponding dumped_data directory, 
                        #then delete original images (they take up a lot of space!)
                        print "\tQuery finished. Downloaded the files to $tmp_image_path\n";
                        chomp($tmp_image_path);

                        $tmp_image_path =~ s/\s*//g;

                        print "\nRunning volume CAD...\n";

                        #first, check that there are no series with image type containing cor, sag, or derived since these all crash 
                        #the CAD system. Do so by opening an image, looking at the header, extracting the tag, and filtering accordingly.
                        #By this point, looking for those is deprecated because looks for DERIVED images before downloading
                        opendir( DIR, $tmp_image_path )
                          or die " $! couldn't open $tmp_image_path\n";
                        my $axCheckFile;
                        my $derivedCheckFile;
                        #noax is the flag for "contains cor, sag, etc..'
                        my $noAx = '0';
                        my $first =1;
                        #dump a file
                        while ( $file = readdir(DIR) ) {

                            #print "Dumping for $tmp_image_path\\$file\n\n";

                            $cmd_dmp = "$dump_path $tmp_image_path\\$file";
                           
                            #print "Dumping from $tmp_image_path to $dumped_data\\$file.txt\nHence, root is $dumped_data\n";
                            system "$cmd_dmp >$dumped_data\\$file.txt";
                            
                            #Make it so it chooses the first file, not . or ..
                            if ($first && $file ne '.' && $file ne '..'){
                                $first =0;
                                $derivedCheckFile = "$dumped_data\\$file.txt";
                            }

                            #commented out this unlink so body volume CAD could work on it
                            #unlink "$tmp_image_path\\$file";
                            
                            $axCheckFile = "$dumped_data\\$file.txt";

                        }
                        print "\tEnsuring that no coronal or sagittal images are processed by the CAD system...\n";

                        #Checks to see if the first file is derived. Deprecated.
                        if($derivedCheckFile){
                            my $derivCheck =0;
                            open (DCH, "<",$derivedCheckFile) or die "couldn't open $derivedCheckFile $!";  #DCH is Derived Check Handle
                            while (my $line = <DCH>){
                                if($line =~ m/0008,0008/g){
                                    if ($line =~ m/derived/i){ #This checks the first image to see if it is derived, and then later will be compared to the other file to see if they match. If they don't...
                                        
                                        $derivCheck = $derivCheck+1;
                                        print "The first file is DERIVED $derivCheck\n\n";
                                    }
                                }
                            }
                            close DCH;
                            
                            
                            
                            #check the dumped file
                            open( ACH, "<$axCheckFile" )
                              or die "Couldn't open $axCheckFile $!\n";
                            while ( my $line = <ACH> ) {

                                #print "line $line\n";
                                if ( $line =~ m/0008,0008/g ) {

    #print "LINE MATCHED:$line\n";
    #get image type
    #These don't work with CAD system. These however are not necessarily recons since acquisitions sometimes have images with these image types mixed in with the original image, so had to take this filter out of the script that determines the # of acquisitions
    #if ($line =~ m/cor/i or $line =~ m/sag/i or $line =~ m/derived/i){
    #commented the line above and replaced with just this because a tag could very well say derived and be axial. In fact, no longer excluding those because of what is described in the comment above
                                    #if ( $line =~ m/cor/i or $line =~ m/sag/i or $line =~m/derived/i ) {
                                    if ( $line =~ m/cor/i or $line =~ m/sag/i ) {   
                                        print "\t'$line' matches 'cor','sag', or 'derived'. Not processing volume.\n";
                                        $noAx = '1';
                                    }
                                    if($line =~ m/derived/i){
                                        
                                        $derivCheck = $derivCheck+1;
                                        print "The last file is DERIVED $derivCheck\n\n";
                                    }

                                }
                            }
                            close ACH;
                            #Apparently there was a case that had a combination of original and derived, so this tries to take care of that.
                            print "The value of the Derived Check is $derivCheck where 0=both original, 2= both derived, 1= the first and last image do not share the same image type\n";
                            #A value of 0 corresponds with both files being original, 2 with both derived, and 1 with the files not matching.
                            if($derivCheck == 1){
                                print "There is a mixture of ORIGINAL and DERIVED file types in this directory, so I'm separating them because DerivCheck = $derivCheck.\n\n";
                                print "The path is: $dumped_data\n\n";
                                &moveDerived($dumped_data);
                            }
                            elsif($derivCheck == 2){
                                print "This should have all derived; renaming the directory to reflect that.\n\n";
                                mv($dumped_data,"$dumped_data\_derived");
                                mkdir $dumped_data; 
                            }
                            print "Past separation\n";
                        }
                        ##########################################################################################################

                        #User can specify whether or not to run body volume, if the body volume CAD is available
                        if ( $body_volume == 1 ) {

                            if ( $noAx == '0' ) {

                                #CAD system crashes on >1000 images.
                                if (    $ImagesInSeries_series_ref->[$a]
                                    and $ImagesInSeries_series_ref->[$a] >
                                    $BV_min
                                    and $ImagesInSeries_series_ref->[$a] <
                                    $BV_max )
                                {
#May need this depending on robustness of body volume measurement tool. Would exclude DE_CAP, ART, VEN
#and ( $SeriesDescription_series[$i] !~ m/$series_description_6/gi ) and  ( $SeriesDescription_series[$i] !~ m/$series_description_7/gi ) and  ( $SeriesDescription_series[$i] !~ m/$series_description_8/gi ) ){
                                    print "\tRunning program to measure scanned volume on the series in $tmp_image_path.\n";

                                    my $CAD_command =
                                      "$CAD_path -i $tmp_image_path -B 1";
                                    print "\tUsing command:\n\t$CAD_command\n";

                                    #use Win32 module to start the CAD process with a timeout
                                    my $job              = Win32::Job->new;
                                    my $max_CAD_time_sec = 600;

                                    # Run $CAD_command for $max_CAD_time_sec. Commented out version was previous way that could only be used without use strict.

                                    $job->spawn( $CAD_path,
                                       $CAD_command);
                                    
                                     #$job->spawn( $Config{$console_path},
                                     #    $CAD_command, new_group );

                                    #played around with a few ways to figure out whether the CAD process runs to completion or gets timedout.
                                    #eg, using $job->status. In the end, just using the return value of the run() command worked.
                                    my $run_return =
                                      $job->run($max_CAD_time_sec);

                                    #my $job_stat = $job->status;

                                    #open CAD results and take results. If this doesn't work, print noValue
                                    my $volume_measurements =
                                      "$tmp_image_path/FatReport.txt";

                                    #No need to make it die; there will undoubtedly be a crash in volume measure CAD, 
                                    #but it just means no data--shouldn't stop parent process
                                    if ( open( VM, "<$volume_measurements" ) ) {
                                        print "OPENED $volume_measurements\n";
                                        while (<VM>) {

                                            #the row with Sum has the study-level info. Would have liked to have taken each slice 
                                            #SBV and Dw(the data is there) for slice level data, but didn't have time to make it do that
                                            #No need for that information yet as well.
                                            if ( $_ =~ m/Sum/i ) {

                                                #print "Looking at $_\n";
                                                my @measurements =
                                                  split( ',', $_ );

                                                $series_scanned_volume =
                                                  $measurements[7];
                                                $series_Dw = $measurements[8];
                                                chomp $series_scanned_volume;
                                                chomp $series_Dw;
                                            }
                                        }
                                        close VM;

                                      #Since it already has the info in the file
                                        unlink $volume_measurements;

#Since Perl apparently converts a string to 0 if it's added to a number, this is extremely important. 
#The downstream scripts will search for these NoValue, NoIm, and NoAx flags to make sure they don't accidentally add them as 0 (which would make the SBV far off)
#CASE 1: if it was supposed to be processed by the BV program but for some reason no results were made, print NoValue in place
                                    }
                                    else {
                                        print "Couldn't open $volume_measurements: $!\n";
                                        $series_scanned_volume = "NoValue";
                                        $series_Dw             = "NoValue";
                                    }

#if the number of images in the series didn't fit the BV program's constraints...
                                }
                                else {
                                    print
"\tNot running body volume condition $ImagesInSeries_series_ref->[$a] and $ImagesInSeries_series_ref->[$a] >50 and $ImagesInSeries_series_ref->[$a]< 1000.\n";
                                    $series_scanned_volume = "NoIm";
                                    $series_Dw             = "NoIm";
                                }

                       #if the image type was wrong (noAx signifies No Axial), but this never happens anymore.
                            }
                            else {
                                print "\tNot running body volume since the image type matches 'cor','sag', or 'derived' (noAx = $noAx).\n";
                                $series_scanned_volume = "NoAx";
                                $series_Dw             = "NoAx";
                            }

                        #if the user just didn't want to run it...(could make this a different flag to distinguish)
                        }
                        else {
                            print "\tNot running body volume since body volume switch = $body_volume.\n";
                            $series_scanned_volume = "NoValue";
                            $series_Dw             = "NoValue";
                        }

#If the user sets this switch on, remove original dicom images, since all their info is now dumped. This is important because they take up a lot of space

                        if ( $delete_DICOM_im == 1 ) {

                            print "\tRemoving $tmp_image_path since delete_dicom_im switch = $delete_DICOM_im.\n";
                            remove_tree($tmp_image_path);
                            print("Deleting root: $tmp_image_path\n");
                        }
                        else {
                            print
"Not removing $tmp_image_path since delete_dicom_im switch = $delete_DICOM_im. To remove the original DICOM images, change the delete_DICOM_im switch to 1 in the configuration file.\n";
                        }

                        print "\tGoing to run get_data on $dumped_data.\n";

                        get_data(
                            $dumped_data,           $study_date,
                            $series_scanned_volume, $series_Dw,
                            $config_file,           $calc_results,
                            $calc_results_slice,    $calcResultsLog,
                            $SRfile
                        );

                    }
                    else {
                        print
"\tHas $ImagesInSeries_series_ref->[$a] images, which is fewer than $min_images_for_calc or more than $max_images_for_calc. Not running calculator/extractor. Change this filter in $config_file.\n";
                    }
                }
                else {
                    #for dose monitoring purposes, these series are irrelevant
                    print "\tThe description of this series $SeriesDescription_series_ref->[$a] has similar content time to another series, so it's probably a duplicate.\n";
                }
                ########################################################################################

                my $series_end  = time;
                my $seriesProcessingTime = ( $series_end - $series_start ) / 60;
                print "\tSeries time: $seriesProcessingTime minutes.\n";

            }
            open( CALCRES, ">>$calc_results" )
              or die "Couldn't open $calc_results $!\n";
            print CALCRES "END\n";
            close CALCRES;

    #This needs to be made a subroutine. It takes like a second, so it doesn't really matter, but in the future, should be a subroutine (not external perl script)
           my $correspond_cmd =
"start cmd.exe $exit_flag $perl_path $prog_path/1_1_correspondencer_new_ON_FLY.pl $calc_results $study_date $config_file $updateData $calc_results_slice";
            print
              "\tCalling 1-1 correspondencer with command\n\t$correspond_cmd\n";
            system $correspond_cmd;

            #wait just in case
            my $one_one_wait = 5;

            #if it has to process slices, wait longer (since it will have to ignore all slices that are reconstructions)
            if ( $slice_data == 1 ) {
                $one_one_wait = 100;
            }
            print "\tSleeping $one_one_wait s so that 1_1 correspondencer can process file (before deleting it and making a new one)\n";
            sleep $one_one_wait;
            my $endtime    = time;
            my $study_time = ( $endtime - $starttime ) / 60;
            print "\tStudy time: $study_time minutes.\n";

            print "a $StudyDescription_series_ref->[$a] or i $StudyDescription_series_ref->[$i]?\n";
            my $study_desc = $StudyDescription_series_ref->[$a];
            $study_desc =~ s/[^a-zA-Z0-9]*//g;
            print "study des $study_desc\n";

#file where data to run regression on is stored
              my $DataForRegression = "$ModelDirectory/RegressionModelData$study_desc.csv";
             
              print "$DataForRegression\n";

            if ( $updateModel == 1 && $study_desc && $study_desc ne "") {
                print "UPDATING MODEL!!!! Update model switch is set to $updateModel. To change, consult $config_file\n";
                ################################################################################################
#file to store model (contains all coefficients and then 3*residualStDev threshold
                my $RegressionFeatures =
                  "$ModelDirectory/RegressionFeatures$study_desc.csv";

                #First predictor index (all other predictors must come directly after until the dependent variable) in $DataForRegression
                #age, gender, pediatric, SBV, DW, Scan length
                my $FPI = 3;

                #Dependent variable index in $DataForRegression (DLP)
                my $DVI = 9;

                print "Regression in progress...\n";

   #will use one of these to index the file it will look for the regression data
                print "a $StudyDescription_series_ref->[$a] or i $StudyDescription_series_ref->[$i]?\n";
                unless(-e  $DataForRegression){open(RD, ">>$DataForRegression") or die "Couldn't open $DataForRegression $!!\n";close RD;}
                open(RD, "<$DataForRegression") or die "Couldn't open $DataForRegression $!!\n";
                my $dataCheckerCounter=0;
                my $pedsCheck = 1;
                my $femCheck=1;
                my $lastLine="";
                while (my $line = <RD>) {
                    #Need to check if any columns contain all of the same value, otherwise the regression fails with this module. 
                    #The peds is the most likely one to fail, while the fem is very much less likely but still possible, while the rest are too unlikely to consider.
                     my @currValues = split(',',$line,8);
                      my @lastValues =  split(',',$lastLine,8);
                     if ($lastLine ne "" && ($pedsCheck==1 || $femCheck==1) && $currValues[6] ne "NoValue"&&$lastValues[6] ne "NoValue" && $currValues[3] ne "" && $lastValues[3] ne ""){
                       
                        
                        $pedsCheck = $pedsCheck*($lastValues[5]==$currValues[5]);
                        $femCheck = $femCheck*($lastValues[4]==$currValues[4]);
                    }
                    $dataCheckerCounter++;
                    $lastLine = $line;
                  
                }
                close RD;
                print "$dataCheckerCounter exams in $DataForRegression. PedsCheck is equal to $pedsCheck while femCheck is equal to $femCheck\n";
                #Send the checks to make a regression depending on the variety of values, but 1 means that it shouldnt be included, while 0 means it should
                #Only create models when sufficient data (using 20 as arbitrary value currently)
                if($dataCheckerCounter>20){
                    MakeRegression::Outlier_Robust_Regress( $DataForRegression,
                        $NoValueFile, $FPI, $DVI, $RegressionFeatures, $pedsCheck,$femCheck);
                }else{
                    print "Possible problems: \n";
                    print "There are only $dataCheckerCounter exams in $DataForRegression. Not making a regression until there are 20\n";
                    print "The checks should both be zero, when the gender check equals $femCheck and the peds check equals $pedsCheck\n";
                }
                ##################################################################################################
            }
            elsif ( $updateModel == 0 ) {
                print "Not updating model since switch is $updateModel. To change, consult $config_file\n";
            }
        }
        else {
            print "\t$accession_study_ref->[$i] already in daily 'processed_exams' hash as $processed_exams{$accession_study_ref->[$i]}\n";
        }

    }

    my @uniqpatient           = uniq @$MRN_study_ref;
    my $total_unique_patients = @uniqpatient;

    print "\nRetrieved $total_exams studies for $total_unique_patients patients.\n";

    close QRLOG;
    close MLOG;
    
    my $numPatients;
    my $numExams;
    my @missingExams;
    
    #Making the figures for a dose report to be automatically generated.
    if($makeFigures && !$run_specific_exam){
        remove_tree("$prog_path/Figures");
        if($figureWeekly){
            my ($sec, $min, $hour, $mday, $mon, $year, $wday)=localtime();
            #0-6 corresponding to Sunday(0) through Saturday(6)
            if($wday  ==0){
                my $timey = &get_time;
                my ( $endTime, $endDate ) = split ' ', $timey;
               
                 my ($endMonth, $endDay, $endYear) = split('\.',$endDate);
                 
                if($endDay<10){
                    $endDay = "0$endDay";
                 }
                 if ($endMonth<10){
                     $endMonth = "0$endMonth";
                 }
                 
                 $figureEnd = "$endYear$endMonth$endDay";
              
                
                #subtracts a week's worth of seconds
                 my ( $lastSec, $lastMin, $lastHour, $lastMday, $lastMon, $lastYear ) = localtime(time-604800);
                 $lastYear += 1900;
                 $lastMon +=1;
                 if($lastMday<10){
                    $lastMday = "0$lastMday";
                 }
                 if ($lastMon<10){
                     $lastMon = "0$lastMon";
                 }
                 $figureStart = "$lastYear$lastMon$lastMday";
                print "Will run figures from $figureStart through $figureEnd\n";
                opendir(DIR, $ModelDirectory);
                
            while (readdir(DIR)){
                
                #Looks for the regression model data and runs the regression Model figure on each of them. The second half of the if statement refers to 
                #if want to report specific protocol (specified in config)
                if ($_ ne "." && $_ ne ".." && $_ =~ m/ModelData/g && (!($reportProtocol)|| $_=~ m/$reportProtocol.csv/g)){
                    #Grabs the study description from the file name by removing the constant portions of the name
                    my $studyDesc=substr($_,19);
                    $studyDesc=substr($studyDesc,0,-4);
                    print "DESC: $studyDesc\n";
                    my $regFeature = "$ModelDirectory/$_";
                    $regFeature =~ s/ModelData/Features/;
                    if(-e $regFeature){
                        print "REG FEATURE: $regFeature\n";
                        RE3reportFigureGeneratorFix::plotscatterandreg("$ModelDirectory/$_",$figureCutoffAge,$figureStart,$figureEnd,$regFeature, $studyDesc,$prog_path);
                    }
                    else{
                        
                        RE3reportFigureGeneratorFix::plotscatterandreg("$ModelDirectory/$_",$figureCutoffAge,$figureStart,$figureEnd,"$ModelDirectory/RegressionFeaturesDefault.csv", $studyDesc,$prog_path);
                    }
                }
            }
                #Use plotdlpboxbyage with format ("address to data", "cutoff age for two box plots", starting date yearmonthday, end date yearmonthday);
                ($numPatients, $numExams, @missingExams) = RE3reportFigureGeneratorFix::plotdlpboxbyage($one_to_one_study,$figureCutoffAge,$figureStart,$figureEnd, $reportProtocol, $reportPeds, $missingAcq);

                #Use plotoutlieragepie with format ("address to data", starting date yearmonthday, end date yearmonthday);
                RE3reportFigureGeneratorFix::plotoutlieragepie($one_to_one_study,$figureStart,$figureEnd, $reportProtocol, $reportPeds);

                #Use plotdlpscatter with format ("address to data", "variable: Age or DLP or Dw or Scan Length or Scan Volume or Predicted or Residual, starting date yearmonthday, end date yearmonthday);
                RE3reportFigureGeneratorFix::plotdlpscatter($one_to_one_study,$dlpVariable,$figureStart,$figureEnd, $reportProtocol, $reportPeds);
                
                RE3reportFigureGeneratorFix::plothistogram($one_to_one_study,$histogramVariable,$figureStart,$figureEnd, $reportProtocol, $reportPeds);
            }
        }
        else{
            if($figureDaily){
                    $figureStart = $study_date;
                    $figureEnd = $study_date;
                    print ("The date is: $study_date");
            }
            opendir(DIR, $ModelDirectory);
            while (readdir(DIR)){
                
                if ($_ ne "." && $_ ne ".." && $_ =~ m/ModelData/g && (!($reportProtocol)|| $_=~ m/$reportProtocol.csv/g)){
                    my $studyDesc=substr($_,19);
                    $studyDesc=substr($studyDesc,0,-4);
                    #print "DESC: $studyDesc\n";
                    my $regFeature = "$ModelDirectory/$_";
                    $regFeature =~ s/ModelData/Features/;
                    if(-e $regFeature){
                        print "REG FEATUY: $regFeature\n";
                        RE3reportFigureGeneratorFix::plotscatterandreg("$ModelDirectory/$_",$figureCutoffAge,$figureStart,$figureEnd,$regFeature, $studyDesc);
                    }
                    else{
                        RE3reportFigureGeneratorFix::plotscatterandreg("$ModelDirectory/$_",$figureCutoffAge,$figureStart,$figureEnd,"$ModelDirectory/RegressionFeaturesDefault.csv", $studyDesc);
                    }
                }
            }
            #Use plotdlpboxbyage with format ("address to data", "cutoff age for two box plots", starting date yearmonthday, end date yearmonthday). Grabs statistics as well
            ($numPatients, $numExams, @missingExams) = RE3reportFigureGeneratorFix::plotdlpboxbyage($one_to_one_study,$figureCutoffAge,$figureStart,$figureEnd, $reportProtocol, $reportPeds, $missingAcq);

            #Use plotoutlieragepie with format ("address to data", starting date yearmonthday, end date yearmonthday);
            RE3reportFigureGeneratorFix::plotoutlieragepie($one_to_one_study,$figureStart,$figureEnd, $reportProtocol, $reportPeds);

            #Use plotdlpscatter with format ("address to data", "variable: Age or DLP or Dw or Scan Length or Scan Volume or Predicted or Residual, starting date yearmonthday, end date yearmonthday);
            RE3reportFigureGeneratorFix::plotdlpscatter($one_to_one_study,$dlpVariable,$figureStart,$figureEnd, $reportProtocol, $reportPeds);
            
            RE3reportFigureGeneratorFix::plothistogram($one_to_one_study,$histogramVariable,$figureStart,$figureEnd, $reportProtocol, $reportPeds);
            
            
        }
        
    }
    genReport($figureStart, $figureEnd, $numPatients, $numExams, @missingExams);
    
    #Deletes all the subfolders in these directories to prevent massive build up of empty folders if so desired
    if ( $delete_DICOM_im == 1 ) {
        print "\tCleaning up the DICOM Image Directory since delete_dicom_im switch = $delete_DICOM_im.\n";
        remove_tree("$prog_path/DICOM_images",{keep_root => 1});                         
    }
    if ( $dumped_data and $delete_dumped_data == 1 ) {
        print "\nCleaning dumped data since delete_dumped_data switch = $delete_dumped_data. To change this switch, consult $config_file.\n";
#If switch to delete dumped data is set in configuration file, delete dumped data after extracting relevant fields. Also, remove any iamges that were moved to the corresponding derived folder.
        remove_tree($dumped_data);
        remove_tree("$prog_path/dumped_data", {keep_root => 1});
    }
    
#the option to run in list mode is in the configuration file. If it's running in list mode, no need to sleep after an iteration of the script. If it's just running one patient, it'll just die when finished.
    if ( $list_switch == 1 ) {
        print "Moving on...\n";
    }
    elsif ( $run_specific_exam == 1 ) {
        print "Processed specific exam. Exiting\n";
        exit;
    }
    elsif($retrospective == 1){
        my $timestamp = &get_time;
        print "Timestamp $timestamp\n";
        my ( $currenttime, $startdate ) = split ' ', $timestamp;
        my ( $hr, $min, $sec ) = split '\\:', $currenttime;
        $min = sprintf( "%2d", $min );
        $min =~ tr/ /0/;
        $sec = sprintf( "%2d", $sec );
        $sec =~ tr/ /0/;
        $currenttime = "$hr$min$sec";
        print "Finished running through the specified days. Done at $currenttime";
        exit;
    }
    #For a prospective running, checks to see if the time is greater than the start date, meaning it is a new day, and changes the study_date accordingly.
    else {
        print "sleeping for $time_between_queries seconds\n";
        
        #to not overload the PACS
        sleep($time_between_queries);
        my $timestamp = &get_time;
        print "Timestamp $timestamp\n";
        my ( $currenttime, $startdate ) = split ' ', $timestamp;
        my ( $hr, $min, $sec ) = split '\\:', $currenttime;
        $min = sprintf( "%2d", $min );
        $min =~ tr/ /0/;
        $sec = sprintf( "%2d", $sec );
        $sec =~ tr/ /0/;
        $currenttime = "$hr$min$sec";
        my $day_start = $config->{day_start};
        if($currenttime>$day_start){
                                 
            my ( $m, $d, $y ) = split '\\.', $startdate;
            $m = sprintf( "%2d", $m );
            $m =~ tr/ /0/;
            $d = sprintf( "%2d", $d );
            $d =~ tr/ /0/;
            my $today = "$y$m$d";
            $study_date=$today;
            print "It's the start of a new day, changing prospective study date to todays date: $today\n"
        }
        else{
            print "No new day yet...\n";
        }
    }

    #}

}


sub exe_query {

#query PACS - all commands and results are documented in query/retrieve and query result log

    $timestamp = &get_time;

#                                                                                               MRN           Patient Name       Retrieval Level   Study Date      Study Description     Modality in Study         Series #  Series related instances Series description  Birthday        accession           studyuid         series time     #studyrelatedinstaces       #Study ID         #InstanceNumber     #Study Time    #ImageType    #ContentTime  #Modality          #SOP Class UID
    my $cmd_query =
"$query_path --study --aetitle $aet_title --call $aec_title $aec_ip $aec_port -k 0010,0020$_[0] -k 0010,0010$_[1] -k 0008,0052$_[2] -k 0008,0020$_[3] -k 0008,1030$_[4] -k 0008,0061$_[5] -k 0020,0011$_[6] -k 0020,1209$_[7] -k 0008,103e$_[8] -k 0010,0030$_[9] -k 0008,0050$_[10] -k 0020,000d$_[11] -k 0020,000E$_[12] -k 0020,1208$_[13] -k 0008,0031$_[14] -k 0020,0010$_[15] -k 0020,0013$_[16] -k 0008,0030 -k 0008,0008 -k 0008,0033 -k 0020,1041 -k 0008,0060$_[17] -k 0008,0016";

    print "Querying with the command:\n$cmd_query\n";
    &persevering_call( $cmd_query, $tmp_query_log, "10" );

    #log the query results in log file, this is no longer in use.
    # open( FH, '<', $tmp_query_log );
    # while ( my $line = <FH> ) {

        # #print QLOG $line;
    # }
    # close FH;

    #print QLOG "\n\n";
}

sub get_exam_info {

    #written originally by JH, modified by SW
    #Modified by WK to also get study IDs, though this value is no longer used
    print "IN CHECK PATIENT\n";

    #parse study-level query results and return the number of patients found
    ########################
    # undef @study_UIDs;
    # undef @MRN_study;
    # undef @instances;
    # ########################
    ########################
    #define all arrays
    my @StudyDate_study;
    my @study_UIDs;
    my @MRN_study;
    my @modality_study;
    my @Studytime;
    my @instances;
    my @accession_study;
    my @studyIDs; #NOT UID
    my @studyDesc;
    my $counter = 0;
    my $check = 0;
    my %studies; #Hash of studies already looked at and their index position.
    my $needCheck = 0;
    ########################
    open( TMALOG, '<', $_[0] ) or print QRLOG "Can't open $_[0] because $!\n";

    while ( my $line = <TMALOG> ) {

        if ( $line =~ m/0008,0020/g ) {    #get study date
            ($value) = $line =~ /\[(.+?)\]/;
            push( @StudyDate_study, $value );
        }
        elsif ( $line =~ m/0008,1030/g ) {    #get study description
            ($value) = $line =~ /\[(.+?)\]/;
            push( @studyDesc, $value );
        }
        elsif ( $line =~ m/0010,0020/g ) {    #get MRN
            ($value) = $line =~ /\[(.+?)\]/;
            push( @MRN_study, $value );
        }
        elsif ( $line =~ m/0002,0016/g ) {    #get modality
            ($value) = $line =~ /\[(.+?)\]/;
            push( @modality_study, $value );
        }
        elsif ( $line =~ m/0008,0050/g ) {    #get acccession number
            ($value) = $line =~ /\[(.+?)\]/;
            push( @accession_study, $value );
        }
        elsif ( $line =~ m/0020,000d/g ) {    #get study UID
            ($value) = $line =~ /\[(.+?)\]/;
            push( @study_UIDs, $value );            
        }
        elsif($line =~ m/0008,0030/g){        #get study time
            ($value) = $line =~ /\[(.+?)\]/;
            push(@Studytime,$value); 
        }
       
        elsif($line =~ m/0020,0010/g){        #Study ID
            ($value) = $line =~ /\[(.+?)\]/;
             push(@studyIDs, $value);
            #Can't use push, because a study won't have a study ID, so place in its spot to keep with sync with other info arrays.
            my $counter= $#accession_study;
                     
        }
       
    }

    #@MRN_study = uniq @MRN_study;
    my $number_patients = @MRN_study;
    my $number_exams    = @accession_study;
    print "\nFound the following exams: @accession_study\n";
    print
"\nFound $number_exams exams from $number_patients patients on $study_date. Now retrieving individual series...\n";
    
    #print "Found @study_UIDs\n";
    #print "Found @accession_study\n";

    close TMALOG;
###########################################
    # #clear all arrays
    # undef @StudyDate_study;
    # #undef @study_UIDs;
    # #undef @MRN_study;
    # undef @modality_study;
    # undef @Studytime;
    # #undef @instances;
    # return $j;
##########################################
#########################################
   
    
    return ( $number_exams, \@StudyDate_study, \@study_UIDs, \@MRN_study,
        \@modality_study, \@Studytime, \@instances, \@accession_study, \@studyIDs );

    #clear all arrays Why is this here, if it's after the return statement...?
    # @StudyDate_study = ();
    # @study_UIDs      = ();
    # @MRN_study       = ();
    # @modality_study  = ();
    # @Studytime       = ();
    # @instances       = ();
    # @accession_study = ();
    # @studyIDs        = ();
###########################################
}

sub get_series_info {

#written originally by JH, modified by SW
#clear these arrays first instead of after; their elements must be defined since they are piped for use into the main script
# undef @SeriesNumber_series;
# undef @StudyDate_series;
# undef @ImagesInSeries_series;
# undef @Series_times;
# undef @SeriesDescription_series;
# undef @Accession_series;
# undef @series_UIDs;

    #define arrays
    my @StudyDate_series;
    my @Accession_series;
    my @Series_times;
    my @Modality_series;
    my @StudyDescription_series;
    my @SeriesDescription_series;
    my @PatientName_series;
    my @MRN_series;
    my @SeriesNumber_series;
    my @ImagesInSeries_series;
    my @Birthday_series;
    my @series_UIDs;
    my @contentTimes;
    my @sLoc;
    my @imageTypes;
    my $notSkip =1;
    open( TMALOG, '<', $_[0] ) or print QRLOG "Can't open $_[0] because $!\n";
    while ( my $line = <TMALOG> ) {
        
        #If the image type is derived, then it doesn't need to read the lines following this until it hits a new series. This is made possible because image type is the first
        #information provided by findscu when giving info about a series.
        if ( $line =~ m/0008,0008/g ) {    #get Image type
            ($value) = $line =~ /\[(.+?)\]/;
           
            if ($value =~ m/DERIVED/g){
               
                $notSkip =0;
            }
            elsif ($value =~ m/SECONDARY/g){
                 $notSkip=0;
            }
            else {
                push(@imageTypes,$value );
                $notSkip =1;
            }
            
        }
        if($notSkip){
            if ( $line =~ m/0008,0020/g ) {    #get study date
               
                ($value) = $line =~ /\[(.+?)\]/;            
                push( @StudyDate_series, $value );
            }
            elsif($line =~ m/0008,0033/g){
                ($value) = $line =~ /\[(.+?)\]/;
                my $indexIs = $#StudyDate_series;
                #Ensures that it is in sync with the other arrays in case there is no contnent time for a study (though I don't know how often if ever this happens)
                $contentTimes[$indexIs]=$value;    
                
            }
            elsif ( $line =~ m/0008,0050/g ) {    #get accession number
                ($value) = $line =~ /\[(.+?)\]/;
                push( @Accession_series, q{"} . $value . q{"} );
            }
            elsif ( $line =~ m/0008,0060/g ) {    #get modality
                ($value) = $line =~ /\[(.+?)\]/;
                push( @Modality_series, $value );

            }
            elsif ( $line =~ m/0008,1030/g ) {    #get study description
                ($value) = $line =~ /\[(.+?)\]/;
                $value =~ s/,//g;
                push( @StudyDescription_series, q{"} . $value . q{"} );
            }
            elsif ( $line =~ m/0008,103e/g ) {    #get series description
                ($value) = $line =~ /\[(.+?)\]/;
                push( @SeriesDescription_series, $value );
            }
            elsif ( $line =~ m/0010,0010/g ) {    #get Patient Name
                ($value) = $line =~ /\[(.+?)\]/;
                push( @PatientName_series, $value );
            }
            elsif ( $line =~ m/0010,0020/g ) {    #get MRN
                ($value) = $line =~ /\[(.+?)\]/;
                push( @MRN_series, $value );
            }
            elsif ( $line =~ m/0020,0011/g ) {    #get series number
                ($value) = $line =~ /\[(.+?)\]/;
                push( @SeriesNumber_series, $value );
               
            }
            elsif ( $line =~ m/0010,0030/g ) {    #get birthday
                ($value) = $line =~ /\[(.+?)\]/;
                push( @Birthday_series, $value );
            }
            elsif ( $line =~ m/0020,1041/g ) {    #get Slice Location
                ($value) = $line =~ /\[(.+?)\]/;
               $sLoc[$#StudyDate_series]=$value;
            }
            elsif ( $line =~ m/0020,1209/g ) {    #seriesrelatedinstances
                ($value) = $line =~ /\[(.+?)\]/;
                
                push( @ImagesInSeries_series, $value );
                
                #Ensures that those with less than 10 images are not used in the content times filtering. Can't use pop because not all series have Content Times.
                if($value<10){
                   
                    $contentTimes[$#ImagesInSeries_series]="";
                    
                }
                
                
            }
            elsif ( $line =~ m/0008,0031/g ) {    #seriestime
                ($value) = $line =~ /\[(.+?)\]/;
                push( @Series_times, $value );
                              
            }
            elsif ( $line =~ m/0020,000e/g ) {    #series uid
                ($value) = $line =~ /\[(.+?)\]/;
                push( @series_UIDs, $value );

                #print "Series uid $value\n";

            }
        }
    }

    # my $k            = 0;
    my $total_series = @SeriesNumber_series;
    print "\n\n    Found $total_series series...\n";
    
    
    close TMALOG;

    print("The following series are taken: ",@SeriesNumber_series,"\n");
    print("SERIES content times: @contentTimes\n");   

    return (
        $total_series,              \@StudyDate_series,
        \@Accession_series,         \@Series_times,
        \@Modality_series,          \@StudyDescription_series,
        \@SeriesDescription_series, \@PatientName_series,
        \@MRN_series,               \@SeriesNumber_series,
        \@ImagesInSeries_series,    \@Birthday_series,
        \@series_UIDs,              \@contentTimes,
        \@sLoc,                     \@imageTypes
    );

    #empty arrays. Again, why are these after the return statement?
    # @StudyDate_series         = ();
    # @Accession_series         = ();
    # @Series_times             = ();
    # @Modality_series          = ();
    # @StudyDescription_series  = ();
    # @SeriesDescription_series = ();
    # @PatientName_series       = ();
    # @MRN_series               = ();
    # @SeriesNumber_series      = ();
    # @ImagesInSeries_series    = ();
    # @Birthday_series          = ();
    # @series_UIDs              = ();

}

sub exe_retrieve {

#subroutine to retrieve images from PACS - all commands and results are documented in query/retrieve and retrieve result log

#                                                                                                                                            MRN             Retrieval         accession #      study date   study description      modality          series #  series related instances  series description o/p dir
    my $cmd_retrieve =
"$retrieve_path --study -v --aetitle $aet_title --port $aet_port --move $aet_title --call $aec_title $aec_ip $aec_port -k 0010,0020$_[0] -k 0008,0052$_[1] -k 0008,0050$_[2] -k 0008,0020$_[3] -k 0008,1030$_[4] -k 0008,0061$_[5] -k 0020,0011$_[6] -k 0020,000e$_[7] -k 0008,103e$_[8] -od $_[9]";
    print "\tRetrieving with the following command:\n\t$cmd_retrieve\n";
    &persevering_call( $cmd_retrieve, $tmp_retrieve_log, "100" );

}

sub persevering_call

#if a file cannot be accessed (most likely due to a race condition), this sub retries up to 10 times, giving the file $space seconds each time to free up
#call like &persevering_call("echo Hello, this is a test call.", $call_op_log, $space);
{
    my $race_counter = "0";
    my $space        = $_[2];
    my $call_op_log  = $_[1];

   #print "for persevering call, I get space $space, call log $call_op_log..\n";
    my $status = system "$_[0] > $call_op_log";

    #print "$_[0]> $call_op_log\n";

    until ( $status == "0" ) {
        print "Race condition identified. Retrying after $space seconds...\n";
        sleep $space;    #give the file some space
        $status = system "$_[0] > $call_op_log";

        #print "status after retrying $status\n";
        $race_counter++;

        if ( $race_counter > 10 ) {
            print
"Tried to make the system call 10 times(!)...might there be a problem with the syntax of the call?";
            last;
        }
    }

    if ( $status != "0" ) {
        print "--exited because enough is enough!\n";
    }
    else {
        #print "DCMTK executable: success\n";
    }

}

sub image_check {

    #this sub ensures that all images have uploaded to a series

    my $count = 0;
    my $item  = $_[0];
    my $cmd_query =
"$query_path --study --aetitle $aet_title --call $aec_title $aec_ip $aec_port -k 0008,0052=STUDY -k 0020,1208 -k 0008,0050=$item";
    print "\tIMAGE CHECK:Querying with command:\n$cmd_query\n";
    my $image_no_log = "$log_dir/study_im.txt";
    system "$cmd_query > $image_no_log";
    my $images_before = 0;
    open( IMLOG, '<', $image_no_log ) or print "Can't open $_[0] because $!\n";

    while ( my $line = <IMLOG> ) {
        if ( $line =~ m/0020,1208/g ) {

            #get number of images in study
            ($images_before) = $line =~ /\[(.+?)\]/;
        }
    }
    close IMLOG;

    print "\tIMAGE CHECK:Images before: $images_before\n";
    my $images_before_query = $images_before;
    my $images_after_query  = "0";

    #print "Have $images_before_query images before first query\n";
    until ( $images_before_query == $images_after_query ) {
        print
"\tIMAGE CHECK:Ensuring that all the images uploaded to the PACS...\n";
        print
"\tIMAGE CHECK:Have $images_before_query images before $count ith query\n";
        
        ###############################
        #query again to see how many images there are
        print
"\tIMAGE CHECK:Now, I'm querying to see if the images are constant. Right now, I think there are $images_before_query. My images after query (for now) is $images_after_query\n";

        my $cmd_query =
"$query_path --study --aetitle $aet_title --call $aec_title $aec_ip $aec_port -k 0008,0052=STUDY -k 0020,1208 -k 0008,0050=$item";
        print "\tIMAGE CHECK:Querying with command:\n$cmd_query\n";
        $image_no_log = "$log_dir/study_im.txt";
        system "$cmd_query > $image_no_log";
        open( IMLOG, '<', $image_no_log )
          or print "\tIMAGE CHECK ERROR:Can't open $_[0] because $!\n";
        while ( my $line = <IMLOG> ) {
            if ( $line =~ m/0020,1208/g ) {

                #get number of images in series
                ($images_after_query) = $line =~ /\[(.+?)\]/;
            }
        }
        close IMLOG;
        ###############################

        print
"\tIMAGE CHECK:I just did the query and got back $images_after_query images after query\n";

        if ( $images_after_query == $images_before_query ) {
            print "\tIMAGE CHECK:Images fully uploaded.\n";

        }

        else {
            print
              "\tIMAGE CHECK:$images_before_query is not $images_after_query\n";
            $images_before_query = $images_after_query;
            print
"\tIMAGE CHECK:setting images before query to $images_after_query. So images before query (before variable: $images_before_query) should now be after variable: $images_after_query\n";

            $images_after_query = "0";
            print
"\tIMAGE CHECK:setting images after query to $images_after_query\n";
            print "\tIMAGE CHECK:count: $count\n";
            $count++;
            print "\tIMAGE CHECK:sleeping 30\n";
            sleep 30;
        }

        if ( $count > 30 ) {
            print
"\tIMAGE CHECK:It's taken so long for the images to upload that there might be something wrong with this series?\n";
            exit;
        }
    }
###############################################
}

sub terminate_if_date {

    #if it's a certain date, exit.
    if ( $terminate == 1 ) {

        my $today = $_[0];
        print
"Since 'termin' switch is '$terminate', running ending engine on date $end_date and after time $end_hour.\n";
        ( $sec, $min, $hour, $mday, $mon, $year ) = localtime();
        if ( $today == $end_date and $hour > $end_hour ) {
            exit;
        }

    }
}

sub schedule_engine {
#note that this sub depends on get_time and time_elapsed. schedule_engine times the engine depending on 'nightly' switch in the config file
#this sub just makes the engine sleep depending on the time of day (e.g., if it's set to run at night, it makes it sleep until night)
#for prospective use, insert this before last bracket of while{}, i.e. :
#                                     $prog_count = 2;
#                                     while ( $prog_count > 1 ) {
#                                                  ...
#                                     &schedule_engine;
#                                     }
#Alternatively, for retrospective use, insert schedule_engine inside the study-processing loop so that the engine can process a large number of studies but still adhere to a schedule (e.g., if you want it not to run during the day)

    $timestamp = &get_time;
    my ( $currenttime, $startdate ) = split ' ', $timestamp;
    my ( $hr, $min, $sec ) = split '\\:', $currenttime;
    $min = sprintf( "%2d", $min );
    $min =~ tr/ /0/;
    $sec = sprintf( "%2d", $sec );
    $sec =~ tr/ /0/;
    $currenttime = "$hr$min$sec";

    my $day_start = $config->{day_start};

    #my $day_start = 60000;
    #my $day_end = 190000;
    my $day_end = $config->{day_end};
    print "Day start:$day_start. Day end:$day_end\n";
    my $until_night     = abs( time_elapsed($day_end) ) * 60;
    my $until_day       = abs( time_elapsed($day_start) ) * 60;
    my $hrs_until_night = ( $until_night / 60 ) / 60;
    my $hrs_until_day   = ( $until_day / 60 ) / 60;

    if ( $nightly == 1 ) {

        if ( $currenttime < $day_start or $currenttime >= $day_end ) {

            print
"Current time: $currenttime. This is in the range as determined by 'nightly' switch. Hence, continuing.\n";

            # print "sleeping for $time_between_queries seconds\n";
            # sleep($time_between_queries);

        }
        else {

            print
"It's $currenttime. Since the engine is set to run nightly, going to sleep for $hrs_until_night hours.\n";

            #print "Sleeping $until_night seconds\n";
            sleep $until_night;

        }

    }
    elsif ( $nightly == '0' ) {

        if ( $currenttime >= $day_start and $currenttime < $day_end ) {

            print
"Current time: $currenttime. This is in the range as determined by 'nightly' switch. Hence, continuing.\n";

            # print "sleeping for $time_between_queries seconds\n";
            # sleep($time_between_queries);

        }
        else {

            print
"It's $currenttime. Since the engine is set to run daily, going to sleep for $hrs_until_day hours.\n";
            sleep $until_day;

        }

    }
    else {
        print "Please set 'nightly' in the configuration file.\n";
    }



    sub time_elapsed {

#This is a subroutine to determine the time elapsed from a DICOM tag value HHMMSS to the time that this subroutine is called. It is used to ensure that the
#study has been in the PACS long enough to be queried at the series level (or has been in the PACS too long to any further be considered). Now, am using it for this
#there are many cpan modules that do this, but it was so easy to write that I just left it.
#This has been validated, but if there is a problem with this sub, it is likely that the input time is not in the correct format

        my $Ref_time = $_[0];

        #print "Time in original format: $Ref_time\n";

        my $left_sec  = chop($Ref_time);
        my $right_sec = chop($Ref_time);
        my $seconds   = "$right_sec$left_sec";

        my $left_min  = chop($Ref_time);
        my $right_min = chop($Ref_time);
        my $minutes   = "$right_min$left_min";

        my $left_hr  = chop($Ref_time);
        my $right_hr = chop($Ref_time);
        my $hours    = "$right_hr$left_hr";

        #print "Original time, reformatted: $hours:$minutes:$seconds\n";
        my $elapsed_sec_study = 60 * 60 * $hours + 60 * $minutes + $seconds;

#print "Time in seconds elapsed from 00:00:00 to ref_time: $elapsed_sec_study\n";

        my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime();

        #print "Current time: $hour:$min:$sec\n";
        my $elapsed_sec_now = 60 * 60 * $hour + 60 * $min + $sec;

#print "Time in seconds elapsed from 00:00:00 until right now: $elapsed_sec_now\n";

        my $sec_diff    = $elapsed_sec_now - $elapsed_sec_study;
        my $min_between = $sec_diff / 60;
        $min_between = sprintf "%.2f", $min_between;

        #print "\nDifference: $min_between\n";
        return $min_between;

    }

}

sub get_data {
#Combined from a separate perl script, so reason for some of the repetitive stuff.     

#calculates DLP from DICOM headers
#this just sums ctdivols and multiplies that sum by the slice thickness. It's faster than the array method (get_data_from_images_CALC(arrays).pl), but not as transparent
    my $dumped_data       = $_[0];
    my $date_identifier   = $_[1];
    my $SerScanvol        = $_[2];
    my $water_eq_diameter = $_[3];
    my $config_file       = $_[4];
    my $results           = $_[5];
    my $slice_results     = $_[6];
    my $calcResultsLog    = $_[7];
    my $SRfile            = $_[8];

    #my $volume_log       = "$prog_path/Volumes_$name_tag.csv";
    #my $slice_data = $config->{slice_data};
    print "______________________________\n\nStarting get_data.\n\n";
    print "Processing data in $dumped_data.\n\n";
    if ( !$dumped_data ) {
        print "No dumped data path. Dying!\n";
        die;
    }
    if ( $slice_data == 1 ) {
       
        print "Switch 'slice_data' == $slice_data.\n";
        open( SLOG, ">>$slice_results" ) or die "can't open $slice_results bc $!\n";
        print SLOG "\n\nSLICE DATA FOR $dumped_data\n";
        close SLOG;

    }

    print "From body volume calculation: volume = $SerScanvol; Dw = $water_eq_diameter.\n";
    my $timestamp = &get_time;
    my ( $starttime, $startdate ) = split ' ', $timestamp;
    my ( $m, $d, $y ) = split '\\.', $startdate;
    $m = sprintf( "%2d", $m );
    $m =~ tr/ /0/;
    $d = sprintf( "%2d", $d );
    $d =~ tr/ /0/;
    my $today = "$y$m$d";

#########################################################################

########################################################################

    my @patients;

    
    &get_header_data( $dumped_data, $SerScanvol, $water_eq_diameter, $results,$calcResultsLog,$SRfile, $slice_results);

    print "Find results in $results.\n\n";
    if ( $slice_data == 1 ) {
        print "Find slice-specific results in $slice_results.\n";
    }

    if ( $dumped_data and $delete_dumped_data == 1 ) {
        print "\nRemoving $dumped_data since delete_dumped_data switch = $delete_dumped_data. To change this switch, consult $config_file.\nFinished processing.\n";

#If switch to delete dumped data is set in configuration file, delete dumped data after extracting relevant fields.
# Also, remove any iamges that were moved to the corresponding derived folder. This folder is fully cleaned after a study is done processing
        remove_tree($dumped_data);
        remove_tree("$dumped_data\_derived");

    }
    else {
        print
"Not removing $dumped_data since delete_dumped_data switch = $delete_dumped_data (or, $dumped_data DNE). To remove dumped data after processing, change the delete_dumped_data switch in $config_file.\n";
    }

    #print "all patients: @patients";

    sub get_header_data {

        #select LOG;
        my $SerScanvol        = $_[1];
        my $water_eq_diameter = $_[2];
        my $results           = $_[3];
        my $resultsLog        = $_[4];
        my $SRfile            = $_[5];
        my $slice_results     = $_[6];
        my %tags = &define_tags;
        my $sum_exposure      = 0;
        my $sum_of_ctdindices = 0;
        my $sum_of_current    = 0;
        my $image_counter     = 0;
        my $series_description;
        my $station_name;
        my $protocol_name;
        my $protocol_number;
        my $private_creator;
        my $scanner_type;
        my $scanner_maker;
        my $no_images;
        my $series_no;
        my $MRN;
        my $slice_thickness;
        my $Kind;
        my $scanner_model;
        my $accession;
        my $pitch;
        my $age;
        my $kvp;
        my $uid;
        my $current;

        #my $series_time;
        my $end_of_uid;
        my $total_collimation_width;
        my $single_collimation_width;
        my $scanlength;
        my $studyTime;
        my $study_date;
        my $body_volume;
        my $requesting_physician;
        my $filterType;
        my $exposure_time;
        my $kernel;
        my $Acquisition_date;
        my $Acquisition_time;
        #my $seriesTime;
        my $Acquisition_number;
        my $Acquisiton_date_time;
        my $average_exposure;
        my $body_part;
        my $length_prob;
        my $length_from_thickness;
        my $DE_dif_in_length;
        my $average_ctdindices;
        my $average_current;
        my $twice_thick_length;
        my $scan_length; #this one is reserved for studies with no locations (older studies lack location tag)
        my $image_type;
        my $table_speed;
        my $exp_0;
        my $exp_f;
        my @acq_times;
        my @slice_locations;
        my @exposures;
        my $size_ex_array;
        my $st_description;
        my $name;
        my $gender;
        my @contentTimes;
        my $exposure;
        my $ctdivol;
        my $irradiationUID;
        ######################
        #these were commented before.
        my $DLP_from_indices;
        ######################

        

        ########## it's possible these need to be initialized elsewhere
        my $start_time;
        my $end_time;
        my $startConTime;
        my $endConTime;
        my $scan_time;
        my $series_time;
        my $slice_location_0;
        my $slice_location_f;
        my $value;
        ######################
        opendir( DIR, $_[0] ) or die $!;
        
        while ( my $file = readdir(DIR) ) {
            my $myfile = "$_[0]/$file";

            #print "Looking at $myfile\n";

            open( FH, '<', $myfile );
            my %seen;

            while ( my $line = <FH> ) {

                foreach my $key ( keys %tags ) {

                    if ( $line =~ m/$key/ ) {

                    #if the line matches one of the keys in the hash, it's something to extract

                        if ( $seen{$key}) {

                        #if the value is already seen once in the file, no need to take it again. this takes the FIRST value, then. this may not always be the best
                        #print "Aleady got a value for $key\n";

                        } else {

                            if ( $line =~ m/\[/ ) {

                                #take whatever is in between brackets
                                ($value) = $line =~ /\[(.+?)\]/;
                                ($value) =~ s/\s*$//;

                            }
                            else {
                             #sometimes, the value is after FD-- NOT in brackets
                                chomp $line;

                                #print "'$line'\n";
                                $line =~ s/\s*$//g;

                                #print "after '$line'\n";

                                ($value) = $line =~ /FD (.+?) #/;
                                ($value) =~ s/\s*$//;

                                #print "FD'$value'\n";

                            }

                            ##########################
                            if ($value) {

                            #if there is a value that matches a key in the hash:

                                if ( $key eq "0018,1152" ) {
                                    $sum_exposure = $sum_exposure + $value;
                                    push( @exposures, $value );
                                    $seen{$key} = '1';
                                    $exposure = $value;
                                }
                               
                                
                                if ( $key eq "0008,0050" ) {
                                    $accession = $value;
                                    $seen{$key} = '1';

                                }
                                if ( $key eq "0008,1030" ) {
                                    $st_description = $value;
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0010,1010" ) {
                                    $age = $value;
                                    $seen{$key} = '1';
                                }

                                if ( $key eq "0010,0020" ) {
                                    $MRN = $value;
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0018,0060" ) {
                                    $kvp = $value;
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "07a1,10c0" ) {
                                    $scanner_model = $value;
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0008,0031" ) {
                                    $series_time = $value;
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0008,0008" ) {
                                    $Kind = $value;
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0020,000e" ) {
                                    $uid        = $value;
                                    $end_of_uid = substr( $uid, -8 );
                                    $seen{$key} = '1';

                                }

                                #print "$tags{$key}(KEY $key):$value\n";
                                if ( $key eq "0018,9345" ) {
                                    $ctdivol = $value;
                                    #print "indice value: $value\n";
                                    $sum_of_ctdindices =
                                      $sum_of_ctdindices + $value;

                                    #print "summer: $sum_of_ctdindices\n";
                                    $seen{$key} = '1';
                                }
                                
                                if ($key eq "0018,1151" ){
                                    $current = $value;
                                    $sum_of_current = $sum_of_current + $value;
                                    $seen{$key} = '1';
                                }

                                if ( $key eq "0018,0050" ) {

                                    $slice_thickness = $value;
                                    $slice_thickness = $slice_thickness / 10;
                                    $seen{$key}      = '1';
                                }

                                if ( $key eq "0010,0020" ) {

                                    $MRN = $value;
                                    $seen{$key} = '1';
                                }

                                if ( $key eq "0020,0011" ) {

                                    $series_no = $value;

                                    #print "$value,";
                                    $seen{$key} = '1';
                                }

                                if ( $key eq "0008,103e" ) {

                                    $series_description = $value;
                                    $seen{$key} = '1';
                                }

                                if ( $key eq "0020,0013" ) {

                                    $no_images = $value;

                                    #print "instance num $value,";
                                    $seen{$key} = '1';
                                    $image_counter++;
                                }

                                if ( $key eq "0008,0070" ) {

                                    $scanner_maker = $value;
                                    $seen{$key} = '1';
                                }

                                if ( $key eq "0008,1090" ) {

                                    $scanner_type = $value;
                                    $seen{$key} = '1';
                                }

                                if ( $key eq "0009,0010" ) {

                                    $private_creator = $value;
                                    $seen{$key} = '1';
                                }

                                if ( $key eq "0018,1030" ) {

                                    $protocol_name = $value;
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0008,1010" ) {

                                    $station_name = $value;
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0008,0008" ) {

                                    $image_type = $value;

                                    $seen{$key} = '1';
                                }
                                if ( $key eq "07a1,1071" ) {

                                    $protocol_number = $value;
                                    $seen{$key} = '1';
                                }

                                if ( $key eq "0018,9311" ) {

                                    $pitch = $value;
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0020,1041" ) {

                                    #print "Loc:$value,";
                                    push( @slice_locations, $value );
                                    $seen{$key} = '1';

                                }
                                
                                if ( $key eq "0008,0030" ) {

                                    #print "Loc:$value,";
                                    $studyTime = $value;
                                    $seen{$key} = '1';

                                }
                                

                                if ( $key eq "0018,9307" ) {

                                    $total_collimation_width = $value;

                             #print "COLLIMATION: '$total_collimation_width'\n";
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0018,9306" ) {

                                    $single_collimation_width = $value;

                            #print "COLLIMATION: '$single_collimation_width'\n";
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0032,1032" ) {

                                    $requesting_physician = $value;
                                    $seen{$key} = '1';

                                }
                                
                                if ( $key eq "0018,1160" ) {

                                    $filterType = $value;
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0018,1150" ) {

                                    $exposure_time = $value;
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0018,9309" ) {

                                    $table_speed = $value;
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0018,9310" ) {

                                    $table_speed = $value;
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0018,1210" ) {

                                    $kernel = $value;
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0020,0012" ) {

                                    $Acquisition_number = $value;
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0008,0032" ) {

                                    $Acquisition_time = $value;
                                    push( @acq_times, $value );
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0008,0022" ) {

                                    $Acquisition_date = $value;
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0008,002a" ) {

                                    $Acquisiton_date_time = $value;
                                    $seen{$key} = '1';

                                }

                                if ( $key eq "0018,0015" ) {

                                    $body_part = $value;

                                    #print "body part $value\n";
                                    $seen{$key} = '1';

                                }
                                if ( $key eq "0010,0010" ) {

                                    $name = $value;

                                    #print "body part $value\n";
                                    $seen{$key} = '1';

                                }
                                if ( $key eq "0010,0040" ) {

                                    $gender = $value;

                                    #print "body part $value\n";
                                    $seen{$key} = '1';

                                }
                                if ( $key eq "0008,0033" ) {
                                    push(@contentTimes,$value);
                                }
                                if( $key eq "0008,3010"){
                                    
                                    $irradiationUID = $value;
                                }
                                
                            }
                        }

                    }

                }

            }

            ######
            if ( $slice_data == 1 ) {

                unless ( !$MRN ) {
                    open( SLOG, ">>$slice_results" )
                      or die "can't open LOG bc $!\n";
                    print SLOG "$MRN,",
                      "$accession,",
                      "$protocol_name,",
                      "$protocol_number,",
                      "$series_no,",
                      "$image_counter,",
                      "$scanner_type,",
                      "$scanner_maker,",
                      "$series_description,",
                      "$ctdivol,",
                      "$DLP_from_indices,",
                      "$pitch,",
                      "$single_collimation_width,",
                      "$total_collimation_width,",
                      "$kvp,$scanlength,",
                      "$end_of_uid,",
                      "$age,",
                      "$exposure_time,",
                      "$average_exposure,",
                      "$exposure,",
                      "$kernel,",
                      "$study_date,",
                      "$image_type,",
                      "$Acquisition_date,",
                      "$Acquisition_time,",
                      "$Acquisition_number,",
                      "$Acquisiton_date_time,",
                      "$slice_location_0,",
                      "$slice_location_f,",
                      "$body_part,",
                      "$length_from_thickness,",
                      "$slice_thickness,",
                      "$table_speed,",
                      "$series_time,",
                      "$start_time,",
                      "$end_time,",
                      "$scan_time,",
                      "$exp_0,",
                      "$exp_f,",
                      "$st_description,",
                      "$name,",
                      "$gender,",
                      "$SerScanvol,",
                      "$water_eq_diameter,",
                      "$studyTime\n";
                    close SLOG;
                }
            }
            ######
            close FH;
        }
        close DIR;

        $size_ex_array = @exposures;
        $exp_0         = $exposures[0];
        $size_ex_array = $size_ex_array - 1;
        $exp_f         = $exposures[$size_ex_array];
        $start_time    = min @acq_times;
        $end_time      = max @acq_times;
        $startConTime  = min @contentTimes;
        $endConTime    = max @contentTimes;
        $scan_time     = $end_time - $start_time;
        $scan_time     = $endConTime - $startConTime;
        $length_from_thickness = $slice_thickness * $image_counter;
        $slice_location_0      = min @slice_locations;
        $slice_location_f      = max @slice_locations;
        $scanlength            = ( $slice_location_f - $slice_location_0 ) / 10;
        if ( $scanlength == '0' ) {
            print
"There wasn't a slice location for this one OR it really has no length..making scan length $image_counter*$slice_thickness (#images*thickness)";

            if ( $slice_thickness == '0.2' ) {
                print "Slice thickness is 0.2, dividing it by 2\n";
                $slice_thickness = $slice_thickness / 2;

            }

            $scan_length = $image_counter * $slice_thickness;
            print "Assuming this is recon\n";
            $scanlength  = '0';
            $series_time = '9999'
              ; #set these two far apart so it gets flagged as 0 and not counted

        }

#if this difference is too large, then it was most likely one of the weird series that has two series within. if these are all reconstructions, those can be left out. if they aren't, TBC...
#Theory: This only happens with DE, and, when this is the case, at least one of the series inside a series is a reconstruction AND it contains PP,MPR,or VNC in its series description.
#Hence, filtering out series with PP, MPR, or VNC from even being retrieved should solve this problem.
#Also, might make the directory name based on uid, not just series number.

        unless ( $image_counter == 0 ) {
            $average_ctdindices = $sum_of_ctdindices / $image_counter;
            $average_exposure   = $sum_exposure / $image_counter;
            $average_current    = $sum_of_current / $image_counter;
        }

        $DLP_from_indices = $average_ctdindices * $scanlength;
        my $overscan = 0;
        #Adding overscan values based on regression models to the resulting DLP values to estimate final ones.
        unless ( $DLP_from_indices == '0' ) {
            #Maybe include if pitch, as that header seems to relate with whether or not helical is being done/need overscan... also, philips never included it in their header...
            if ( $scanner_maker =~ m/Siemens/gi ) {
                $overscan =
                  40.98918311 + 0.009254232 * $exp_0 + 0.014539485 * $exp_f;
            }
            elsif ( $scanner_maker =~ m/Toshiba/gi ) {
                if (
                    (
                           $protocol_name eq "Cardiac Prospective CAC+CTA-Chen"
                        or $protocol_name eq "Calcium Score - ClinSeq"
                        or $protocol_name eq "Cardiac Mass CAC+CTA+Venous-Chen"
                        or $protocol_name eq "Carotid Cardiac CTA"
                        or $protocol_name eq "Carotid Cardiac Part2"
                    )
                    and ( $st_description eq "CT Non-Cardiac Finding" )
                  )
                {
                    print
"This is description '$st_description' of protocol '$protocol_name'. No overscan for these exams.\n";
                    $overscan = 0;
                }
                else {
                    $overscan = 2.9337975 + 0.56161244 * $average_exposure;
                }
            }
            elsif ( $scanner_maker =~ m/Philips/gi ) {
                $overscan =
                  -13.90473368 + 0.35571065 * $exp_0 + 0.434828045 * $exp_f;
            }
            else {
                print
"Do not recognize vendor '$scanner_maker'. Not adding overscan, since have no regression for this vendor.\n";
            }
        }

        print
          "\nSeries number: $series_no;\nDescription: $series_description;\n";
        print "Overscan $overscan being added to $DLP_from_indices.\n";
        $DLP_from_indices = $DLP_from_indices + $overscan;
        #Gets the exact values from the SR so no worry about overscan
        if($SRfile){
            ($DLP_from_indices,$average_ctdindices)=getSRDose($irradiationUID,$SRfile);
        }
        
        #Some are not done helically, and filters out by pitch (as pitch shows that its helical or not)
        if (    ($st_description eq "CT Chest (High Resolution)" or $st_description eq  "CT Lung - Limited Prone Select Slices")
            and ($scanner_maker eq "SIEMENS" || $scanner_maker eq "TOSHIBA") and !$SRfile)
        {
            print
"This is $st_description from $scanner_maker! Using slice thickness ($slice_thickness) rather than slice location for the length of scan. Writing over previous variable $DLP_from_indices and not adding overscan\n";
            if(!$pitch){
                $DLP_from_indices = $average_ctdindices * $length_from_thickness;
            }
        }
        elsif ( $st_description eq "CT Chest (High Resolution)"
            and $scanner_maker eq "TOSHIBA" )
        {
            print
"This is a $st_description but maker is $scanner_maker. Doing nothing\n";
        }

        print "DLP: $DLP_from_indices.\n\n";
        
        #calculating estimated dose from this.
        
        

#This was done for the csv files. So, output for some of the fields, e.g., series description (since it often has a comma), is slightly diff from input fields.
        $series_description =~ s/\,/_/g;
        $scanner_type =~ s/\,/_/g;
        $scanner_maker =~ s/\,/_/g;
        $protocol_name =~ s/\,/_/g;
        $protocol_number =~ s/\,/_/g;
        $series_description =~ s/\,/_/g;
        $end_of_uid =~ s/\,/_/g;
        $kernel =~ s/\,/_/g;
        $image_type =~ s/\,/_/g;
        $Acquisiton_date_time =~ s/\,/_/g;
        $body_part =~ s/\,/_/g;
        $st_description =~ s/\,/_/g;

        #Get rid of Y and leading 0s. Convert months to year.
        $age =~ s/0*(\d+)/$1/;
        $age =~ s/Y//g;
        if($age=~m/M/){
            $age =~s/M//;
            $age = $age/12;
        }
        my $st_descr = $st_description;
        $st_descr =~ s/[^a-zA-Z0-9]*//g;
        my $estDoseSeries = &calcEstDose($st_descr,$DLP_from_indices, $age, $body_part);
        
#print "new $series_description\n";
#print "AFTER GET_DATA printing scanvol $SerScanvol and Dw $water_eq_diameter to calc results...\n";
        unless ( !$MRN ) {
            open( LOG, ">>",$results ) or die "can't open LOG bc $!\n";
            my $calcPrint = "$MRN,".
              "$accession,".
              "$protocol_name,".
              "$protocol_number,".
              "$series_no,".
              "$image_counter,".
              "$scanner_type,".
              "$scanner_maker,".
              "$series_description,".
              "$average_ctdindices,".
              "$DLP_from_indices,".
              "$pitch,".
              "$single_collimation_width,".
              "$total_collimation_width,".
              "$kvp,$scanlength,".
              "$end_of_uid,".
              "$age,".
              "$exposure_time,".
              "$average_exposure,".
              "$sum_exposure,".
              "$kernel,".
              "$study_date,".
              "$image_type,".
              "$Acquisition_date,".
              "$Acquisition_time,".
              "$Acquisition_number,".
              "$Acquisiton_date_time,".
              "$slice_location_0,".
              "$slice_location_f,".
              "$body_part,".
              "$length_from_thickness,".
              "$slice_thickness,".
              "$table_speed,".
              "$series_time,".
              "$start_time,".
              "$end_time,".
              "$scan_time,".
              "$exp_0,".
              "$exp_f,".
              "$st_description,".
              "$name,".
              "$gender,".
              "$SerScanvol,".
              "$water_eq_diameter,".
              "$studyTime,".
              "$startConTime,".
              "$endConTime,".
              "$estDoseSeries,".
              "$requesting_physician,".
              "$filterType,".
              "$average_current,".
              "$irradiationUID\n";
            if(!$secureOn){
                print LOG $calcPrint;
            }
            else{
                $calcPrint = encode($encoding,$calcPrint);
                print LOG "$calcPrint\n";
            }
            close LOG;
        }
        
         open( CALCRESL, ">>",$resultsLog ) or die "Can't open $resultsLog $!\n" ;
         my $needPrint = "$MRN,".
              "$accession,".
              "$protocol_name,".
              "$protocol_number,".
              "$series_no,".
              "$image_counter,".
              "$scanner_type,".
              "$scanner_maker,".
              "$series_description,".
              "$average_ctdindices,".
              "$DLP_from_indices,".
              "$pitch,".
              "$single_collimation_width,".
              "$total_collimation_width,".
              "$kvp,$scanlength,".
              "$end_of_uid,".
              "$age,".
              "$exposure_time,".
              "$average_exposure,".
              "$sum_exposure,".
              "$kernel,".
              "$study_date,".
              "$image_type,".
              "$Acquisition_date,".
              "$Acquisition_time,".
              "$Acquisition_number,".
              "$Acquisiton_date_time,".
              "$slice_location_0,".
              "$slice_location_f,".
              "$body_part,".
              "$length_from_thickness,".
              "$slice_thickness,".
              "$table_speed,".
              "$series_time,".
              "$start_time,".
              "$end_time,".
              "$scan_time,".
              "$exp_0,".
              "$exp_f,".
              "$st_description,".
              "$name,".
              "$gender,".
              "$SerScanvol,".
              "$water_eq_diameter,".
              "$studyTime,".
              "$startConTime,".
              "$endConTime,".
              "$estDoseSeries,".
              "$requesting_physician,".
              "$filterType,".
              "$average_current,".
              "$irradiationUID\n";
              if(!$secureOn){
                print CALCRESL $needPrint;
              }
              else{
                my $encryptLine = encode($encoding, $needPrint);
                print CALCRESL "$encryptLine\n";
              }
              undef $needPrint;
            close CALCRESL;
         
         

        #print "Done.\n";

    }

    sub define_tags {

        my %tags = (

            "0008,1010" => "Station_Name",
            "07a1,10c0" => "Scanner(TamarMiscString7)",
            "0008,0008" => "Original_or_Derived",
            "0018,9305" => "Revolution_Time",
            "0018,9306" => "Single_Collimation_Width",
            "0018,9307" => "Total_Collimation_Width",
            "0018,9309" => "Table_Speed",
            "0018,9310" => "Table_Feed_per_Rotation",
            "0018,9311" => "CT_Pitch_Factor",
            "2071,1071" => "Tamar_Misc_String",
            "071,1040"  => "Tamar_Study_Body_Part",
            "0008,0020" => "Study_Date",
            "0008,0050" => "Accession_Number",
            "0008,0070" => "Manufacturer",
            "0008,0090" => "end_of_uidhysician",
            "0008,103e" => "Series_Description",
            "0008,1030" => "Study_Description",
            "0008,1090" => "Manufacturer_Model",
            "0010,0010" => "Patient_Name",
            "0010,0020" => "MRN_Patient_ID",
            "0010,0030" => "Patient_Birthdate",
            "0010,0040" => "Patient_Sex",
            "0010,1010" => "Patient_Age",
            "0018,0010" => "Contrast_Agent",
            "0018,0015" => "Body_Part_Examined",
            "0018,0060" => "kVp",
            "0020,0011" => "Series_Number",
            "0020,0013" => "Image_Number",
            "0020,1208" => "Number_of_Study_Related_Images",
            "0018,9345" => "CTDIvol",
            "0020,0012" => "Acquisition_Number",
            "0018,0050" => "Slice_Thickness",
            "0018,1150" => "Exposure_Time",
            "0018,1151" => "X_ray_Tube_Current",
            "0018,1152" => "Exposure",
            "0018,1210" => "Convolution_Kernel",
            "0018,9311" => "Type",
            "0020,1041" => "Slice_Location",
            "0018,9360" => "CT_Additional_X_Ray_Source_Sequence",
            "0018,9330" => "X_Ray_Tube_Current_in_mA",
            "0020,1002" => "Images_in_Acquisition",
            "0020,1001" => "Acquisition_in_Series",
            "0018,11A0" => "Body_Part_Thickness",
            "0021,1054" => "Image_Position",
            "0021,1055" => "Image_Orientation",
            "0018,9309" => "Table_Speed",
            "07a1,1071" => "NIH_research_protocol_identifier",
            "0018,9310" => "Table_Feed_per_Rotation",
            "0018,9452" => "Calculated_Anatomy_Thickness",
            "0010,1030" => "Patient_Weight",
            "0010,1020" => "Patient_size",
            "0018,0087" => "Magnetic_Field_Strength",
            "0018,0087" => "Magnetic_Field_Strength",
            "0018,115E" => "Image_Area_Dose_Product",
            "0018,1155" => "Radiation_Setting",
            "0018,9324" => "Estimated_Dose_saving",
            "0018,1030" => "Protocol_Name",
            "0018,9311" => "Spiral_Pitch_Factor",
            "0018,9318" => "Reconstruction_Target_patient",
            "0018,9313" => "Data_collection_center_patient",
            "0018,9307" => "Total_collimation_width",
            "0018,9306" => "Single_collimation_width",
            "0018,5100" => "Patient_position",
            "0018,1110" => "Distance_source_to_detector",
            "0018,1111" => "Distnace_source_to_patient",
            "0018,1140" => "Rotation_direction",
            "0018,1170" => "Generator_power",
            "0018,9311" => "Spiral_pitch_factor",
            "0018,1130" => "Table_height",
            "0018,1160" => "Filer_type",
            "0020,000e" => "Series_instance_UID",
            "0018,9311" => "Spiral_pitch_factor",
            "0018,9310" => "Table_feed_per_rotation",
            "0018,9311" => "Spiral_pitch_factor",
            "0020,0013" => "Instance_number",
            "0008,0008" => "Image_type",
            "0040,0244" => "PerformedProcedureStepStartDate",
            "0040,0245" => "PerformedProcedureStepStartTime",
            "0040,0250" => "PerformedProcedureStepEndDate",
            "0040,0251" => "PerformedProcedureStepEndTime",
            "0040,0252" => "PerformedProcedureStepStatus",
            "0040,0253" => "PerformedProcedureStepID",
            "0020,000D" => "Study_instance_iud",
            "0008,0031" => "SeriesTime",
            "0038,0500" => "Patient_State",
            "0018,1100" => "Reconstruction_diameter(FOV)",
            "0018,0090" => "Data_collection_diameter(FOV)",
            "0008,0008" => "SOP_Class_uid",
            "0008,0032" => "Acquisition_time",
            "0018,1130" => "Table_height",
            "07a1,10c0" => "Scanner_type",
            "0009,0010" => "Private_creator",
            "0032,1032" => "Requesting_physician",
            "0020,0012" => "Acquisition_number",
            "0008,0032" => "Acquisition_time",
            "0008,0033" => "Content_time",
            "0008,0022" => "Acquisition_date",
            "0008,0030" => "StudyTime",
            "0008,002a" => "Acquisition_date_time",
            "07a1,1040" => "Another_body_part",
            "0008,3010" => "IrradiationEventUID"
        );

        return %tags;

    }

    print "Ending get_data.\n______________________________\n";


}



sub get_time {

    ( $sec, $min, $hour, $mday, $mon, $year ) = localtime();
    $year += 1900;
    $mon  += 1;
    $time = "$hour:$min:$sec $mon.$mday.$year";
    return $time;
}
    
    
    #Goes through each image of a series and moves all the derived images to a new folder, appended with derived.
sub moveDerived {
    #print "helloworld\n";   
    my $data = shift;                      #Location of Dumped Data from images
   # print "The directory name is $data, while the file in this is called ....\n";
    opendir( DIF, $data ) or die " $! couldn't open $data\n";
     while (my $file = readdir(DIF) ) {
         if($file ne '.' && $file ne '..'){
		open (DER, "<","$data/$file") or die "Problem opening $data/file $!";  #DER is file being checked if it's DERived or not.
                        while (my $line = <DER>){
                            if($line =~ m/0008,0008/g){
                                if ($line =~ m/derived/i) {
                                   # print "Found derived! Twas file $file \n\n";
                                    my $directory = "$data\_derived";
                                     #print "Should be moving from $data to: $directory\n\n";
                                    unless (-e $directory){
                                        print "Making Directory: $directory\n\n";
                                         mkdir $directory; 
                                     }
                                     #Close so it can be moved, and last so the loop doesn't try to read a file that wouldn't be there.
                                     close DER;
                                    mv("$data/$file","$directory/$file") or die "Cannot move $data/$file because $!";
                                    last;
                                }
                            }
                        }
                        close DER;
	}
     }
     close DIF;
}

#The purpose of this subroutine is to filter which series are to be retrieved based on content time, as these say when the images are created and they are the same
#for duplicate images. Because they are for the image level, have to retrieve the first image of each series to access this information. If the content times are the same,
#then it checks the length to make sure that they are comparable in size, and if they are, take the one with fewer images in order to save time when retrieving. Else, take the longer one.
#This subroutine takes in the content times of the first image, the series uids, the number of images, the accession number, and the slice locations of the first image. Modified so that
#it would compare content times of all the series of a specific patient on the same day.
sub checkContentTime{
    my @contentTimes = @{$_[0]};
   # print "content times: @contentTimes\n";
    my @seriesUIDs = @{$_[1]};
    my @numImages = @{$_[2]};
    
    my @sLoc = @{$_[4]};
    my @imageTypes = @{$_[5]};
    my $accNum = $_[3]->[0];
    my $mrn=$_[6];
    my $date=$_[7];
    my $totSeries = $_[8];
    my %notInclude = %{$_[9]};
    my $sLoc1=0;
    my @needToDelete;
    my $value;
    my $length1;
    my $length2;
    my $endContentTime1;
    my $endContentTime2;
    
    #Grabs all series that a patient underwent and occurred on the same day as the current study
    exe_query( "=$mrn", '', "=IMAGE", "=$date", '', "=CT", '', '', '', '',
                                "=CT*",'', '', '', '', '', "=1" );
     my (
                $otherTotalSeries,                 $StudyDate_series_ref,
                $Accession_series_ref,         $Series_times_ref,
                $Modality_series_ref,          $StudyDescription_series_ref,
                $SeriesDescription_series_ref, $PatientName_series_ref,
                $MRN_series_ref,               $SeriesNumber_series_ref,
                $ImagesInSeries_series_ref,    $Birthday_series_ref,
                $series_UIDs_ref,              $contentTime_ref,
                $sLoc_ref,                     $imageTypes_ref 
            ) = get_series_info( $tmp_query_log, "$retrieval" );             
    my @otherTimes = @{$contentTime_ref};
    my @otherNumImages=@{$ImagesInSeries_series_ref};
    my @otherFirstLoc=@{$sLoc_ref};      
    my @otherAccession=@{$Accession_series_ref}; 
    my @otherSeriesUID=@{$series_UIDs_ref};       
    #Bases it on series uid because there are some reconstructions sharing the same uid.
    for (my $i =0; $i<=$#seriesUIDs; $i++){
        $sLoc1=0;
        my $endTime=0;
        #Only look at those that aren't decided to be deleted
        if($notInclude{$accNum}{$seriesUIDs[$i]}){
            $needToDelete[$i] = 1;
        }
        if(!$needToDelete[$i]){
            for(my $j = $i+1; $j<=$#seriesUIDs;$j++){
                if(!$needToDelete[$j]){
                  #  print "The content times are $contentTimes[$i] and $contentTimes[$j]\n";
                   
                    my $sLoc2;
                    #To reduce number of queries, checks to see if it already has performed this query. Otherwise grab ending slice location and time
                    if(!$sLoc1){
                        
                        exe_query( '', '', "=IMAGE", '', '', '', '', '', '', '',
                            "=$accNum",'', "=$seriesUIDs[$i]", '', '', '', "=$numImages[$i]" );
                        open( TMALOG, '<', $tmp_query_log ) or print TMALOG "Can't open $tmp_query_log because $!\n";
                        while ( my $line = <TMALOG> ) {
                            
                            
                            if ( $line =~ m/0020,1041/g ) {    #get slice location 
                                ($value) = $line =~ /\[(.+?)\]/;
                                $sLoc1=$value;                               
                            }   
                            if( $line =~ m/0008,0033/g) {
                                ($value) = $line =~ /\[(.+?)\]/;
                                $endContentTime1 = $value;
                            }
                        }
                        close TMALOG;
                        $length1= abs($sLoc1-$sLoc[$i]);
                    }
                     
                    exe_query( '', '', "=IMAGE", '', '', '', '', '', '', '',
                                "=$accNum", '', "=$seriesUIDs[$j]", '', '', '', "=$numImages[$j]" );
                    open( TMALOG, '<', $tmp_query_log ) or print TMALOG "Can't open $tmp_query_log because $!\n";
                        while ( my $line = <TMALOG> ) {
                                
                                
                            if ( $line =~ m/0020,1041/g ) {    #get slice location 
                                ($value) = $line =~ /\[(.+?)\]/;
                                $sLoc2=$value;
                            
                            }
                            if( $line =~ m/0008,0033/g) {
                                ($value) = $line =~ /\[(.+?)\]/;
                                $endContentTime2 = $value;
                            }   
                        }
                     close TMALOG;
                     $length2 = abs($sLoc2-$sLoc[$j]);
                     print "The locs are $sLoc1 and $sLoc2\n";
                    if($contentTimes[$i]&&$contentTimes[$j]&&(($contentTimes[$i]<=$contentTimes[$j] && ($endContentTime1 >= $endContentTime2)) || ($contentTimes[$i]>=$contentTimes[$j] && ($endContentTime1 <= $endContentTime2)))){
                        #detScore refers to detector score. Dual energy scans come with DET_A B or AB in their image type. It seems that those with AB are higher than those
                        #with A, which are higher than those with B. If the content times are the same and it comes across a dual energy scan, it needs to take into account which 
                        #detector it comes from to get an accurate DLP dose. If this doesn't hold, can just say take all dual energy ones via if det is in the image type, take
                        my $detScore1=0;
                        my $detScore2=0;
                        if($imageTypes[$i]=~ m/DET_AB/g){
                            $detScore1 = 2;
                        }
                        elsif($imageTypes[$i]=~ m/DET_A/g){
                            $detScore1 = 1;
                        }
                        if($imageTypes[$j]=~ m/DET_AB/g){
                            $detScore2 = 2;
                        }
                        elsif($imageTypes[$j]=~ m/DET_A/g){
                            $detScore2 = 1;
                        }
                        
                        if($detScore1 > $detScore2){
                            $needToDelete[$j]=1;
                        }
                        elsif($detScore1<$detScore2){
                            $needToDelete[$i]=1;
                        }
                        else{
                            #If the last image differs in location by less than 12 mm (a little over 2 slices of 5 mm length)
                            if(abs($sLoc1-$sLoc2)<12){
                                if($numImages[$i]<$numImages[$j]){
                                    $needToDelete[$j]=1;
                                    print "Deleting $seriesUIDs[$j] based on number of images because slice loc is close enough\n";
                                    #push($j, @needToDelete);
                                }
                                else {
                                    $needToDelete[$i]=1;
                                     print "Deleting $seriesUIDs[$i] based on number of images because slice loc is close enough\n";
                                    #push($i, @needToDelete);
                                }
                            }
                            else{
                                if($length1>$length2){
                                    $needToDelete[$j]=1;
                                     print "Deleting $seriesUIDs[$j] based on lengths\n";
                                }
                                else {
                                    $needToDelete[$i]=1;
                                     print "Deleting $seriesUIDs[$i] based on lengths\n";
                                    #push($i, @needToDelete);
                                }
                            }
                        }
                    }
                }
            }
            #This checks if there is more than one study. (If only 1 study, the number of series on that day would be equal to the number of studies in that study)
            if($otherTotalSeries != $totSeries){
                #Runs through all of the studies of the patient performed on that day.
                for (my $k=0; $k<=$#otherNumImages;$k++){
                    #Makes sure it's not comparing with itself, and that there is a content time, and that it isn't already being deleted.
                   if($otherAccession[$k] ne $accNum && $contentTimes[$i] && !$needToDelete[$i]){
                            my $sLoc2;
                            
                            my $otherEndTime;
                            #To reduce number of queries, checks to see if it already has gotten the end time.
                            if(!$endTime){
                                
                                exe_query( '', '', "=IMAGE", '', '', '', '', '', '', '',
                                    "=$accNum",'', "=$seriesUIDs[$i]", '', '', '', "=$numImages[$i]" );
                                open( TMALOG, '<', $tmp_query_log ) or print TMALOG "Can't open $tmp_query_log because $!\n";
                                while ( my $line = <TMALOG> ) {
                                    
                                    
                                    if ( $line =~ m/0020,1041/g ) {    #get slice location 
                                        ($value) = $line =~ /\[(.+?)\]/;
                                        $sLoc1=$value;
                                    }
                                    elsif ( $line =~ m/0008,0033/g){
                                        ($endTime) = $line =~ /\[(.+?)\]/;
                                    }   
                                }
                                close TMALOG;
                                $length1= abs($sLoc1-$sLoc[$i]);
                           }
                             
                            exe_query( '', '', "=IMAGE", '', '', '', '', '', '', '',
                                        "=$otherAccession[$k]", '', "=$otherSeriesUID[$k]", '', '', '', "=$otherNumImages[$k]" );
                            open( TMALOG, '<', $tmp_query_log ) or print TMALOG "Can't open $tmp_query_log because $!\n";
                                while ( my $line = <TMALOG> ) {
                                        
                                        
                                    if ( $line =~ m/0020,1041/g ) {    #get slice location 
                                        ($value) = $line =~ /\[(.+?)\]/;
                                        $sLoc2=$value; 
                                    }   
                                    elsif ( $line =~ m/0008,0033/g){
                                        ($otherEndTime) = $line =~ /\[(.+?)\]/;
                                    }  
                                }
                             close TMALOG;
                             $length2 = abs($sLoc2-$otherFirstLoc[$k]);
                             print "The locs are $sLoc1 and $sLoc2. The time of the first is $contentTimes[$i] and $endTime. The time of the second is $otherTimes[$k] and $otherEndTime.\n";                       
                            #Currently, testing this method out, so, for simplicity, only going to be deleting the series of the study that is currently being examined overall. So
                            #Only checks if it is equal or within length. If the same length, then just take the series with smaller accession number because need a unique way to ensure that one and only one 
                            #exam is being removed.
                            if ($contentTimes[$i]&&$otherTimes[$k]&& (($contentTimes[$i]>=$otherTimes[$k]&&$endTime<=$otherEndTime))){
                            #If the last image differs in location by less than 12 mm (a little over 2 slices of 5 mm length)
                            #This section is for when the studies are of same length (the 12 is in case there is a difference in slice thickness). Wonder what is best way to choose which study stays.
                                if(abs($length1-$length2)<12){
                                    if($numImages[$i]>$otherNumImages[$k]){
                                        $needToDelete[$i]=1;
                                        print "Deleting $seriesUIDs[$i] based on number of images because slice loc is close enough, compared with study $otherAccession[$k]\n";
                                        
                                    }
                                    elsif($numImages[$i]<$otherNumImages[$k]){
                                        $notInclude{$accNum}{$otherSeriesUID[$k]}=1;
                                        print "Adding $otherSeriesUID[$k] to hash so that it will be deleted due to image number.";
                                    }
                                    elsif($numImages[$i] == $otherNumImages[$k] && $accNum gt $otherAccession[$k]) {
                                        $needToDelete[$i]=1;
                                         print "Deleting $seriesUIDs[$i] based on accession because slice loc is close enough and image numebrs are equal, compared with study $otherAccession[$k]\n";                                    
                                    }
                                    else{
                                        $notInclude{$accNum}{$otherSeriesUID[$k]}=1;
                                        print "Adding $otherSeriesUID[$k] to hash so that it will be deleted based on accession because everything else is equal.";
                                    }
                                }
                                else{
                                    
                                        $needToDelete[$i]=1;
                                         print "Deleting $seriesUIDs[$i] based on lengths, compared with study $otherAccession[$k]\n";
                                        #push($i, @needToDelete);
                                    
                                }
                         }
                         #Don't need to include if they are about the same length becasue that should have been taken care of in the previous block.
                         elsif($contentTimes[$i]&&$otherTimes[$k] && (($otherTimes[$k]>=$contentTimes[$i]&& $otherEndTime <= $endTime))){
                             $notInclude{$otherAccession[$k]}{$otherSeriesUID[$k]}=1;
                             print "Adding $otherSeriesUID[$k] to hash so that it will be deleted.";
                         }   
                  }      
                }
            }
        }
    }
    
   
    
    return \@needToDelete,\%notInclude;
}  

sub genReport{
    
    #Setting up variables for the graph. data is the table representation, acc is the accessions, obs is the observed DLP, pred are the predicted DLPS, res are the residuals

    my $start = shift;
    my $end = shift;
    my $numPatients = shift;
    my $numExams = shift;
    my @missingExams = @_;
    
    my $height = 792;
    my $width = 612;
    my @data;
    my @acc;
    my @obs;
    my @age;
    my @gender;
    my @prot;
    my @scanner;
    my @predicted;
    my @sbv;
    my @doses;
    
   #Separates the reports into two types: those for a group of exams, and those for just a specified one.
    if($run_specific_exam != 1){
        open(OUTL,"<","$prog_path/outliers.csv");

        #Makes the days into an easily readable format on the report.
        
        my $startYear = substr($start,0,4);
        my $startMonth = substr($start,4,2);
        my $startDay = substr($start, 6,2);
        my $startRecord = "$startMonth/$startDay/$startYear";
        
        my $endYear = substr($end,0,4);
        my $endMonth = substr($end,4,2);
        my $endDay = substr($end, 6,2);
        my $endRecord = "$endMonth/$endDay/$endYear";

        #Goes through the outliers file and records the corresponding values

        while (<OUTL>){
            my $line = $_;
                if($secureOn){
                    chomp $line;
                    $line = decode($encoding,$line);
                }
                my @values = split(',',$line);
                
                if(!($reportPeds)||$reportPeds==$values[5]){
                    if(!($reportProtocol)||$reportProtocol eq $values[1]){
                        if($values[18]>=$start && $values[18] <= $end){
                            push(@acc, $values[0]);
                            push(@obs,nearest(.1,$values[9]));
                            push(@age,$values[3]);
                            push(@gender, $values[2]);
                            push(@prot, $values[1]);
                            push(@scanner, $values[16]);
                            push (@predicted, nearest(.1, $values[10]));
                            push(@sbv, $values[6]);
                            my $estDose = &calcEstDose($values[1], nearest(.1,$values[9]), $values[3],"late");
                            push(@doses, nearest(.1,$estDose));
                        }
                    }
                }
        }

        #adds a header

        $data[0][0] = "Accession Number";
        $data[0][1] = "Protocol";
        $data[0][2] = "DLP";
        $data[0][3] = "Gender";
        $data[0][4] = "Age";
        $data[0][5] = "Scanner";
        $data[0][6] = "Est Dose";
        
        
        #Transfers the data to an array, that will be used for the table
        
        for my $i (1..($#acc+1)){
                
                $data[$i][0]=$acc[$i-1];
                $data[$i][1]=$prot[$i-1];
                $data[$i][2]=$obs[$i-1];
                $data[$i][3]=$gender[$i-1];
                $data[$i][4]=$age[$i-1];
                $data[$i][5]=$scanner[$i-1];
                $data[$i][6]=$doses[$i-1];
        }

        my $data = \@data;

        


        #Setting up the figures by name, as well as setting date (can be grabbed ifin the other prog)

        print "\nMaking Report...\n";
        
        #If only one day is used, no need for the dash
        
        my $date;
        if($figureDaily || $start == $end){
            $date = $startRecord;
        }
        else{
            $date = "$startRecord - $endRecord";
        }
        
        #Paths for the images.
        
        my $figure1 = "$prog_path/Scatterplot.jpg";
        my $figure2 = "$prog_path/Histogram.jpg";
        my $figure3 = "$prog_path/BoxPlotByAge.jpg";
        my $figure4 = "$prog_path/PieOutlierAge.jpg";

        
        my $numOutliers= scalar @acc;

        my $paragraph;
           
        #The short paragraph on the first page, with a couple of things to ensure that proper grammar is used
        
        my $verb = "were";
        my $plural = "s";
        if ($numOutliers ==1){
            $verb = "was";
            $plural = "";
        }
        my $ending ="";
        if($reportProtocol){
            $ending.= " for $reportProtocol";
        }
        if($reportPeds){
            $ending .= " for Peds Patients";
        }
        if($figureDaily || $start==$end){
            $paragraph = "On this day, there were $numPatients patients. From these patients, there have been a total of $numExams different CT scan studies. 
    Of these, there $verb $numOutliers high outlier$plural.";
        }
        else{
        $paragraph = "On these days, there were $numPatients patients. From these patients, there have been a total of $numExams different CT scan studies. 
    Of these, there $verb $numOutliers high outlier$plural.";
        }

        #Creates a new PDF, and adds the Title

        my $pdf = PDF::API2->new();
        my $page = $pdf -> page();
        $page->mediabox('Letter');
        my $font = $pdf ->corefont('Helvetica-Bold');
        my $text = $page->text();
        $text-> font($font, 20);
        $text->translate(50,700);
        $text->text("RE3 Radiation Dose Report for $date");
        $text->lead(23);
        $text->nl;
        $text->text($ending);
        
        $font = $pdf ->corefont('TimesNewRoman');
        $text->font($font, 15);
        $text->translate(50,655);



        #adds the paragraph

        my $txt = $page->text;
        $txt->textstart;
        $txt->font($font, 15);
        $txt->translate(50,655);
        $txt->paragraph($paragraph,500);

        #Creates the table, whose data was created at the start of this

        my $outTable = PDF::Table->new();
        $outTable->table($pdf,$page,$data,
        x=>75, w=> 460, start_y => 600, next_y => 700,
        start_h => 500, next_h => 600, padding=> 5);

    #Goes through the exams, looking for the series that are part of the outliers studies, and creates an info page for each

        open(SERIES, "<",$one_to_one_series);

        for my $i (0..$#acc){
           
            my $hasSeen =0;
            my $acc = $acc[$i];
            my $MRN;
            my $name;
            my $gender;
            my $date;
            my $age;
            my $manu;
            my $scanner;
            my $totCTDI=0;
            my $totDLP=0;
            my $totMas=0;
            
            # my $studyDesc;
            
            my @seriesNumber;
            my @protName;
            my @kvp;
            my @ctdi;
            my @dlp;
            my @estDose;
            my @scanLength;
            my @newTab;
            my @exposures;
            
            #Labels for the table
            
            $newTab[0][0] = "Series #";
            $newTab[0][1] = "Series Name";
            $newTab[0][2] = "kvp";
            $newTab[0][3] = "CTDIvol";
            $newTab[0][4] = "DLP";
            $newTab[0][5] = "Est Dose";
            $newTab[0][7] = "Scan Length";
            $newTab[0][6] = "Avg. mAs";
            
            $page = $pdf->page;
            
            my $txt = $page->text;
            $txt->font($font, 15);
            $txt->translate(100, 725);
            $txt->lead(23);
            
            #actually goes through the file and gets the series
            
            while(<SERIES>){
                my @values = split(',',$_);
                 if($hasSeen && $values[1] ne $acc){
                        
                        seek(SERIES, -length($_)-1, 1);
                        last;
                  }
                if($values[1] eq $acc){
                    $hasSeen=1;
                    $MRN = $values[0];
                    $name = $values[41];
                    $gender = $values[42];
                    $date = $values[24];
                    $age = $values[17];
                    $manu = $values[7];
                    $scanner = $values[6];
                    # $studyDesc = $values[40];
                    push(@seriesNumber, $values[4]);
                    push(@protName, $values[8]);
                    push(@kvp, $values[14]);
                    push(@ctdi, $values[9]);
                    $totCTDI = $totCTDI + $values[9];
                    push(@dlp, $values[10]);
                    $totDLP = $totDLP + $values[10];
                   
                    my $estSeriesDose = &calcEstDose($prot[$i], $values[10], $age,"late");
                    push(@estDose, $estSeriesDose);
                    $totMas = $totMas + $values[19];
                    push(@scanLength, $values[15]);
                    push (@exposures, $values[19]);
                    
                }
                
            }
            my @splitName = split('\^', $name);
            
            #Gets al lthe data into the table
            
            $name =join(' ', @splitName);
            my $year = substr($date,0,4);
            my $month = substr($date,4,2);
            my $day = substr($date, 6,2);
            my $fullDate = "$month/$day/$year";
            for my $i(0..$#kvp){
                $newTab[$i+1][0]=$seriesNumber[$i];
                $newTab[$i+1][1]=$protName[$i];
                $newTab[$i+1][2]=$kvp[$i];
                $newTab[$i+1][3]=nearest(.1,$ctdi[$i]);
                $newTab[$i+1][4]=nearest(.1,$dlp[$i]);
                $newTab[$i+1][5]=nearest(.1,$estDose[$i]);
                $newTab[$i+1][6]=nearest(.1,$exposures[$i]);
                $newTab[$i+1][7]=$scanLength[$i];
            }
            
            my $lastInd = scalar @kvp + 1;
            my $roundDLP = nearest(.1,$totDLP);
            my $roundCTDI = nearest(.1,$totCTDI);
            my $roundExp = nearest(.1,$totMas);
            $txt->text("Name: $name", 700);
            $txt->nl;
            $txt->text("MRN: $MRN     Age: $age      Gender: $gender");
            $txt->nl;
            $txt->text("Accession Number: $acc");
            $txt->nl;
            $txt->text("Study Date: $fullDate    Protocol: $prot[$i]");
            $txt->nl;
            $txt->text("Scanner: $scanner    Manufacturer: $manu");
            $txt->nl;
             $txt->nl;
            $txt->text("Total DLP: $roundDLP, Expected DLP: $predicted[$i]");
            $txt->nl;
            my $predDose = nearest(.1,&calcEstDose($prot[$i],$predicted[$i],$age,"late"));
            $txt->text("Estimated Dose: $doses[$i] Predicted Dose: $predDose");
            $txt->nl;
            $txt->text("Total CTDI: $roundCTDI Total Exposure: $roundExp");
            
            if($sbv[$i] =~ m/No/g || $sbv[$i] == 0){
                $txt->nl;
                $txt->text("SBV/Dw was $sbv[$i]; needs to be recalculated or too many images");
            }
            
            if(!(-e "$ModelDirectory/RegressionFeatures$prot[$i].csv")){
                
                $txt->nl;
                $txt->text("Used default model (None for this study when calculated).");
            }
            
            
            my $newTab = \@newTab;
            my $outTable = PDF::Table->new();
            $outTable->table($pdf,$page,$newTab,
            x=>75, w=> 500, start_y => 500, next_y => 700,
            start_h => 500, next_h => 600, padding=> 5);
        }
        
        
        close SERIES;
        
        #Creating the images from the files

        my $image1 = $pdf->image_jpeg($figure1);
        my $image2 = $pdf->image_jpeg($figure2);
        my $image3 = $pdf->image_jpeg($figure3);
        my $image4 = $pdf->image_jpeg($figure4);
        #my $image5 = $pdf->image_jpeg($figure5);


        #adds the figures to the page

        $page = $pdf -> page;
        addFigures($page,$image1, $image2);
        $page = $pdf -> page;
        addFigures($page, $image3, $image4);
        

        my @descToInclude = uniq @prot;

        #Goes through the figures directory, looking for all jpgs to create figures from. If an odd number, just leave the first array longer

        @descToInclude = sort @descToInclude;

        opendir(DIR,"$prog_path/Figures");
        my $count=1;
        my @figs1;
        my @figs2;
        while (readdir(DIR)){
            for my $checkDesc (@descToInclude){
               # if( $_ =~ m/$checkDesc.jpg/){
                 if( $_ =~ m/$checkDesc.png/){   
                        if($count==1){
                                push (@figs1, $_);
                                $count =2;
                        }
                        elsif($count==2){
                                push(@figs2, $_);
                                $count=1;
                        }
                }
            }
        }

        #Goes through the arrays and sends both images to be made into figure, otherwise just send the one
        
        for my $i(0..$#figs1){
                $page = $pdf -> page;
                if($figs2[$i]){
                        my $imgA = $pdf->image_png("$prog_path/figures/$figs2[$i]");
                        my $imgB = $pdf->image_png("$prog_path/figures/$figs1[$i]");
                        addFigures($page, $imgA, $imgB,$descToInclude[($i*2+1)],$descToInclude[($i*2)], $pdf);
                }
                else{
                        #my $imgA = $pdf->image_jpeg("$prog_path/figures/$figs1[$i]");
                        my $imgA = $pdf->image_png("$prog_path/figures/$figs1[$i]");
                        addFigures($page, $imgA,"",$descToInclude[($i*2)],"", $pdf);
                }
               

        }
        
        if($missingExams[0]){
            $page = $pdf->page;
            $page->mediabox('Letter');
            my $txt = $page->text;
            $txt->font($font, 15);
            $txt->translate(90, 700);
            my $leading = $txt->lead(23);
            $txt->text("The following exams are some of those that are missing series on the PACS: ");
            $txt->nl;
            $txt->text("(They are part of a low dose protocol that have two scans)");
            $txt->nl;
            for(@missingExams){
                $txt->nl;              
                $txt->text($_);
                my ($w, $h) = $txt->textpos();
                if($h<75 && $w <350){
                    $txt->translate($w+50,700-$leading*2);
                }
                elsif($h<75 && $w>350){
                    $page = $pdf->page;
                    $txt = $page->text;
                    $txt->font($font, 15);
                    $txt->lead(23);
                    $txt -> translate(90,700);
                }
            }
        }
        

        #Saves the pdf depending on whether it's a single day or not.
       
        if($start==$end){
            $pdf->saveas("$report_path/DailyReport$start.pdf");
        }
        else{
            $pdf->saveas("$report_path/WeeklyReport$start-$end.pdf");
        }
    }
    else{
        #Creates a report if only for one exam.
        my $ending ="";
        if($reportProtocol){
            $ending.= " for $reportProtocol";
        }
        if($reportPeds){
            $ending .= " for Peds Patients";
        }
         my $pdf = PDF::API2->new();
        my $page = $pdf -> page();
        $page->mediabox('Letter');
        my $font = $pdf ->corefont('Helvetica-Bold');
        my $text = $page->text();
        $text-> font($font, 20);
        $text->translate(50,750);
        $text->text("RE3 Radiation Dose Report for $specific_accession");
        $text->lead(23);
        $text->nl;
        $text->text($ending);
        
        $font = $pdf ->corefont('TimesNewRoman');
        $text->font($font, 15);
        $text->translate(50,655);
        my $acc = $specific_accession;
        open(STUDY, "<", $one_to_one_study);
        my $sbv;
        my $dw;
        my $prot;
        my $predicted;
        my $outlier;
        my $seen=0;
        my $hasSeen = 0;
        while(<STUDY>){
            my @values = split(',',$_);
            if($values[0] ne $acc && $hasSeen){
                last;
            }
            elsif($values[0] eq $acc){
                $hasSeen =1;
                $sbv = nearest(.1,$values[6]);
                $dw = nearest(.1,$values[7]);
                $prot = $values[1];
                $predicted = nearest(.1,$values[10]);
                $outlier=$values[19];
            }
        }
        close STUDY;

    #Goes through the exams, looking for the series that are part of the outliers studies, and creates an info page for each

        open(SERIES, "<",$one_to_one_series);

        
           
            $hasSeen =0;
            
            my $MRN;
            my $name;
            my $gender;
            my $date;
            my $age;
            my $manu;
            my $scanner;
            my $totCTDI=0;
            my $totDLP=0;
            my $totMas=0;
            
            # my $studyDesc;
            
            my @seriesNumber;
            my @protName;
            my @kvp;
            my @ctdi;
            my @dlp;
            my @estDose;
            my @scanLength;
            my @newTab;
            my @exposures;
            
            #Labels for the table
            
            $newTab[0][0] = "Series #";
            $newTab[0][1] = "Series Name";
            $newTab[0][2] = "kvp";
            $newTab[0][3] = "CTDIvol";
            $newTab[0][4] = "DLP";
            $newTab[0][5] = "Est Dose";
            $newTab[0][7] = "Scan Length";
            $newTab[0][6] = "Avg. mAs";
            
        
            
            my $txt = $page->text;
            $txt->font($font, 15);
            $txt->translate(100, 725);
            $txt->lead(23);
            
            #actually goes through the file and gets the series
            
            while(<SERIES>){
                my $line = $_;
                if($secureOn){
                    chomp $line;
                    $line = decode($encoding,$line);
                }
                my @values = split(',',$line);
                 if($hasSeen && $values[1] ne $acc){
                        
                        # seek(SERIES, -length($_)-1, 1);
                        last;
                  }
                if($values[1] eq $acc){
                    $hasSeen=1;
                    $MRN = $values[0];
                    $name = $values[41];
                    $gender = $values[42];
                    $date = $values[24];
                    $age = $values[17];
                    $manu = $values[7];
                    $scanner = $values[6];
                    # $studyDesc = $values[40];
                    push(@seriesNumber, $values[4]);
                    push(@protName, $values[8]);
                    push(@kvp, $values[14]);
                    push(@ctdi, $values[9]);
                    $totCTDI = $totCTDI + $values[9];
                    push(@dlp, $values[10]);
                    $totDLP = $totDLP + $values[10];
                    my $estSeriesDose = &calcEstDose($prot,$values[10],$age,"late");
                    push(@estDose, $estSeriesDose);
                    $totMas = $totMas + $values[19];
                    push(@scanLength, $values[15]);
                    push (@exposures, $values[19]);
                    
                }
                
            }
            close SERIES;
            my @splitName = split('\^', $name);
            
            #Gets al lthe data into the table
            
            $name =join(' ', @splitName);
            my $year = substr($date,0,4);
            my $month = substr($date,4,2);
            my $day = substr($date, 6,2);
            my $fullDate = "$month/$day/$year";
            for my $i(0..$#kvp){
                $newTab[$i+1][0]=$seriesNumber[$i];
                $newTab[$i+1][1]=$protName[$i];
                $newTab[$i+1][2]=$kvp[$i];
                $newTab[$i+1][3]=nearest(.1,$ctdi[$i]);
                $newTab[$i+1][4]=nearest(.1,$dlp[$i]);
                $newTab[$i+1][5]=nearest(.1,$estDose[$i]);
                $newTab[$i+1][6]=nearest(.1,$exposures[$i]);
                $newTab[$i+1][7]=$scanLength[$i];
            }
            
            my $lastInd = scalar @kvp + 1;
            my $roundDLP = nearest(.1,$totDLP);
            my $roundCTDI = nearest(.1,$totCTDI);
            my $roundExp = nearest(.1,$totMas);
            $txt->text("Name: $name", 700);
            $txt->nl;
            $txt->text("MRN: $MRN     Age: $age      Gender: $gender");
            $txt->nl;
            $txt->text("Accession Number: $acc");
            $txt->nl;
            $txt->text("Study Date: $fullDate    Protocol: $prot");
            $txt->nl;
            $txt->text("Scanner: $scanner    Manufacturer: $manu");
            $txt->nl;
             $txt->nl;
            $txt->text("Total DLP: $roundDLP, Expected DLP: $predicted");
            $txt->nl;
            my $estDose = nearest(.1,&calcEstDose($prot, $roundDLP, $age,"late"));
            my $expDose = nearest(.1,&calcEstDose($prot, $predicted, $age,"late"));
            $txt->text("Estimated Dose: $estDose Expected Dose: $expDose");
            $txt->nl;
            $txt->text("Total CTDI: $roundCTDI Total Exposure: $roundExp");
            
            my $status=" is not";
            if($outlier){
                $status = " is";
            }
            $txt->nl;
            $txt->text("This$status an outlier");
            
            if($sbv =~ m/No/g || $sbv == 0){
                $txt->nl;
                $txt->text("SBV/Dw was $sbv; needs to be recalculated or too many images");
            }
            
            if(!(-e "$ModelDirectory/RegressionFeatures$prot.csv")){
                
                $txt->nl;
                $txt->text("Used default model (None for this study yet).");
            }
            
            
            my $newTab = \@newTab;
            my $outTable = PDF::Table->new();
            $outTable->table($pdf,$page,$newTab,
            x=>75, w=> 500, start_y => 480, next_y => 700,
            start_h => 500, next_h => 600, padding=> 5);
        
        
        
        close SERIES;
         $pdf->saveas("$report_path/ReportFor$acc.pdf");
    }

    print "The report has been created\n";
}

sub addFigures{
	my $page = $_[0];
	my $img = $_[1];
	my $title = $_[3];
	my $img2;
	my $title2;
	my $onePic=0;
	my $pdf = $_[5];
	
	
	
	#Checks to see if there was two or one images sent, if only one note that, but if two, store it.
	
	if($_[2]){
		$img2 = $_[2];
		$title2 = $_[4];
	}
	else{
		$onePic = 1;
	}
	
	#Sets up and adds the image(s) to the page
	
	$page -> mediabox('Letter');
	
	
        
	my $gfx = $page -> gfx;
	$gfx-> scale(.75,.75);
	
	#Different locations depending on the number of images
	
	if($onePic){
		$gfx ->image($img, 100, 600);
	}
	else{
		$gfx ->image($img, 100,100);
		$gfx ->image($img2, 100, $img->height+200);
	}
	
	#If the pdf is sent along, means that a label needs to be added to it. Also, depends on whether one or two images is being added.
	
	if($_[2] && $_[5]){
	     my $text = $page->text;
            
             my $font = $pdf ->corefont('Helvetica-Bold');
            $text-> font($font, 20);
            $text->translate(150,$img2->height + 590);
            $text->text("DLP Model for $title2");  
            
            $text = $page->text;
            $font = $pdf ->corefont('Helvetica-Bold');
            $text-> font($font, 20);
            $text->translate(150,$img->height + 125);
            $text->text("DLP Model for $title");
                      
        }
        elsif ($_[5]){
            my $text = $page->text;
            my $font = $pdf ->corefont('Helvetica-Bold');
            $text-> font($font, 20);
            $text->translate(150,$img->height + 610);
            $text->text("DLP Model for $title");  
        }

}

#Uses k-factors from a file, study description, and the DLP to calculate an estimated dose
sub calcEstDose{
    my $studyDesc = shift;
    my $dlp = shift;
    my $age = shift;
    my $body_part = shift;
    my $ageIndex;
    if ($age >=15){
        $ageIndex = 0;
    }
    elsif ($age<15 && $age >=10){
        $ageIndex =1;
    }
    elsif ($age<10 && $age >=5){
        $ageIndex =2;
    }
    elsif ($age<5 && $age >=1){
        $ageIndex =3;
    }
    elsif ($age<1){
        $ageIndex =4;
    }
    #elsif($age>10&&$age<=15)
    my $estDose;
    my @bodyParts = keys %kfactorBody;
    for(@bodyParts){
        if($body_part =~ m/$_/g){
            $estDose = $dlp*$kfactorBody{$_}->[$ageIndex];
            last;
        }
    }
    
   if (!$estDose){
       my @studyDescs = keys %kfactorStudy;
       for(@studyDescs){
            if($studyDesc =~ m/$_/g){
                $estDose = $dlp*$kfactorStudy{$studyDesc}->[$ageIndex];
                last;
            }
        }
    }
    if(!$estDose){
        $estDose= $dlp * $kfactorBody{"default"}->[$ageIndex];
       }
    
   # print "Keys: ", keys %kfactors, "weird\n";
    return $estDose;
    
}
#Creates the hash correlating the k factors based on study description, if body part not there.
sub setUpStudyKfactor{
    open(KF, "<", $kfactorFile);
    my %kfactor;
    for(<KF>){
        my @values = split(',',$_);
       
        my $desc = shift(@values);
        $kfactor{$desc} = \@values;
        
    }
    close KF;   
    return %kfactor;
}

sub setUpBodyKfactor{
    open(KF, "<", $kfactorBodyFile);
    my %kfactor;
    for(<KF>){
        my @values = split(',',$_);
        my $body = shift(@values);
        $kfactor{$body} = \@values;
    }
    close KF;
    return %kfactor;
}

sub checkFirstTwenty{
    my $acc = $_[0];
    my $study = $_[1];
    open(CT,"<", "$ModelDirectory/RegressionModelData$study.csv");
    #20 bsaed on minimum number of studies needed for a model
    for(0..19){
        my $check = <CT>;
        my @values = split(',',$check);
        if($values[0] eq $acc){
            return 1;
        }
    }
    return 0;
}

sub getStructuredReport{
    
    my $series;
    my $dosePresent=0;
    my $fileSR="";
    my $seriesUID =0;
    my $acc = $_[1];
    my $tmp_image_path=$_[2];
    my $dumped_data=$_[3];
    
    exe_query( '', '', $_[0], '', '', '', '', '', '', '',
                "=$acc", '', '', '', '', '', "=1", "=SR");
    open( TMALOG, '<', $tmp_query_log ) or print QRLOG "Can't open $_[0] because $!\n";
    my $notSkip = 1;
    my $seriesNumber;
    while ( my $line = <TMALOG> ) {
        
        #If the image type is derived, then it doesn't need to read the lines following this until it hits a new series. This is made possible because image type is the first
        #information provided by findscu when giving info about a series.
        if ( $line =~ m/0008,0016/g ) {    #get SOP Class
            
            if ($line =~ m/XRayRadiationDose/g){
                
               $dosePresent =1;
                $notSkip =1;
            }
            else {
                
                $notSkip =0;
            }
            
        }
        if($notSkip){
            if ( $line =~ m/0020,000e/g ) {    #series uid
                ($value) = $line =~ /\[(.+?)\]/;
                $seriesUID = $value;
            }
            if ( $line =~ m/0020,0011/g){       #Series number
                ($value) = $line =~ /\[(.+?)\]/;
                $seriesNumber = $value;
            }
        }
    }
    
    if($dosePresent){
          
        $acc =~ s/\s*//g;
        $acc =~ s/"//g;

#identify by series UID instead of series number, since sometimes there are two series under the same series number in dual energy scans
        my $end_of_uid = substr( $seriesUID, -8 );
        

        #make directories for the series
        my $tmp_image_path =
            "$tmp_image_path\\$end_of_uid";
        my $dumped_data =
            "$dumped_data\\$end_of_uid";

        #make the next folders in these directory trees
        unless ( -e $tmp_image_path ) {
            mkdir($tmp_image_path);
            print "\tMade $tmp_image_path\n";
        }
        unless ( -e $dumped_data ) {
            mkdir($dumped_data);
            print "\tMade $dumped_data\n";
        }                       
                        
        #retrieve images
        exe_retrieve(
            '',
            "=SERIES",
            "=$acc",
            '',
            '',
            '',
            '',
            "=$seriesUID",
            '',
            $tmp_image_path,
            '',
            '',
            '',
            '',
            ''
        );

#open each directory containing the images, dump header data into corresponding dumped_data directory, then delete original images (they take up a lot of space!)
        print
            "\tQuery finished. Downloaded the files to $tmp_image_path\n";
        chomp($tmp_image_path);

        #print "Chomped path is $tmp_image_path\n";
        $tmp_image_path =~ s/\s*//g;

        #print "Unspaced path is $tmp_image_path\n";
        # }

      opendir( DIR, $tmp_image_path )
          or die " $! couldn't open $tmp_image_path\n";
      
        #dump a file
        while ( $file = readdir(DIR) ) {

            #print "Dumping for $tmp_image_path\\$file\n\n";

            $cmd_dmp = "$dump_path $tmp_image_path\\$file";
           
#print "Dumping from $tmp_image_path to $dumped_data\\$file.txt\nHence, root is $dumped_data\n";
            system "$cmd_dmp >$dumped_data\\$file.txt";
            
            if($file ne '.' && $file ne '..'){
                $fileSR = "$dumped_data\\$file.txt";
            }

  #commented out this unlink so body volume CAD could work on it
            unlink "$tmp_image_path\\$file";
        }
    }
    print "Structured Report: $fileSR \n";
    
     return ($dosePresent,$fileSR);
     
}

sub getSRDose{
    my $irradiationUID = $_[0];
    
    my $SRfile = $_[1];
     
    my $value;
    my $ctdivol=0;
    my $dlp=0;
    my $needLeave=0;
    open(SR, "<", $SRfile);
    while(my $line = <SR>){
        if($needLeave){
            last;
        }
        if ( $line =~ m/Irradiation Event UID/g ) {    #get birthday
                #($value) = $line =~ /\[(.+?)\]/;
                
                while(my $lineA = <SR>){
                     my $waitCTDIvol = 0;
                     my $waitDLP=0;
                    if($needLeave){
                        last;
                    }
                    if ($lineA =~ m/0040,a124/){
                       
                        ($value) = $lineA =~ /\[(.+?)\]/;
                        
                        if($value eq $irradiationUID){
                           
                            while(my $lineB = <SR>){
                               
                                
                                #print "lines within is $lineB\n";
                                if($lineB =~ m/CTDIvol/){
                                    
                                    $waitCTDIvol = 1;
                                }
                                
                                if($waitCTDIvol && ($lineB =~ m/0040,a30a/)){
                                    
                                    ($value) = $lineB =~ /\[(.+?)\]/;
                                    $ctdivol = $value;
                                   # print "CTDIvol is $value and $ctdivol\n";
                                    $waitCTDIvol = 0;
                                }
                                if($lineB =~ m/DLP/){
                                     
                                    $waitDLP = 1;
                                }
                                if($waitDLP && $lineB =~ m/0040,a30a/){
                                    
                                    ($value) = $lineB =~ /\[(.+?)\]/;
                                    $waitDLP=0;
                                    $dlp = $value;
                                    $needLeave =1;
                                }
                                if($needLeave){
                                    last;
                                }
                                
                            }
                        }
                        else{last;}
                    }
                }
        }
        
    }
    print "DLP from SR: $dlp CTDI: $ctdivol \n";
    
    return($dlp, $ctdivol);
}