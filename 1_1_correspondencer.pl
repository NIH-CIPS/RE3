#This perl script goes through the log containing all of the information about the series of a study
#It identifies which series are duplicates, removes them, and organizes the rest of the data into two
#results files, one for series level info (one-to-one_series) and the other for study level info (one-to-one_study)
#It also can take the data for slice level info, and put that in its own file
#Author: SJW (samweisenthal@gmail.com) Updated by: WCK (william.kovacs@nih.gov)

use Data::Dumper;
use List::MoreUtils qw/ uniq /;
use XML::Simple;
use DetectOutliers;
use List::Util qw( min max );
use Encode;
use strict;
use warnings;

#my $datafile = $ARGV[0];
######
#to use separately, uncomment datafile below (udner config information), comment datafile above

my $date_identifier = $ARGV[1];
my $config_file =$ARGV[2];
my $updateData =$ARGV[3];
print "UPDATE DATA VALUE IS SET AS: $updateData\n";
my $calc_results_slice;

my $config   = new XML::Simple->XMLin($config_file);
my $prog_path= $config->{program_path};
my $slice_data = $config->{slice_data};
my $encoding = $config->{encoding};
my $secureOn = $config->{secureOn};

my $datafile = "$prog_path/calcresultsLog.csv";

my $one_to_one_slice;
my $one_to_one_slice_daily;
my @SliceData;
my @SlicestoShift;

#Sets up the data files, including separate ones if the information is to be encrypted
if($slice_data == 1){
    $calc_results_slice = $ARGV[4];
    open(SLDA, "<$calc_results_slice") or die "Cannot open $calc_results_slice: $!\n";
    @SliceData = <SLDA>;
    close SLDA;
    if(!$secureOn){
        $one_to_one_slice = "$prog_path/one-to-one_slice.csv";
        $one_to_one_slice_daily = "$prog_path/one-to-one_slice.$date_identifier.csv";
    }else{
        $one_to_one_slice = "$prog_path/one-to-one_slice_encrypt.csv";
        $one_to_one_slice_daily = "$prog_path/one-to-one_slice_encrypt.$date_identifier.csv";
    }
    
}


open (DATA,"<$datafile" ) or die "Couldn't open $datafile $!\n";
my $one_to_one_series;
my $one_to_one_study;
if(!$secureOn){
    $one_to_one_series = "$prog_path/one-to-one_series.csv";
    $one_to_one_study = "$prog_path/one-to-one_study.csv";
}
else{
    $one_to_one_series = "$prog_path/one-to-one_series_encrypt.csv";
    $one_to_one_study = "$prog_path/one-to-one_study_encrypt.csv";
}

my $last_accession= 'abc'; 
print "Last accession is set to '$last_accession',so...\n";
my $Acquisition_number;
my $last_Acquisition_number = '';
my @grouped_series;
my @big_DLP_diff;
my @missing_tags;
my @missing_times;
my @missing_series_no;
my @missing_scanlength;
my @missing_ctdi;
my @missing_DLP;
my @fields;
my @accession_counter;
my @mrn_counter;
my @weird_acq;
my $predictedValue;
my $residualValue;
my $outlierFlag;
my $DLPdifferenceFlag;

#Skip the first line, which is just the header
<DATA>;
#For everything else...
while (<DATA>) {
    
    #If the information is already encrypted, need to be able to read it so it can separate by commas.
    if($secureOn){
        chomp $_;
        $_ = decode($encoding,$_);
    }
    print "Data: $_\n";

        my ($MRN, 
            $accession, 
            $other_data) = split ',',$_,3;
              push(@accession_counter,$accession);
              push(@mrn_counter,$MRN);
       
       #abc is the code for the first line, so avoids processing empty data. Then, if the accessions are different, 
       #all the series for the previous accession is collected in grouped_series, so can process that information.
       if($last_accession ne 'abc'){
            if( $accession ne $last_accession){
               print "\n\n";                     
               print "'$accession' != '$last_accession'\n";               
               process_data(@grouped_series);              
               @grouped_series = ();
                      
               }
       }else{
           
           print "\t\t\tSkipped first line.\n";
           
       }
          
       push @grouped_series, $_;

       $last_accession = $accession;
       $last_Acquisition_number = $Acquisition_number;
      
}
close DATA;
@big_DLP_diff = uniq @big_DLP_diff;
@missing_tags = uniq @missing_tags;
@missing_times = uniq @missing_times;
@missing_series_no = uniq @missing_series_no;
@missing_scanlength = uniq @missing_scanlength;
@missing_ctdi = uniq @missing_ctdi;
@missing_DLP = uniq @missing_DLP;
@weird_acq = uniq @weird_acq;

print "\n";
print "Have now kept only one series per pass (separated 'recons' from 'acquisitions')\n";
print "\nPossible issues:\n";
print "DLP difference problems (two series with same acq and very different DLP--will keep both, but it's likely that one is a recon. That recon MUST be manually removed, should that be the case):\n @big_DLP_diff\n";
print "Missing times (missing a start or end time)):\n @missing_times\n";
print "Missing series_no:\n @missing_series_no\n";
print "Missing scan length:\n @missing_scanlength\n";
print "Missing ctdi:\n @missing_ctdi\n";
print "Missing DLP:\n @missing_DLP\n";
print "Odd acquisition numbers (sometimes, a manufacturer (e.g., Philips) may put something else in this tag):\n @weird_acq\n";

@accession_counter = uniq @accession_counter;
@mrn_counter = uniq @mrn_counter;
my $number_patients = @mrn_counter;
my $number_exams = @accession_counter;
print "Number of exams $number_exams; number of patients $number_patients\n";
print "Find the results in $one_to_one_series\n";

#Goes through the series in grouped_series, removes any duplicate series (detailed in delete_unwanted), and organizes the remaining data into the corresponding 
#results files (for slice, series, or study level information)
sub process_data{

    my $group_size = @grouped_series; 
    print "MRN,accession,protocol,protocol no,series no,# images,scanner_type,scanner_maker,series_description,",
"average_ctdindices,DLP_from_indices,pitch,single_collimation_width,total_collimation_width,",
"kvp,scanlength (last location - first location),end_of_uid,age,exposure time,avg exposure,sum exposure,kernel,",
"study date,image_type,acq date,acq time,acq number,acq date_time,slice loc 0, slice location,body part,",
"length from thickness (imagecounter*thick),slice thickness,table_speed,derived?,start time,end time,scan time\n";
    print "group size: '$group_size'\n";
    
    my %this_group;
    my $counter = 0;
    my @fields;
    my $fields;
    my %HoA;
    $DLPdifferenceFlag=0;
    #my $HoA{$counter};
   
    
    
    foreach(@grouped_series){
                  
        chomp $_;               
        @fields = split ',',$_;                  
        $HoA{$counter} = [@fields];                                 
        print "$counter-->$_\n";              
        $counter++;        
    }
    #Deletes the duplicate series, primarily based off of acquisition time of series with non-zero DLP.  
    delete_unwanted(\%HoA,$group_size);
    
    print "New group:\n";
   
     my $study_DLP=0;
     my $study_Dose =0;
     my $acc_for_rep;
     my $st_des;
     my $Age;
     my $gender;
     my $protocol_name;
     my $protocol_no;
     my $series_scanned_volume=0;
     my $water_eq_diameter=0;
     my $ScanLength=0;
     my $genderFlag;
     my $pedsFlag;
     my $DLP_residual;
     my $predicted_DLP;
     my $outlierFlag;
     my $scanner_maker;
     my $scanner_type;
     my $date;
     my $StudyTime;
     my $MRN;
     my $physician;
     my $filter;
     my $acquisitions = keys %HoA;

     my @contributing_series;
         
    #assign all values for printing
    #sum up values that need to be summed for the whole study
    #################################################################################################         
    for $fields ( sort {$a<=>$b} keys %HoA) {

         print "$fields-->". join (',', @{$HoA{$fields}}) ."\n";
         push(@contributing_series, $HoA{$fields}[8]);
         $study_DLP = $study_DLP + $HoA{$fields}[10];
         $study_Dose = $study_Dose = $HoA{$fields}[48];
         $ScanLength = $ScanLength + $HoA{$fields}[15];
         
                      $acc_for_rep = $HoA{$fields}[1];
         $physician = $HoA{$fields}[49];
         $filter = $HoA{$fields}[50];
         $st_des = $HoA{$fields}[40];
         $protocol_name = $HoA{$fields}[2];
         $protocol_no = $HoA{$fields}[3];
         $StudyTime = $HoA{$fields}[45];
         $date =$HoA{$fields}[24];
         $MRN = $HoA{$fields}[0];
         print "DATE '$date'\n";
         $scanner_maker = $HoA{$fields}[7];
         $scanner_type = $HoA{$fields}[6];

         if($HoA{$fields}[43] eq "NoValue" or $HoA{$fields}[44] eq "NoValue"){
          $series_scanned_volume = "NoValue";   
          $water_eq_diameter =  "NoValue";
             }elsif($HoA{$fields}[43] eq "NoIm" or $HoA{$fields}[44] eq "NoIm"){

          $series_scanned_volume = "NoIm";   
          $water_eq_diameter =  "NoIm";
          
             }elsif($HoA{$fields}[43] eq "NoAx" or $HoA{$fields}[44] eq "NoAx"){
          $series_scanned_volume = "NoAx";   
          $water_eq_diameter =  "NoAx";
             }else{
                 if($series_scanned_volume eq "NoAx" or  $series_scanned_volume eq "NoIm" or $series_scanned_volume eq "NoValue"){print "Can't add it:$series_scanned_volume\n";}else{       
                    $series_scanned_volume = max($series_scanned_volume,$HoA{$fields}[43]);
                    $water_eq_diameter = max($water_eq_diameter,$HoA{$fields}[44]);
                }
         }
         $gender = $HoA{$fields}[42];
         $Age = $HoA{$fields}[17];
         if($gender eq "F"){$genderFlag = 1;}elsif($gender eq "M"){$genderFlag = 0;}else{$genderFlag = "NoValue";}
         if($Age <=18){ $pedsFlag = 1;}else{$pedsFlag = 0;}         
         
         print "study DLP: '$study_DLP'\nDw: '$water_eq_diameter'\nVol: '$series_scanned_volume'\n";
         
    } #End of fields for loop
    #remove all special characters in study description since it will be used for the file with the regression features (a different regression will be trained on every study description)
    $st_des =~ s/[^a-zA-Z0-9]*//g;
    #Change the study descriptions of those with multi in its name to be a more accurate representation of what it is doing.
    if($st_des=~m/Multi/i){
        my $change;
        if($acquisitions == 2){
            $change = "Bi";
        }
        elsif($acquisitions == 3){
            $change = "Tri";
        }
        elsif($acquisitions == 4){
            $change = "Tetra";
        }
        if ($change){
            $st_des =~ s/Multi/$change/i;
        }
    }
    print "Going to look for file:\n$prog_path/RegressionFeatures$st_des.csv\n";

    #detect outliers
  
     ####################################################################################
    print "OUTSIDE: study DLP: '$study_DLP'\nDw: '$water_eq_diameter'\nVol: '$series_scanned_volume'\n";
    my $RegressionFeaturesFile = "$prog_path/model/RegressionFeatures$st_des.csv";
    my @predictors = (1,$Age,$genderFlag,$pedsFlag,$series_scanned_volume,$water_eq_diameter,$ScanLength);
    print "PREDICTORS @predictors\n";
    my $observation = $study_DLP;
    if (-e $RegressionFeaturesFile) {
        ($predictedValue,$residualValue,$outlierFlag) = DetectOutliers::DetectOutlier($RegressionFeaturesFile,\@predictors,$observation);
         print "PRED $predictedValue,RES $residualValue,O? $outlierFlag\n";
    }elsif(-e "$prog_path/model/RegressionFeaturesDefault.csv"){
        $RegressionFeaturesFile = "$prog_path/model/RegressionFeaturesDefault.csv";
        ($predictedValue,$residualValue,$outlierFlag) = DetectOutliers::DetectOutlier($RegressionFeaturesFile,\@predictors,$observation);
        print "PRED $predictedValue,RES $residualValue,O? $outlierFlag\n";
        #If have a default Regressions model file available, then it is possible to make that the one to be used here. Or rather a different elsif there.
        print "$RegressionFeaturesFile DNE yet. This is the first time seeing such a study, so not running outlier detection on it. Will print data to a model file indexed by $st_des so main script can start a model for this type of exam!\n";
    }
    else{
        print "Please create a default regression file called RegressionFeaturesDefault.csv in the model folder.\n";
        print "Flagging study as outlier because it still needs to be checked\n";
        $predictedValue =0;
        $residualValue=0;
        $outlierFlag=1;
    }
   
     ####################################################################################




    #print to different levels (study, series, slice)
    #################################################################################################
             
    my $study_level_output = "$acc_for_rep,$st_des,$gender,$Age,$genderFlag,$pedsFlag,$series_scanned_volume,$water_eq_diameter,$ScanLength,$study_DLP,$predictedValue,$residualValue,$acquisitions,@contributing_series,$protocol_name,$protocol_no,$scanner_type,$scanner_maker,$date,$outlierFlag,$DLPdifferenceFlag,$StudyTime,$MRN,$study_Dose,$physician,$filter\n";

    #study-level data

    open(OTO, ">>$one_to_one_study" ) or die "Can't open $one_to_one_study because $!\n";
    if($study_DLP){
        print "FINAL DLP '$acc_for_rep': '$study_DLP'\n";
        if(!$secureOn){
            print OTO $study_level_output;
        }
        else{
            chomp $study_level_output;
            my $encryptLine = encode($encoding,$study_level_output);
            print OTO "$encryptLine\n";
        }          
    }
      
    close OTO;
    #Print outlier infromation to their own file     
    if($outlierFlag==1){
        if(!$secureOn){
            open(OUT, ">>","$prog_path/outliers.csv");
            print OUT $study_level_output;
            close OUT;
        }
        else{
            open(OUT, ">>","$prog_path/outliersEncrypt.csv");
            chomp $study_level_output;
            my $encryptLine = encode($encoding,$study_level_output);
            print OUT "$encryptLine\n";
            close OUT;
        }
    }
         
    #If desired, add the collected information to the regression model information     
    if($updateData){
        my $RegressionModelData = "$prog_path/model/RegressionModelData$st_des.csv";
        open(RM,">>$RegressionModelData") or die "Can't open $RegressionModelData because $!\n";
        print RM $study_level_output;
        close RM;
    }
    
    #series-level data
         
    open(LOG, ">>$one_to_one_series" ) or die "Can't open $one_to_one_series because $!\n";

    for $fields ( sort {$a<=>$b} keys %HoA) {

        my $toAdd = "". join (',', @{$HoA{$fields}}) .",$outlierFlag,$DLPdifferenceFlag\n";
        if(!$secureOn){
            print LOG $toAdd;
        }
        else{
            chomp $toAdd;
            my $encryptLine = encode($encoding,$toAdd);
            print LOG "$encryptLine\n";
        }

    }
    close LOG;
    
    #slice-level data       
        
    if($slice_data == 1 ){
        open(SLDAO,">>$one_to_one_slice") or die "Cannot open $one_to_one_slice $!\n";    
        foreach(@SliceData){
              unless($_ =~ m/DeletedSlice/){
                chomp $_; 
                if(!$secureOn){
                    print SLDAO "$_\n";
                }
                else{
                   chomp;
                     my $encryptLine = encode($encoding,$_);
                    print SLDAO "$encryptLine\n";
                }
            }
        }
        close SLDAO;
    }   
    undef %HoA;
           
}

sub split_into_variables{
    print "inside splitter\n";
    print "splitting $_\n";
 
    my @features = split(',',$_);
    print "\n\nLength_prob ", $features[31] , "\n";     
       
#Here are the indices of the arrays in HoA:
       
 # $MRN, 			        0
 # $accession, 			        1
 # $protocol_name,  			2
 # $protocol_number, 			3
 # $series_no, 			        4
 # $image_counter, 			5
 # $scanner_type, 			6
 # $scanner_maker, 			7
 # $series_description, 		8
 # $average_ctdindices, 		9
 # $DLP_from_indices, 			10
 # $pitch, 			        11
 # $single_collimation_width, 		12
 # $total_collimation_width, 		13
 # $kvp,			        14
 # $scanlength, 			15
 # $end_of_uid, 			16
 # $age, 			        17
 # $exposure_time, 			18
 # $average_exposure, 			19
 # $sum_exposure, 			20
 # $kernel, 			        21
 # $study_date, 			22
 # $image_type, 			23
 # $Acquisition_date, 			24
 # $Acquisition_time, 			25
 # $Acquisition_number, 		26
 # $Acquisiton_date_time, 		27
 # $slice_location_0, 			28
 # $slice_location_f, 			29
 # $body_part, 			        30
 # $series time, 			31
 # $slice_thickness,			32
 # $table_speed, 			33
 # null                                 34
 # $start_time,			        35
 # $end_time,			        36
 # $scan_time			        37
 #expf                                  38
 #expi                                  39
 #stdes                                 40
 #$name,",                              41
 #$gender,",                            42
 #$series_scanned_volume,",             43
 #$water_eq_diameter\n";                44
 #$StudyTime                            45
  
}

#Identifies series that are "unwanted" either because they have a DLP value of zero, or because they are a duplicate series
#as determined by their acquisition time. (Because there is some trouble with acquisition number especially with Toshiba, and
#because only Siemens has Irradiation Event UID)
sub delete_unwanted {
    my @delete;
    my $HoARef=shift; 
    my $group_size = shift;
    print "group size in sub $group_size\n";
    
    #Setting up indices of the values
    
    my $prob_in =34;
    my $serDe_in =8;
    my $proto_name =2;
    my $acqNu_in =26;
    my $ScLen_in =15;
    my $SerNu_in =4;
    my $CTDI_in =9;
    my $Ex_in =18;
    my $DLP_in =10;
    my $Acc_in =1;
    my $kVp_index=14;
    my $Im_ty_in =23;
    my $start_time_in =35;
    my $end_time_in =36;
    my $S_Col_w_in =12;
    my $T_Col_w_in =13;
    my $Pit_in =11;
    my $Sc_M_in =7;
    my $Acq_time_in =25;
    my $thicknessIndex=32;
    my $uid_in =16;
    my $studyDescIn = 40;
    my $scannerMakerIn = 7;

    my $intersection;
    my $fraction_intersect_i;
    my $fraction_intersect_j;
    my $DLP_diff;
    my $DLP_max_diff=10;


    my $hash_size = scalar keys $HoARef;
    print "Hash size $hash_size\n\nHHH:";
    #Removes any series that does not have a description associated with it
    foreach my $key (keys %{$HoARef}){
        if(! defined $HoARef->{$key}[$serDe_in]){print "Missing $HoARef->{$key} corresponding to $serDe_in...\n";push(@delete,$key);}
        if(!$HoARef->{$key}[$serDe_in]){print "Missing $HoARef->{$key} corresponding to $serDe_in...\n";push(@delete,$key);}
        if($HoARef->{$key}[$serDe_in] eq ''){print "Missing $HoARef->{$key} corresponding to $serDe_in ...\n";push(@delete,$key);}
    }
    
    $hash_size = scalar keys $HoARef;
    
    #Print out study descriptions of remaining series
    foreach my $key (keys %{$HoARef}){
        print "Seeing $HoARef->{1}[$studyDescIn]\n";
    }
    
    #Remove any non-alphanumeric characters from the study description
    $HoARef->{1}[$studyDescIn] =~ s/[^a-zA-Z0-9]*//g;
   
    #Starts to go through all of the series
    foreach my $key (keys %{$HoARef}){
        #if the study description exists, print that analyzing it
        if($HoARef->{$key}[$serDe_in]){ print "\n\n\t\t\tJJJ Analyzing'$HoARef->{$key}[$serDe_in]' from exam '$HoARef->{$key}[$Acc_in]'\n\n";}
        else{print "\n\n\t\t\tJJJ This series ('$HoARef->{$key}[$serDe_in]') from exam '$HoARef->{$key}[$Acc_in]' has no description...\n\n";}
        #this is the beginning hash size. Will now start to delete "recons"
        $hash_size = scalar keys $HoARef;
        #first announce the hash size
        print "HoAref size: $hash_size\n";
        #Now, iterate through same hash once for each series (which is currently $HoARef->{$key}) to compare
        foreach my $key_compare (keys %{$HoARef}){

            #Again, just records what it's doing
            if($HoARef->{$key_compare}[$serDe_in]){ print "\n\n\t\t\t\t\tiii Analyzing '$HoARef->{$key_compare}[$serDe_in]' from exam '$HoARef->{$key_compare}[$Acc_in]'\n\n";}
            else{print "\n\n\t\t\tJJJ A series (key = $key_compare) from exam '$HoARef->{$key_compare}[$Acc_in]' has no description...\n\n";}
            
            #if the DLP is zero, discard it. Probably not something to consider. This check is kind of unneccesary now, since only series that will give nonzero DLP pass the filter. However, maybe wise to leave it. May want to move the one checking the DLP of $key up in front of "foreach my $key(keys..." above
            if($HoARef->{$key_compare}[$DLP_in] == '0'){
                print "\t\t$HoARef->{$key_compare}[$serDe_in] has a DLP of 0. Deleting it.\n"; 
                push(@delete,$key_compare);
                last;
            }
            if($HoARef->{$key}[$DLP_in] == '0'){
                print "\t\t$HoARef->{$key}[$serDe_in] has a DLP of 0. Deleting it.\n"; 
                push(@delete,$key);
                last;
            }
            #I've never seen a study without a series number; this is me being very careful, but is probably not necessary.
            #Nevertheless, the following algorithm requires a series number, so I wanted to check.
            #Note: DICOM conformance statements say that the series number is always present, so very likely it is unnecessary, especially with newer scanners
            if(!$HoARef->{$key_compare}[$SerNu_in] or !$HoARef->{$key}[$SerNu_in]){
                print "Can't continue, one of the series is missing a series number.";
                last;
            }

            #If the ending and starting time are the same, most likely that it is talking about series time, so it can be used as a way to filter things out (for us, Toshiba and
            #Philips scanners would do this, and it would be more reliable than acquisition number due to certain studies).
            if(($HoARef->{$key_compare}[$start_time_in]-$HoARef->{$key_compare}[$end_time_in]==0) && ($HoARef->{$key_compare}[$start_time_in] == $HoARef->{$key}[$start_time_in])){
                
                #If it's looking at the same scan, but in a series with a different uid, filter.
                if ($HoARef->{$key_compare}[$acqNu_in] == $HoARef->{$key}[$acqNu_in] and $HoARef->{$key_compare}[$uid_in] ne $HoARef->{$key}[$uid_in] ){

                    print "Same acquisition $HoARef->{$key_compare}[$acqNu_in] for  $HoARef->{$key_compare}[$serDe_in] and $HoARef->{$key}[$serDe_in].\n";
                    print "\t\t\t$HoARef->{$key_compare}[$serDe_in]:$HoARef->{$key_compare}[$start_time_in] to $HoARef->{$key_compare}[$end_time_in]\n";
                    print "\t\t\t$HoARef->{$key}[$serDe_in]:$HoARef->{$key}[$start_time_in] to $HoARef->{$key}[$end_time_in]\n";


                    #Even if the acquisitions are the same, if the kVp, they can't possibly be the same acquisitions. If the protocol name is not the same, they also can't be the same acquisitions (this is a way to ensure the Carotid ones from Toshiba are correct)
                    #May be not necessary at this point
                    if($HoARef->{$key_compare}[$proto_name] ne $HoARef->{$key}[$proto_name] or $HoARef->{$key_compare}[$kVp_index] != $HoARef->{$key}[$kVp_index]){
                        print "\t\t\t\t\t!!!!!!!!!!!!$HoARef->{$key_compare}[$proto_name] == $HoARef->{$key}[$proto_name] and $HoARef->{$key_compare}[$kVp_index] == $HoARef->{$key}[$kVp_index], doing nothing\n";
                        last;
                    }
                    #################### Delete one with smaller thickness. This is because the BV CAD has an image limit of 1000. 
                    #If the thickness is very thin a series may have more than that, in which case it will get no BV,Dw from the CAD. 
                    #We don't want this to happen (although I did accomodate it in the regression,--it checks for that before it runs, just in case). 
                    #When Dr. Yao increases the limit on the BV program, this could be removed. 

                    if($HoARef->{$key_compare}[$thicknessIndex] > $HoARef->{$key}[$thicknessIndex] ){
                        print "Thickness of $HoARef->{$key_compare}[$serDe_in] ($HoARef->{$key_compare}[$thicknessIndex])>thickness $HoARef->{$key}[$serDe_in]($HoARef->{$key}[$thicknessIndex]). Eliminating $HoARef->{$key}[$serDe_in].\n";
                        push(@delete,$key);
                        last;
                    }else{
                        print "Thickness of $HoARef->{$key_compare}[$serDe_in] ($HoARef->{$key_compare}[$thicknessIndex])<thickness $HoARef->{$key}[$serDe_in] ($HoARef->{$key}[$thicknessIndex]). Eliminating $HoARef->{$key_compare}[$serDe_in]\n";
                        push(@delete,$key_compare);
                        last;  
                    }
                 }
            }

            #If the acquisition times aren't equal, then number can be used to sort, and can be verified by looking at the time to see if there's any overlap.
            elsif($HoARef->{$key_compare}[$acqNu_in] == $HoARef->{$key}[$acqNu_in]){
                if( ($HoARef->{$key_compare}[$start_time_in] >= $HoARef->{$key}[$start_time_in] && $HoARef->{$key_compare}[$start_time_in] <= $HoARef->{$key}[$end_time_in]) || 
                  ($HoARef->{$key_compare}[$end_time_in] >= $HoARef->{$key}[$start_time_in] && $HoARef->{$key_compare}[$end_time_in] <= $HoARef->{$key}[$end_time_in]) ||
                  ($HoARef->{$key}[$start_time_in] >= $HoARef->{$key_compare}[$start_time_in] && $HoARef->{$key}[$start_time_in] <= $HoARef->{$key_compare}[$end_time_in])){
                      
                    #could make the following a subroutine for improved readibility, but I will comment abundantly to try to help

                    print "Acquisition number $HoARef->{$key_compare}[$acqNu_in] exists. Acquisition times $HoARef->{$key_compare}[$Acq_time_in] and $HoARef->{$key}[$Acq_time_in] are the same\n";

                    #if the acquisition numbers are the same and the series numbers are not (it's not itself)... Maybe Series uid depending on what want it to do.
                    if ($HoARef->{$key_compare}[$acqNu_in] == $HoARef->{$key}[$acqNu_in] and $HoARef->{$key_compare}[$uid_in] ne $HoARef->{$key}[$uid_in] ){

                        print "Same acquisition $HoARef->{$key_compare}[$acqNu_in] for  $HoARef->{$key_compare}[$serDe_in] and $HoARef->{$key}[$serDe_in].\n";
                        print "\t\t\t$HoARef->{$key_compare}[$serDe_in]:$HoARef->{$key_compare}[$start_time_in] to $HoARef->{$key_compare}[$end_time_in]\n";
                        print "\t\t\t$HoARef->{$key}[$serDe_in]:$HoARef->{$key}[$start_time_in] to $HoARef->{$key}[$end_time_in]\n";


                        #Even if the acquisitions are the same, if the kVp, they can't possibly be the same acquisitions. If the protocol name is not the same, they also can't be the same acquisitions (this is a way to ensure the Carotid ones from Toshiba are correct)
                        #May be not necessary at this point
                        if($HoARef->{$key_compare}[$proto_name] ne $HoARef->{$key}[$proto_name] or $HoARef->{$key_compare}[$kVp_index] != $HoARef->{$key}[$kVp_index]){
                            print "\t\t\t\t\t!!!!!!!!!!!!$HoARef->{$key_compare}[$proto_name] == $HoARef->{$key}[$proto_name] and $HoARef->{$key_compare}[$kVp_index] == $HoARef->{$key}[$kVp_index], doing nothing\n";
                            last;
                        }
                        #################### Delete one with smaller thickness if DLP are close. This is because the BV CAD has an image limit of 1000. 
                        #If the thickness is very thin a series may have more than that, in which case it will get no BV,Dw from the CAD. 
                        #We don't want this to happen (although I did accomodate it in the regression,--it checks for that before it runs, just in case). 
                        #When Dr. Yao increases the limit on the BV program, this could be removed. 
                        $DLP_diff = abs($HoARef->{$key_compare}[$DLP_in] - $HoARef->{$key}[$DLP_in]);

                        if($DLP_diff<$DLP_max_diff){
                            print "DLP difference between series is $DLP_diff, less than max $DLP_max_diff\n";
                            if($HoARef->{$key_compare}[$thicknessIndex] > $HoARef->{$key}[$thicknessIndex] ){
                                print "Thickness of $HoARef->{$key_compare}[$serDe_in] ($HoARef->{$key_compare}[$thicknessIndex])>thickness $HoARef->{$key}[$serDe_in]($HoARef->{$key}[$thicknessIndex]). Eliminating $HoARef->{$key}[$serDe_in].\n";
                                push(@delete,$key);
                                last;
                            }elsif($HoARef->{$key_compare}[$thicknessIndex] < $HoARef->{$key}[$thicknessIndex] ){
                                print "Thickness of $HoARef->{$key_compare}[$serDe_in] ($HoARef->{$key_compare}[$thicknessIndex])<thickness $HoARef->{$key}[$serDe_in] ($HoARef->{$key}[$thicknessIndex]). Eliminating $HoARef->{$key_compare}[$serDe_in]\n";
                                push(@delete,$key_compare);
                                last;  
                            }

                        }
                        #####################
                        #...look at the acquisition times. If one of the series contains the other, keep the longer one
                        if(($HoARef->{$key_compare}[$start_time_in] <= $HoARef->{$key}[$start_time_in]) and ($HoARef->{$key_compare}[$end_time_in] >= $HoARef->{$key}[$end_time_in]) and (($HoARef->{$key_compare}[$start_time_in] != $HoARef->{$key_compare}[$end_time_in]) and ($HoARef->{$key}[$start_time_in] != $HoARef->{$key}[$end_time_in])) ){
                            print "\t\t\t\t$HoARef->{$key_compare}[$serDe_in] temporally contains $HoARef->{$key}[$serDe_in] (for all intents and purposes)\n"; 
                            push(@delete,$key);
                            last;
                        }
                        elsif(($HoARef->{$key_compare}[$start_time_in] >= $HoARef->{$key}[$start_time_in]) and ($HoARef->{$key_compare}[$end_time_in] <= $HoARef->{$key}[$end_time_in]) and (($HoARef->{$key_compare}[$start_time_in] != $HoARef->{$key_compare}[$end_time_in]) and ($HoARef->{$key}[$start_time_in] != $HoARef->{$key}[$end_time_in]))){
                            print "\t\t\t\t$HoARef->{$key}[$serDe_in] temporally contains $HoARef->{$key_compare}[$serDe_in] (for all intents and purposes)\n"; 
                            push(@delete,$key_compare);
                            last;
                        }
                        #...if neither contains another fully but they intersect, delete the shorter one
                        # if key start < key compare start < key end OR key start <key compare end < key end
                        #Can't happen if basing it offof one containing the other.
                        elsif(
                        (
                        $HoARef->{$key_compare}[$start_time_in] > $HoARef->{$key}[$start_time_in]
                        and
                        $HoARef->{$key_compare}[$start_time_in] < $HoARef->{$key}[$end_time_in]
                        )

                        or

                        (
                        $HoARef->{$key_compare}[$end_time_in] > $HoARef->{$key}[$start_time_in]
                        and
                        $HoARef->{$key_compare}[$end_time_in] < $HoARef->{$key}[$end_time_in])
                        )
                        {
                            my $intersection1 = $HoARef->{$key}[$end_time_in] - $HoARef->{$key_compare}[$start_time_in];
                            my $intersection2 = $HoARef->{$key_compare}[$end_time_in] - $HoARef->{$key}[$start_time_in];


                            print "There's an intersection of length $intersection1 or $intersection2\n";
                            #Either way, keep the longer series

                            my $keyLength = $HoARef->{$key}[$end_time_in]-$HoARef->{$key}[$start_time_in];
                            my $keyCompareLength = $HoARef->{$key_compare}[$end_time_in]-$HoARef->{$key_compare}[$start_time_in];

                            if( $keyLength > $keyCompareLength ){
                                print "KEY: $keyLength; KEY COMPARE:$keyCompareLength\n";
                                print "deleting KEY COMPARE $HoARef->{$key_compare}[$serDe_in]\n";
                                push(@delete,$key_compare);
                                last;
                                #an "else{..." would do I think, but might as well belabor the point
                            }elsif( $keyLength < $keyCompareLength ){
                                print "KEY: $keyLength; KEY COMPARE:$keyCompareLength\n";
                                print "deleting KEY $HoARef->{$key}[$serDe_in]\n";
                                push(@delete,$key);
                                last;

                            }elsif( $keyLength == $keyCompareLength ){

                                print "KEY: $keyLength; KEY COMPARE:$keyCompareLength\n";
                                print "deleting KEY $HoARef->{$key}[$serDe_in]\n";
                                push(@delete,$key);
                                last;

                            }
                            #Finally, since we know the acquisition numbers are the same (we are still here only because that's true), if all of the acquisition time stuff falls short, we can check the DLPs. I highly doubt it comes to this very often
                        }

                    }elsif ($HoARef->{$key_compare}[$acqNu_in] == $HoARef->{$key}[$acqNu_in] and $HoARef->{$key_compare}[$SerNu_in] ==$HoARef->{$key}[$SerNu_in]){
                    print "Was looking at itself \n";

                    }

                }       
            }
        }

        ######################################################################################################################
        #move this out one? (out of foreach keys)???
        ######################################################################################################################              
        #if the engine was set to retrieve and analyze slice-specific data...

        if ($slice_data == 1){
            foreach (@delete){
                print "deleting:\n$_\n";
            }
            #for all of the slicedata...
            for my $in (0 .. $#SliceData){
                for my $delete_cand (@delete){


                    #print "Delete cand = $delete_cand\n";

                    my @slice_datas = split (',', $SliceData[$in]);
                    #look for the series uid
                    if(defined $HoARef->{$delete_cand}[$uid_in] and defined $slice_datas[$uid_in]){
                        #if it's not the first line...
                        if($HoARef->{$delete_cand}[$uid_in] ne 'end_of_uid'){
                            #push that index to an array '@SlicestoShift'
                            if($HoARef->{$delete_cand}[$uid_in] eq $slice_datas[$uid_in]){
                                #print "Yes! shifting $SliceData[$in]\n";
                                #print "Pushing 
                                push(@SlicestoShift,$in);
                            }else{
                                #print "No.\n";
                            }
                        }
                    }
                }
            }
        }

        #print "DeletedSlice in place of to-delete slices
        foreach(@SlicestoShift){
            $SliceData[$_] = "DeletedSlice";
        }


        #now that we know who to delete, delete them
        foreach(@delete){delete $HoARef->{$_};}
        ######################################################################################################################              
        ######################################################################################################################

    }

}    
