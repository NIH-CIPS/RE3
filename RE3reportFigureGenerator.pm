
package RE3reportFigureGeneratorFix;

#RE3 report figure generator contains subroutines that are able to generate the plots as described below
#Written by: Joy Li	Updated by: Will Kovacs
use strict;
use warnings;use List::MoreUtils qw/ uniq /;
#plotdlpboxbyage: Creates two boxplots of all the DLP values. One plot is for all the patients under the cutoff age given as a parameter, the other is for
#the patients with age above the threshold.
#Use with format ("address to data", "cutoff age for two box plots", starting date yearmonthday, end date yearmonthday);
#plotdlpboxbyage("C:\\RE3\\one-to-one_study.csv",18,20140907,20140912);

#plotoutlieragepie: Creates a pie graph of the outliers separated by age, each section representing a 10 year range.
#Use with format ("address to data", starting date yearmonthday, end date yearmonthday);
#plotoutlieragepie("C:\\RE3\\one-to-one_study3stddev.csv",20140907,20140912);

#plotdlpscatter: Creates a scatterplot of the DLP as a function of a specified parameter.
#Use with format ("address to data", "variable: Age or DLP or Dw or Scan Length or Scan Volume or Predicted or Residual, starting date yearmonthday, end date yearmonthday);
#plotdlpscatter("C:\\RE3\\one-to-one_study.csv","Age",20140908,20140912);

#plothistogram: Use this to create a histogram of a specified parameter
#Use with format ("address to data", "variable: Age or DLP or Dw or Scanned Volume", starting date yearmonthday, end date yearmonthday);
#plothistogram("C:\\RE3\\one-to-one_study.csv","DLP",20140900,20140920);

#plotscatterandreg: Creates a scatterplot of the predicted DLP based on the regression model vs the actual DLP values, along with lines for three std deviations. #Use with format ("address to data", "cutoff age for different colors", starting date yearmonthday, end date yearmonthday,"regression features file", "study description", "program path");
#plotscatterandreg("C:/RE3/Model/RegressionModelDataCTChestAbdomenPelvis.csv",18,20140908,20140912,"C:/RE3/Model/RegressionFeaturesCTChestAbdomenPelvis.csv", "CTChestAbdomenPelvis", "C:/RE3");

#genRegFig:An alternative to plotscatterandreg which uses gnuplot to create a different version of the graph with outliers labelled with their accession number
#Use with format ("address to data", "cutoff age for different colors", starting date yearmonthday, end date yearmonthday,"regression features file", "study description","program path");

sub plotdlpscatter
{
	use DBI;
	use DBD::Chart;

	#Sets input format

	my ($new_Data, $variable, $date1, $date2, $reportProtocol, $reportPeds) = @_;

	my $dbh = DBI->connect('dbi:Chart:');

	#Opens data file
	if (-e $new_Data){print "$new_Data exists\n";}
	open(NEWDATA,"<$new_Data") or print "Can't open $new_Data $!\n";
	my @data = (<NEWDATA>);
	my $header = $data[0];

	#Takes off header
	splice(@data,0,1);

	#Sorts datapoints in the designated date frame into new array (all data for one patient is one item in array)
	my @newdata;
	foreach (@data) {
		my @splitdata = split(',', $_);
		if ($splitdata[18] ne " date" and $splitdata[18]>=$date1 and $splitdata[18]<=$date2 && (!($reportProtocol)||$splitdata[1] eq $reportProtocol) && (!($reportPeds)||$splitdata[5] == $reportPeds)) {
			push (@newdata, $_);
		 }
	}

	#Splits each item in the array and sorts each variable into a new array
	my @Acc_for_rep;
	my @St_des;
	my @Gender;
	my @Age;
	my @Series_scanned_volume;
	my @Water_eq_diameter;
	my @ScanLength;
	my @Study_DLP;
	my @Predicted;
	my @Residual;
	my @Acq;
	my @Scanner;
	my @Scannertype;
	my @Scannermaker;
	my @Outlierstatus;
	my @Date;
	foreach (@newdata) {
		my  @splitdata = split(',', $_);
		push (@Acc_for_rep, $splitdata[0]);
		push (@St_des, $splitdata[1]);
		push (@Gender, $splitdata[2]);
		push (@Age, $splitdata[3]);
		push (@Series_scanned_volume, $splitdata[6]);
		push (@Water_eq_diameter, $splitdata[7]);
		push (@ScanLength, $splitdata[8]);
		push (@Study_DLP, $splitdata[9]);  
		push (@Predicted, $splitdata[10]);
		push (@Residual, $splitdata[11]);
		push (@Acq, $splitdata[12]);
		push (@Scannertype, $splitdata[16]);
		push (@Scannermaker, $splitdata[17]);
		push (@Outlierstatus, $splitdata[19]);
		push (@Date, $splitdata[18]);
	}

	#Creates database ageanddlp
	$dbh->do('CREATE CHART ageanddlp (Month DECIMAL, sales DECIMAL)');
	my $sth = $dbh->prepare('INSERT INTO ageanddlp VALUES( ?, ?)');

	#Pushes variable into the @values array based on input array
	my @values;
	my $title;
	my $xaxis;

	if ($variable eq "Scan Length") {
		$title = "Dose Length Product and Scan Length";
		$xaxis = "Scan Length (cm)";
		push (@values, @ScanLength);
	}
	if ($variable eq "Scanned Volume"){
		$title = "Dose Length Product and Scanned Volume";
		$xaxis = "Volume (cm^3)";
		push (@values, @Series_scanned_volume);
	}
	if ($variable eq "Dw"){
		$title = "Dose Length Product and Water Equivalent Diameter";
		$xaxis = "Dw (cm)";
		push (@values, @Water_eq_diameter);
	}
	if ($variable eq "Age"){
		$title = "Dose Length Product and Patient Age";
		$xaxis = "Age (Years)";
		push (@values, @Age);
	}
	if ($variable eq "Predicted"){
		$title = "Measured Dose Lenght Product and Predicted Dose Length Product";
		$xaxis = "Predicted DLP (mGYcm)";
		push (@values, @Predicted);
	}
	if ($variable eq "Residual"){
		$title = "Dose Length Product and Residual from Predicted DLP";
		$xaxis = "Residual DLP (mGYcm)";
		push (@values, @Residual);
	}

	#Plots data points

	my @indices = sort {$values[$a] <=> $values[$b]} 0 .. $#values;
	@values = @values[@indices];
	@Study_DLP = @Study_DLP[@indices];
	for my $i (0 .. $#Study_DLP)
	{
	      $sth->execute($values[$i], $Study_DLP[$i]);
	}

	#Controls graph settings
	my $rsth = $dbh->prepare(
	"SELECT POINTGRAPH FROM ageanddlp
	WHERE WIDTH=600 and HEIGHT=350 AND X_AXIS='$xaxis' AND
	title='$title' AND
	Y_AXIS='Dose Length Product (mGYcm)' AND
	SHOWVALUES = 0 AND
	SHOWGRID = 1 AND
	SHAPE = 'filldiamond' AND
	SIGNATURE='Date: $date1 to $date2' AND
	COLOR= 'blue' AND
	BACKGROUND ='white'
	AND FORMAT = 'JPEG'");
	#Executes points
	my $buf;
	$rsth->execute;
	$rsth->bind_col(1, \$buf);
	$rsth->fetch;
	#Saves as .png file
	open(OUTF, '>Scatterplot.jpg');
	binmode OUTF;
	print OUTF $buf;
	close(OUTF);
	print "Scatterplot.jpg OK\n";
}

sub plotdlpboxbyage
{
	use DBD::Chart;
	use Math::Round;

	#Sets input format


	my ($new_Data, $age, $date1, $date2, $reportProtocol, $reportPeds, $missingAcq) = @_;

	#Opens file
	if (-e $new_Data){print "$new_Data exists\n";}
	open(NEWDATA,"<$new_Data") or print "Can't open $new_Data $!\n";
	my @data = (<NEWDATA>);
	my $header = $data[0];

	my %missing;
	my @missingExams;

	open(EXAM, "<",$missingAcq);	while(<EXAM>){
		chomp $_;
		$missing{$_}=1;
	}
	close EXAM;
	#Deletes Header from dataset
	splice(@data,0,1);

	#Sorts datapoints in the designated date frame into new array (all data for one patient is one item in array)
	my @newdata;
	foreach (@data) {
		my @splitdata = split(',', $_);
		
		if ($splitdata[18] ne " date" and $splitdata[18]>=$date1 and $splitdata[18]<=$date2 && (!($reportProtocol)||$splitdata[1] eq $reportProtocol) && (!($reportPeds)||$splitdata[5] == $reportPeds)) {
			if($missing{$splitdata[14]}){
				push(@missingExams,$splitdata[0]);
			}
			push (@newdata, $_);
		 }
	}

	#Splits each item in the array and sorts each variable into a new array
	my @Acc_for_rep;
	my @St_des;
	my @Gender;
	my @Age;
	my @Series_scanned_volume;
	my @Water_eq_diameter;
	my @ScanLength;
	my @Study_DLP;
	my @Predicted;
	my @Residual;
	my @Acq;
	my @Scanner;
	my @Scannertype;
	my @Scannermaker;
	my @Outlierstatus;
	my @Date;
	my @MRN;
	foreach (@newdata) {
		my  @splitdata = split(',', $_);
		push (@Acc_for_rep, $splitdata[0]);
		push (@St_des, $splitdata[1]);
		push (@Gender, $splitdata[2]);
		push (@Age, $splitdata[3]);
		push (@Series_scanned_volume, $splitdata[6]);
		push (@Water_eq_diameter, $splitdata[7]);
		push (@ScanLength, $splitdata[8]);
		push (@Study_DLP, $splitdata[9]);  
		push (@Predicted, $splitdata[10]);
		push (@Residual, $splitdata[11]);
		push (@Acq, $splitdata[12]);
		push (@Scannertype, $splitdata[16]);
		push (@Scannermaker, $splitdata[17]);
		push (@Outlierstatus, $splitdata[19]);
		push (@Date, $splitdata[18]);
		push (@MRN, $splitdata[22]);
	}

	#Rounds data points to the nearest whole number
	my @ScanLengthR;
	my @Study_DLPR;
	my @Series_scanned_volumeR;
	my @Water_eq_diameterR;

	foreach (@Study_DLP) {
		push (@Study_DLPR, nearest (1,$_));
	}
	foreach (@Series_scanned_volume) {
		push (@Series_scanned_volumeR, nearest (1,$_));
	}
	foreach (@Water_eq_diameter) {
		push (@Water_eq_diameterR, nearest (1,$_));
	}
	foreach (@ScanLength) {
		push (@ScanLengthR, nearest (1,$_));
	}   

	#Creates hash with age as key and DLP as value
	my %hash1;
	@hash1{@Acc_for_rep} = @Study_DLPR;
	my %hash2;
	@hash2{@Acc_for_rep} = @Age;

	my @under;
	my @over;

	#Sorts the DLP into two arrays based on cutoff age
	foreach my $key (sort keys %hash1) {
	     if ($hash2{$key}<$age) {
		push(@under, $hash1{$key});
	     }
	     elsif ($hash2{$key}>=$age) {
		push(@over, $hash1{$key});
		
	     }
	}

	#Creates database samplebox
	my $dbh = DBI->connect('dbi:Chart:');
	$dbh->do('CREATE TABLE samplebox (Under integer, Over integer)');
	my $sth = $dbh->prepare('INSERT INTO samplebox VALUES(?, ?)');

	#Enters in dataset
	if($#under>$#over){
		for my $i (0 .. $#under)
		{
		      $sth->execute($under[$i], $over[$i]);
		}
	}
	else{
	for my $i (0 .. $#over)
		{			
		      $sth->execute($under[$i], $over[$i]);
		}
	}

	#Controls graph settings
	$sth = $dbh->prepare(
	"SELECT BOXCHART, IMAGEMAP FROM samplebox
	WHERE WIDTH=650 and HEIGHT=300 AND X_AXIS='DLP' and
	    title = 'DLP Distribution Comparison by Cutoff Age $age' AND
	    signature = '$header' AND
	    SHOWVALUES = 1 AND
	    SIGNATURE='Date: $date1 to $date2' AND
	    COLORS IN ('red', 'blue')
	    AND FORMAT = 'JPEG'"
	);

	#Graphs data
	$sth->execute;
	my $row = $sth->fetchrow_arrayref;

	#Saves as .png file
	open(PIE, '>BoxPlotByAge.jpg');
	binmode PIE;
	print PIE $$row[0];
	close PIE;
	print "BoxPlotByAge.jpg OK\n";
	my @uniq_patients = uniq @MRN;
	return(scalar @uniq_patients, scalar @Acc_for_rep, @missingExams);
}

sub plotoutlieragepie 
{
	use DBI;
	use DBD::Chart;
	use Math::Round;

	#Sets input variables

	my ($new_Data, $date1, $date2, $reportProtocol, $reportPeds) = @_;

	#Opens file
	if (-e $new_Data){print "$new_Data exists\n";}
	open(NEWDATA,"<$new_Data") or print "Can't open $new_Data $!\n";
	my @data = (<NEWDATA>);
	my $header = $data[0];

	#Removes header
	splice(@data,0,1);

	#Sorts datapoints in the designated date frame into new array (all data for one patient is one item in array)
	my @newdata;
	foreach (@data) {
		my @splitdata = split(',', $_);
		if ($splitdata[18] ne " date" and $splitdata[18]>=$date1 and $splitdata[18]<=$date2 && (!($reportProtocol)||$splitdata[1] eq $reportProtocol) && (!($reportPeds)||$splitdata[5] == $reportPeds)) {
			push (@newdata, $_);
		 }
	}

	#Sorts normal data points into one array and outlier data points into another array
	my @normal;
	my @highoutlier;
	foreach (@newdata) {
		 my @splitdata = split(',', $_);
		 
		 if ($splitdata[19]==1) {
			push (@highoutlier, $_);
		 }
		 elsif ($splitdata[19]==0) {
			push (@normal, $_);
		 }
	}

	my @Acc_for_rep;
	my @St_des;
	my @Gender;
	my @Age;
	my @Series_scanned_volume;
	my @Water_eq_diameter;
	my @ScanLength;
	my @Study_DLP;
	my @Predicted;
	my @Residual;
	my @Acq;
	my @Scannertype;
	my @Scannermaker;
	my @Outlierstatus;
	my @Date;

	#Splits each item in the array and sorts each variable into a new array
	foreach (@highoutlier) {
		my  @splitdata = split(',', $_);
		push (@Acc_for_rep, $splitdata[0]);
		push (@St_des, $splitdata[1]);
		push (@Gender, $splitdata[2]);
		push (@Age, $splitdata[3]);
		push (@Series_scanned_volume, $splitdata[6]);
		push (@Water_eq_diameter, $splitdata[7]);
		push (@ScanLength, $splitdata[8]);
		push (@Study_DLP, $splitdata[9]);  
		push (@Predicted, $splitdata[10]);
		push (@Residual, $splitdata[11]);
		push (@Acq, $splitdata[12]);
		push (@Scannertype, $splitdata[16]);
		push (@Scannermaker, $splitdata[17]);
		push (@Outlierstatus, $splitdata[19]);
		push (@Date, $splitdata[18]);
	}

	#Sorts ages into correct array
	my @age010;
	my @age1020;
	my @age2030;
	my @age3040;
	my @age4050;
	my @age5060;
	my @age6070;
	my @age7080;
	my @ageover80;

	foreach (@Age) {
	     if ($_<10) {
		push(@age010, $_);
	     }
	     if ($_<20 and $_>=10) {
		push(@age3040, $_);
	     }
	     if ($_<30 and $_>=20) {
		push(@age3040, $_);
	     }
	     if ($_<40 and $_>=30) {
		push(@age3040, $_);
	     }
	      if ($_<50 and $_>=40) {
		push(@age4050, $_);
	     }
	      if ($_<60 and $_>=50) {
		push(@age5060, $_);
	     }
	      if ($_<70 and $_>=60) {
		push(@age6070, $_);
	     }
	      if ($_<80 and $_>=70) {
		push(@age7080, $_);
	     }
	      elsif ($_>=80) {
		push(@ageover80, $_);
	     }
	}

	#Counts number of items in each array
	my $bin0to10 = scalar @age010;
	my $bin10to20 = scalar @age1020;
	my $bin20to30 = scalar @age2030;
	my $bin30to40 = scalar @age3040;
	my $bin40to50 = scalar @age4050;
	my $bin50to60 = scalar @age5060;
	my $bin60to70 = scalar @age6070;
	my $bin70to80 = scalar @age7080;
	my $binover80 = scalar @ageover80;

	#Creates database pie
	my $dbh = DBI->connect('dbi:Chart:');

	$dbh->do('CREATE TABLE pie (region CHAR(20), sales FLOAT)');
	my $sth = $dbh->prepare('INSERT INTO pie VALUES( ?, ?)');

	#Creates section of pie chart if it is not empty
	if ($bin0to10 ne 0) {
		my $length = $bin0to10;
		$sth->execute("0-10 ($length)", $bin0to10);
	}
	if ($bin10to20 ne 0) {
		my $length = $bin10to20;
		$sth->execute("10-20 ($length)", $bin10to20);
	}
	if ($bin0to10 ne 0) {
		my $length = $bin20to30;
		$sth->execute("20-30 ($length)", $bin20to30);
	}
	if ($bin30to40 ne 0) {
		my $length = $bin30to40;
		$sth->execute("30-40 ($length)", $bin30to40);
	}
	if ($bin40to50 ne 0) {
		my $length = $bin40to50;
		$sth->execute("40-50 ($length)", $bin40to50);
	}
	if ($bin50to60 ne 0) {
		$sth->execute("50-60 ($bin50to60)", $bin50to60);
	}
	if ($bin60to70 ne 0) {
		$sth->execute("60-70 ($bin60to70)", $bin60to70);
	}
	if ($bin70to80 ne 0) {
		$sth->execute("70-80 ($bin70to80)", $bin70to80);
	}
	if ($binover80 ne 0) {
		$sth->execute(">80 ($binover80)", $binover80);
	}

	#Controls chart settings
	my $rsth = $dbh->prepare(
	"SELECT PIECHART FROM pie
	 WHERE WIDTH=400 AND HEIGHT=400 AND
	 TITLE = 'Age of High Outliers' AND
	 SIGNATURE='Date: $date1 to $date2' AND
	 COLOR IN ('red', 'green', 'blue', 'lyellow', 'marine', 'purple', 'lgreen', 'lpurple', 'orange') AND
	 BACKGROUND='lgray'
	 AND FORMAT = 'JPEG'");
	 
	 	my $buf;
	#Executes chart
	$rsth->execute;
	$rsth->bind_col(1, \$buf);
	$rsth->fetch;

	#Saves chart as .png file
	open(OUTF, '>PieOutlierAge.jpg');
	binmode OUTF;
	print OUTF $buf;
	close(OUTF);
	print "PieOutlierAge.jpg OK\n";
}

sub plothistogram
{
	use DBI;
	use DBD::Chart;
	use Math::SigFigs;
	use List::Util qw( min max );

	#Sets input variables

	my ($data, $category, $date1, $date2, $reportProtocol, $reportPeds) = @_;

	#Opens data file
	my $new_Data = "$data";
	if (-e $new_Data){print "$new_Data exists\n";}
	open(NEWDATA,"<$new_Data") or print "Can't open $new_Data $!\n";
	my @data = (<NEWDATA>);
	my $header = $data[0];

	#Removes header
	splice(@data,0,1);

	#Sorts datapoints in the designated date frame into new array (all data for one patient is one item in array)
	my @newdata;
	foreach (@data) {
		my @splitdata = split(',', $_);
		if ($splitdata[18] ne " date" and $splitdata[18]>=$date1 and $splitdata[18]<=$date2 && (!($reportProtocol)||$splitdata[1] eq $reportProtocol)&& (!($reportPeds)||$splitdata[5] == $reportPeds)) {
			push (@newdata, $_);
		 }
	}

	#Splits each item in the array and sorts each variable into a new array
	my @Acc_for_rep;
	my @St_des;
	my @Gender;
	my @Age;
	my @Series_scanned_volume;
	my @Water_eq_diameter;
	my @ScanLength;
	my @Study_DLP;
	my @Predicted;
	my @Residual;
	my @Acq;
	my @Scanner;
	my @Scannertype;
	my @Scannermaker;
	my @Outlierstatus;
	my @Date;
	foreach (@newdata) {
		my  @splitdata = split(',', $_);
		push (@Acc_for_rep, $splitdata[0]);
		push (@St_des, $splitdata[1]);
		push (@Gender, $splitdata[2]);
		push (@Age, $splitdata[3]);
		push (@Series_scanned_volume, $splitdata[6]);
		push (@Water_eq_diameter, $splitdata[7]);
		push (@ScanLength, $splitdata[8]);
		push (@Study_DLP, $splitdata[9]);  
		push (@Predicted, $splitdata[10]);
		push (@Residual, $splitdata[11]);
		push (@Acq, $splitdata[12]);
		push (@Scannertype, $splitdata[16]);
		push (@Scannermaker, $splitdata[17]);
		push (@Outlierstatus, $splitdata[19]);
		push (@Date, $splitdata[18]);
	}

	#Pushes variable into the @values array based on input array and finds max number in data set
	my $max;
	my $title;
	my $xaxis;
	my @values;

	if ($category eq "DLP") {
		$max = max @Study_DLP;
		$title = "Patient Study Dose Length Product";
		$xaxis = "Dose Length Product (mGYcm)";
		push (@values, @Study_DLP);
	}
	if ($category eq "Scanned Volume"){
		$max = max @Series_scanned_volume;
		$title = "Patient Series Scanned Volume";
		$xaxis = "Volume (cm^3)";
		push (@values, @Series_scanned_volume);
	}
	if ($category eq "Dw"){
		$max = max @Water_eq_diameter;
		$title = "Patient Water Equivalent Diameter";
		$xaxis = "Dw (cm)";
		push (@values, @Water_eq_diameter);
	}
	if ($category eq "Age"){
		$max = max @Age;
		$title = "Patient Age";
		$xaxis = "Age (Years)";
		push (@values, @Age);
	}

	#Sets bins for histogram
	my $round = FormatSigFigs($max,1);
	my $int = $round/5;

	my $int2 = 2*$int;
	my $int3 = 3*$int;
	my $int4 = 4*$int;
	my $int5 = 5*$int;

	my @bin0to1;
	my @bin1to2;
	my @bin2to3;
	my @bin3to4;
	my @bin4to5;
	my @binover5;

	#Sorts values into correct bin
	foreach (@values) {
	     if ($_<$int) {
		push(@bin0to1, $_);
	     }
	     if ($_<$int2 and $_>=$int) {
		push(@bin1to2, $_);
	     }
	     if ($_<$int3 and $_>=$int2) {
		push(@bin2to3, $_);
	     }
	     if ($_<$int4 and $_>=$int3) {
		push(@bin3to4, $_);
	     }
	      if ($_<$int5 and $_>=$int4) {
		push(@bin4to5, $_);
	     }
	      elsif ($_>=$int5) {
		push(@binover5, $_);
	     }
	}

	#Finds how many values are in each bin (sets frequency)
	my $bin1 = scalar @bin0to1;
	my $bin2 = scalar @bin1to2;
	my $bin3 = scalar @bin2to3;
	my $bin4 = scalar @bin3to4;
	my $bin5 = scalar @bin4to5;
	my $bin6 = scalar @binover5;

	#Creates database bars
	my $dbh = DBI->connect('dbi:Chart:');
	$dbh->do('CREATE TABLE bars (quarter FLOAT, East FLOAT)');
	my $sth = $dbh->prepare('INSERT INTO bars VALUES(?, ?)');

	#Plots frequency and labels bars
	$sth->execute(my $bin = $int/2, $bin1);
	$sth->execute($bin+$int, $bin2);
	$sth->execute($bin+$int2, $bin3);
	$sth->execute($bin+$int3, $bin4);
	$sth->execute($bin+$int4, $bin5);

	#Executes last bar only if not empty
	if ($bin6 ne 0) {
		$sth->execute($bin+$int5, $bin6);
	}

	#Controls graph settings
	my $rsth = $dbh->prepare(
	"SELECT BARCHART FROM bars
	WHERE WIDTH=600 AND HEIGHT=400 AND X_AXIS='$xaxis' AND
	Y_AXIS='Frequency' AND TITLE = '$title' AND
	THREE_D=0 AND SHOWVALUES=6 AND
	LINEWIDTH=10 AND
	SIGNATURE='Date: $date1 to $date2' AND
	BACKGROUND= 'white' AND TEXTCOLOR= 'black' AND
	COLORS IN ('lgray')
	AND FORMAT = 'JPEG'");

	my $buf;
	#Executes graph
	$rsth->execute;
	$rsth->bind_col(1, \$buf);
	$rsth->fetch;

	#Saves as .png file
	open(OUTF, '>Histogram.jpg');
	binmode OUTF;
	print OUTF $buf;
	close(OUTF);
	print "Histogram.jpg OK\n";
}


sub plotscatterandreg
{
	use DBI;
	use DBD::Chart;
	use Statistics::Regression;
	use List::Util qw( min max );
	use Statistics::Descriptive;

	my ($new_Data, $age, $date1, $date2,$regFeatures, $studyDesc, $progPath) = @_;

	#Opens file
	if (-e $new_Data){print "$new_Data exists\n";}
	open(NEWDATA,"<$new_Data") or print "Can't open $new_Data $!\n";
	my @data = (<NEWDATA>);

	my $header = $data[0];

	#Removes header
	splice(@data,0,1);

	#Sorts datapoints in the designated date frame into new array (all data for one patient is one item in array)
	my @newdata;
	foreach (@data) {
		my @splitdata = split(',', $_);
		if ($splitdata[18] ne  " date" &&$splitdata[18]>=$date1 and $splitdata[18]<=$date2) {
			push (@newdata, $_);
		 }
	}

	#Ensures that there is actual data within the dates, so it doesn't crash
	my $lengthy = @newdata;
	if($lengthy!=0){
					#Splits each item in the array and sorts each variable into a new array
		my @Acc_for_rep;
		my @St_des;
		my @Gender;
		my @Age;
		my @Series_scanned_volume;
		my @Water_eq_diameter;
		my @ScanLength;
		my @Study_DLP;
		my @Predicted;
		my @Residual;
		my @Acq;
		my @Scanner;
		my @Scannermaker;
		my @Outlierstatus;
		my @Date;
		my @Scannertype;
		foreach (@newdata) {
			my  @splitdata = split(',', $_);
			push (@Acc_for_rep, $splitdata[0]);
			push (@St_des, $splitdata[1]);
			push (@Gender, $splitdata[2]);
			push (@Age, $splitdata[3]);
			push (@Series_scanned_volume, $splitdata[6]);
			push (@Water_eq_diameter, $splitdata[7]);
			push (@ScanLength, $splitdata[8]);
			push (@Study_DLP, $splitdata[9]);  
			push (@Predicted, $splitdata[10]);
			push (@Residual, $splitdata[11]);
			push (@Acq, $splitdata[12]);
			push (@Scannertype, $splitdata[16]);
			push (@Scannermaker, $splitdata[17]);
			push (@Outlierstatus, $splitdata[19]);
			push (@Date, $splitdata[18]);
		}
		my $x = max(@Predicted);
		
		#Grabs the regression featuers
		open(REG,"<",$regFeatures);
		my @coefficientsToGet = <REG>;
		close REG;
		my $coefSize =@coefficientsToGet;
		my @coefficientsArray = split(',',$coefficientsToGet[$coefSize-1]);
		
		#Graphs three standard deviations above regression
		my $stdDev = $coefficientsArray[$#coefficientsArray];		
		my $dbh = DBI->connect('dbi:Chart:');
		$dbh->do('CREATE CHART Standarddeviation (Month DECIMAL, sales DECIMAL)');
		my $sth = $dbh->prepare('INSERT INTO Standarddeviation VALUES( ?, ?)');
		$sth->execute(0, $stdDev);
		$sth->execute($x, $x+$stdDev);

		#Graphs three standard deviations below regression
		$dbh = DBI->connect('dbi:Chart:');
		$dbh->do('CREATE CHART Standarddeviation2 (Month DECIMAL, sales DECIMAL)');
		$sth = $dbh->prepare('INSERT INTO Standarddeviation2 VALUES( ?, ?)');
		$sth->execute(0, -$stdDev);
		$sth->execute($x, $x-$stdDev);

		#Graphs regression
		$dbh = DBI->connect('dbi:Chart:');
		$dbh->do('CREATE CHART Regression (Month DECIMAL, sales DECIMAL)');
		$sth = $dbh->prepare('INSERT INTO Regression VALUES( ?, ?)');
		$sth->execute(0, 0);
		$sth->execute($x, $x);

		# Opens file and sets data inputs
		if (-e $new_Data){print "$new_Data exists\n";}
		my ($new_Data, $age, $date1, $date2,$regFeatures, $studyDesc) = @_;
		open(NEWDATA,"<$new_Data") or print "Can't open $new_Data $!\n";
		my @data = (<NEWDATA>);
		my $header = $data[0];

		#Removes header
		splice(@data,0,1);

		#Sorts datapoints in the designated date frame into new array (all data for one patient is one item in array)
		my @newdata;
		foreach (@data) {
			my @splitdata = split(',', $_);
			if ($splitdata[18] ne  " date" &&$splitdata[18]>=$date1 and $splitdata[18]<=$date2) {
				push (@newdata, $_);
			 }
		}

		#Sorts datapoints into two arrays based on cutoff age
		my @overage;
		my @underage; 
		my @outlier;
		foreach (@newdata) {
			 my @splitdata = split(',', $_);
			 if ($splitdata[19]==1){
				push (@outlier, $_);
			 }
			 elsif ($splitdata[3]>=$age) {
				push (@overage, $_);
			 }
			 elsif ($splitdata[3]<$age) {
				push (@underage, $_);
			 }

		#Splits each item in the both arrays and sorts each variable into a new array	 
		}

		my @Acc_for_rep3;
		my @St_des3;
		my @Gender3;
		my @Age3;
		my @Series_scanned_volume3;
		my @Water_eq_diameter3;
		my @ScanLength3;
		my @Study_DLP3;
		my @Predicted3;
		my @Residual3;
		my @Acq3;
		my @Scanner3;
		my @Scannertype3;
		my @Scannermaker3;
		my @Referringphy3;
		my @Outlierstatus3;
		my @Date3;
		foreach (@outlier) {
			my  @splitdata= split(',', $_);
			push (@Acc_for_rep3, $splitdata[0]);
			push (@St_des3, $splitdata[1]);
			push (@Gender3, $splitdata[2]);
			push (@Age3, $splitdata[3]);
			push (@Series_scanned_volume3, $splitdata[6]);
			push (@Water_eq_diameter3, $splitdata[7]);
			push (@ScanLength3, $splitdata[8]);
			push (@Study_DLP3, $splitdata[9]);  
			push (@Predicted3, $splitdata[10]);
			push (@Residual3, $splitdata[11]);
			push (@Acq3, $splitdata[12]);
			push (@Scannertype3, $splitdata[16]);
			push (@Scannermaker3, $splitdata[17]);
			push (@Outlierstatus3, $splitdata[19]);
			push (@Date3, $splitdata[18]);
		}

		my @Acc_for_rep1;
		my @St_des1;
		my @Gender1;
		my @Age1;
		my @Series_scanned_volume1;
		my @Water_eq_diameter1;
		my @ScanLength1;
		my @Study_DLP1;
		my @Predicted1;
		my @Residual1;
		my @Acq1;
		my @Scanner1;
		my @Scannertype1;
		my @Scannermaker1;
		my @Referringphy1;
		my @Outlierstatus1;
		my @Date1;


		foreach (@underage) {
			my  @splitdata= split(',', $_);
			push (@Acc_for_rep1, $splitdata[0]);
			push (@St_des1, $splitdata[1]);
			push (@Gender1, $splitdata[2]);
			push (@Age1, $splitdata[3]);
			push (@Series_scanned_volume1, $splitdata[6]);
			push (@Water_eq_diameter1, $splitdata[7]);
			push (@ScanLength1, $splitdata[8]);
			push (@Study_DLP1, $splitdata[9]);  
			push (@Predicted1, $splitdata[10]);
			push (@Residual1, $splitdata[11]);
			push (@Acq1, $splitdata[12]);
			push (@Scannertype1, $splitdata[16]);
			push (@Scannermaker1, $splitdata[17]);
			push (@Outlierstatus1, $splitdata[19]);
			push (@Date1, $splitdata[18]);
		}



		my @Acc_for_rep2;
		my @St_des2;
		my @Gender2;
		my @Age2;
		my @Series_scanned_volume2;
		my @Water_eq_diameter2;
		my @ScanLength2;
		my @Study_DLP2;
		my @Predicted2;
		my @Residual2;
		my @Acq2;
		my @Scanner2;
		my @Scannertype2;
		my @Scannermaker2;
		my @Referringphy2;
		my @Outlierstatus2;
		my @Date2;

		foreach (@overage) {
			my @splitdata2 = split(',', $_);
			push (@Acc_for_rep2, $splitdata2[0]);
			push (@St_des2, $splitdata2[1]);
			push (@Gender2, $splitdata2[2]);
			push (@Age2, $splitdata2[3]);
			push (@Series_scanned_volume2, $splitdata2[6]);
			push (@Water_eq_diameter2, $splitdata2[7]);
			push (@ScanLength2, $splitdata2[8]);
			push (@Study_DLP2, $splitdata2[9]);  
			push (@Predicted2, $splitdata2[10]);
			push (@Residual2, $splitdata2[11]);
			push (@Acq2, $splitdata2[12]);
			push (@Scannertype2, $splitdata2[16]);
			push (@Scannermaker2, $splitdata2[17]);
			push (@Outlierstatus2, $splitdata2[19]);
			push (@Date2, $splitdata2[18]);
		}

		#Creates database and enters data points
		my $dbh2 = DBI->connect('dbi:Chart:');
		#$dbh2->do("DROP TABLE IF EXISTS Dose") or die ("Cannot drop table: " . $dbh->errstr);
		$dbh2->do('CREATE CHART Dose (Month DECIMAL, UnderCutoffAge DECIMAL, OverCutoffAge DECIMAL, Outlier DECIMAL)');
		$sth = $dbh2->prepare('INSERT INTO Dose VALUES( ?, ?, ?, ?)');
		for my $i (0..$#Study_DLP1) {
			
			$sth->execute($Predicted1[$i],$Study_DLP1[$i],undef,undef);
		}

		for my $l (0..$#Study_DLP2) {
			
			$sth->execute($Predicted2[$l],undef,$Study_DLP2[$l], undef);
		}

		for my $k (0..$#Study_DLP3) {
			
			$sth->execute($Predicted3[$k],undef,undef, $Study_DLP3[$k]);
		}

		#Controls graph settings
		$sth = $dbh->prepare(
		"select image, imagemap from
		    (select linegraph from Regression
		    where color='green') Regression,
		    (select linegraph from Standarddeviation
		    where color='red') Standarddeviation,
		    (select linegraph from Standarddeviation2
		    where color='red') Standarddeviation2,
		    (select pointgraph from Dose
		    where COLOR IN ('purple', 'lblue','gray') and shape='filldiamond') Dose
		where WIDTH=500 AND HEIGHT=375 AND
		    TITLE='DLP of $studyDesc' AND
		    SIGNATURE='\nDate: $date1-$date2' AND
		    SHOWVALUES=1 AND
		    X_AXIS='Predicted Dose Length Product (mGYcm)' AND Y_AXIS='Observed Dose Length Product (mGYcm)' AND
		    FORMAT='PNG' AND SHOWGRID=0
		    AND FORMAT = 'JPEG'");
		   #TITLE='DLP of $studyDesc' AND
		my $buf;   		#Executes graph
		$sth->execute;
		$sth->bind_col(1, \$buf);
		$sth->fetch;
		my $row = $sth->fetchrow_arrayref;

		unless ( -e "$progPath/Figures" ) { mkdir "$progPath/Figures"; }		#Saves as .png file
		open(OUTF, '>',"$progPath/Figures/Regression$studyDesc.jpg");
		binmode OUTF;
		print OUTF $buf;
		close(OUTF);
		print "Regression$studyDesc.jpg OK\n";

	}
	else{
		print "NUMBER OF STUDIES IS $lengthy\n";
	}
}

#Alternative method to dlpscatterandreg that uses gnuplot so that the points can be labelled.
sub genRegFig{
  my $fileData = $_[0];
  my $cutoffAge = $_[1];
  my $startDay=$_[2];
  my $endDay=$_[3];
  my $regFile = $_[4];
  my $studyDesc = $_[5];
  my $progPath = $_[6];
  
  #Opening Gnuplot, program path may need to be changed if it's not located there.
  my $pid = open(GP, "|-", 'C:/Program Files/gnuplot/bin/gnuplot.exe' ); 
  my $stdDev;
  
  #Get the regression coefficients.
  open(CAP, "<", $fileData);
  open(REG, "<", $regFile);
  while(<REG>){
    my @value = split(',',$_);
    $stdDev = $value[7];
  }
  chomp $stdDev;
  my @outObserved;
  my @outPredicted;
  my @pedObserved;
  my @pedPredicted;
  my @observed;
  my @predicted;
  my @acc;
  
  #Puts the values in their corresponding array
  while(<CAP>){
    my @values = split(',',$_);
    if($values[0] && $values[9] && $values[10] && ($values[18]>=$startDay && $values[18] <= $endDay)){
      
      if($values[19]==1){
        push(@outObserved, $values[9]);
        push(@outPredicted, $values[10]);
        push(@acc, $values[0]);
      }
      elsif($values[5]==1){
        push(@pedObserved, $values[9]);
        push(@pedPredicted, $values[10]);
      }
      else{
        push(@observed, $values[9]);
        push(@predicted, $values[10]);
      }
    }
  }

  my @x = @predicted;
  my @y = @observed;
  my @l = @acc;
  
  #Use gnuplot to graph
  say GP "set terminal png size 500,375";  
  unless ( -e "$progPath/Figures" ) { mkdir "$progPath/Figures"; }
  say GP "set output '$progPath/Figures/Regression$studyDesc.png'";
  say GP 'unset key';
  say GP "set datafile sep ','";
  say GP "set style line 1 pt 3 ";
  say GP "set key font 'Verdana,8'";
  say GP "set offset character 0,1";
  say GP "set title 'Regression Model for $studyDesc'";
  say GP "set xlabel 'Predicted DLP (mGy-cm)'";
  say GP "set ylabel 'Observed DLP (mGy-cm)'";
  say GP "set key below horizontal";
  my $outlierGraph ="";
  my $outlierGraph2 ="";
  if($outPredicted[0]){
    $outlierGraph = ",'-' using 1:2 title 'Outliers' lt 1";
    $outlierGraph2 = ", '-' using 1:2:3 notitle with labels point lt 1 font 'Verdana,8' offset character 0,1 "; 
  }
  my $pedGraph = "";
  if($pedPredicted[0]){
    $pedGraph = ", '-' using 1:2 title 'Pediatrics' lt 11";
  }
  my $normGraph = "";
  if($x[0]){
  	$normGraph = ",'-' using 1:2 title 'Normal Patients' lt 2";
  }
  
  say GP "plot x title 'Expected' linetype rgb 'blue', x + $stdDev title '3 Std Dev' linetype rgb 'red', x-$stdDev notitle linetype rgb 'red'$pedGraph$outlierGraph$normGraph$outlierGraph2";
 
  if($pedPredicted[0]){
    for my $i (0..$#pedPredicted){
      say GP "$pedPredicted[$i],$pedObserved[$i]";
    }
    say GP "eof";
  }
  if($outPredicted[0]){
    say GP "$outPredicted[0],$outObserved[0]";
    say GP "eof";
  }
  if($x[0]){
	   for my $i (0..$#x){
	    say GP "$x[$i],$y[$i]";
	  }
	  say GP "eof";
  }
  if($outPredicted[0]){
    for my $i (0..$#outPredicted){
      say GP "$outPredicted[$i],$outObserved[$i],$l[$i]"
    }
    say GP "eof";
}
close GP;
}

1;