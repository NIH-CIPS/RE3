

package MakeRegression;
#written by SWeisenthal
#runs a regression that is robust to outliers

sub Outlier_Robust_Regress {

use strict;
use warnings;
use Data::Dumper;
use lib 'C:/Perl64/site/lib';
my $datafile = $_[0];
my $NoValueFile =$_[1];
my $FPI = $_[2];
my $DVI=$_[3];
my $RegFeatures = $_[4];
my $pedCheck = $_[5];
my $femCheck = $_[6];

my ($Data_ref,$header) = strip_before_loop($datafile);
my @Data=@$Data_ref;
chomp @Data;
my @labels = split(',',$header);


#Clears elts of @Data that have NoValue as a value (don't want to run a regression on strings)
@Data = clearNoValues(\@Data,$NoValueFile);

print "PEDS: $pedCheck";

my $sampleSize0=@Data;
my @sampleSizes = ($sampleSize0);

for (my $i=1; $i <= 10000; $i++) {
#iteratively run regression, remove outliers, and rerun regression until N is constant.  

    @Data = &RunIteration(\@Data,\@labels,$FPI,$DVI,$RegFeatures,$pedCheck,$femCheck);
    my $Nsam = @Data;
    
    push(@sampleSizes,$Nsam);
    print "Sample sizes array @sampleSizes\n";
    if($sampleSizes[$i]==$sampleSizes[$i-1]){
        print "From $sampleSize0, Sample size (N=$sampleSizes[$i-1])constant. Exiting loop.\n";
        last;
    }else{
        print "From $sampleSize0, $sampleSizes[$i] ne $sampleSizes[$i-1]. Iterating...\n";
    }
}




sub RunIteration{




    my @PEDS;
    my @FEM;
    my @AGE;
    my @SL;
    my @SBV;
    my @Dw;
    my @DLP;

    my @Data = @{$_[0]};
    my @saveData = @{$_[0]};
    my @labels = @{$_[1]};
    my $FPI =$_[2];
    my $DVI = $_[3];
    my $RegressionFeatures = $_[4];
    my $pedsCheck = $_[5];
    my $femCheck = $_[6];
    foreach (@Data) {
        #print "$_\n";
        my @values = split( ',', $_ );
        chomp @values;
        #Remember one means that all are the same, so that it shouldn't be included
        
        push(@PEDS,$values[$FPI]);
        
        if(!$femCheck){
            push(@FEM,$values[$FPI+1]);
        }
        if(!$pedsCheck){
            push(@AGE,$values[$FPI+2]);
        }
        push(@SL,$values[$FPI+3]);
        push(@SBV,$values[$FPI+4]);
        push(@Dw,$values[$FPI+5]);
        push(@DLP,$values[$DVI]);
        
    }

    use Statistics::Regression;
    use Statistics::Basic qw(:all);
    my $reg='';
    
    # Create regression object. Changes based on whether a column consists of the same values, and if it does, exlcudes that in the regression. Also if peds or fem check != 0, then need to exclude that
    #as it means that the respective column is entirely 0, and would crash the program
    
    if(!$pedsCheck && !$femCheck){
        $reg = Statistics::Regression->new( "sample regression", ["Constant", "$labels[$FPI]", "$labels[$FPI+1]", "$labels[$FPI+2]", "$labels[$FPI+3]", "$labels[$FPI+4]", "$labels[$FPI+5]"] );
        for my $i (0 .. $#DLP){
            $reg->include( $DLP[$i], [ 1, $PEDS[$i], $FEM[$i], $AGE[$i],$SL[$i],$SBV[$i],$Dw[$i] ] );
        }
    }
    elsif(!$pedsCheck && $femCheck){
        $reg = Statistics::Regression->new( "sample regression", ["Constant", "$labels[$FPI]", "$labels[$FPI+2]", "$labels[$FPI+3]", "$labels[$FPI+4]", "$labels[$FPI+5]"] );
        for my $i (0 .. $#DLP){
            $reg->include( $DLP[$i], [ 1, $PEDS[$i], $AGE[$i],$SL[$i],$SBV[$i],$Dw[$i] ] );
        }
    }
    elsif($pedsCheck && !$femCheck){
        $reg = Statistics::Regression->new( "sample regression", ["Constant", "$labels[$FPI]", "$labels[$FPI+1]", "$labels[$FPI+3]", "$labels[$FPI+4]", "$labels[$FPI+5]"] );
        for my $i (0 .. $#DLP){
            $reg->include( $DLP[$i], [ 1, $PEDS[$i], $FEM[$i],$SL[$i],$SBV[$i],$Dw[$i] ] );
        }
    }
    else{
        $reg = Statistics::Regression->new( "sample regression", ["Constant", "$labels[$FPI]", "$labels[$FPI+3]", "$labels[$FPI+4]", "$labels[$FPI+5]"] );
        for my $i (0 .. $#DLP){
            $reg->include( $DLP[$i], [ 1, $PEDS[$i],$SL[$i],$SBV[$i],$Dw[$i] ] );
        }
    }
        
    $reg->print();

    my @theta  = $reg->theta();

    my @residuals;

    #Goes through the data and calculates the predicted values based on the regression model
    foreach (@saveData) {
        my @values = split( ',', $_ );
        #print "$_\n";
        my $prediction = 0;
        if(!$pedsCheck && !$femCheck){
        
            $prediction =
            1*$theta[0]+
            $values[$FPI]*$theta[1]+
            $values[$FPI+1]*$theta[2]+
            $values[$FPI+2]*$theta[3]+
            $values[$FPI+3]*$theta[4]+
            $values[$FPI+4]*$theta[5]+
            $values[$FPI+5]*$theta[6];
            
        }
        elsif(!$pedsCheck && $femCheck){
            $prediction =
            1*$theta[0]+
            $values[$FPI]*$theta[1]+
            $values[$FPI+2]*$theta[2]+
            $values[$FPI+3]*$theta[3]+
            $values[$FPI+4]*$theta[4]+
            $values[$FPI+5]*$theta[5];
            
        }
         elsif($pedsCheck && !$femCheck){
            $prediction =
            1*$theta[0]+
            $values[$FPI]*$theta[1]+
            $values[$FPI+1]*$theta[2]+
            $values[$FPI+3]*$theta[3]+
            $values[$FPI+4]*$theta[4]+
            $values[$FPI+5]*$theta[5];
            
        }
        else{
         $prediction =
            1*$theta[0]+
            $values[$FPI]*$theta[1]+
            $values[$FPI+3]*$theta[2]+
            $values[$FPI+4]*$theta[3]+
            $values[$FPI+5]*$theta[4];
        }
        
        my $residual = $values[$DVI]-$prediction;
        push(@residuals,$residual);
               
    }
    my $meanRes=mean(@residuals);
    my $stddevRes=stddev(@residuals);
    my $ThreeStddevRes=3*$stddevRes;
      
    #stores coefficients and 3SD for future use
    open(RF,">>$RegressionFeatures") or die "Can't open $RegressionFeatures $!\n";
    if(!$pedsCheck && !$femCheck){
        print RF join(',',@theta);
    }
    elsif(!$pedsCheck && $femCheck){
        print RF "$theta[0],$theta[1],0,$theta[2],$theta[3],$theta[4],$theta[5]";
    }
    elsif($pedsCheck && !$femCheck){
        print RF "$theta[0],$theta[1],$theta[2],0,$theta[3],$theta[4],$theta[5]";
    }
    else{
        print RF "$theta[0],$theta[1],0,0,$theta[2],$theta[3],$theta[4]";
    }
    print RF ",$ThreeStddevRes\n";
    close RF;

    my $ResCut = $meanRes+$ThreeStddevRes;
    print "mean:$meanRes;stddev=$stddevRes;3 stddev cutoff: $ResCut.\n";
    my @cuts;

    for my $i (0 .. $#Data){

        if(abs($residuals[$i])<$ResCut){
            #print "$Data[$i] kept since residual $residuals[$i] < $ResCut\n";
            #do nothing...
        }else{
            print "Removed '$Data[$i]' with residual $residuals[$i]\n";
            push(@cuts,$i);
        }
    }
    print "cuts: @cuts\n";

    my %cuts = map { $_ => 1 } @cuts;
    my @keeps = grep !$cuts{$_}, 0..$#Data;
    @Data = @Data[@keeps];

    return @Data;
}




}

sub strip_before_loop {
    #skip a header and read in a file
    my $file = shift;
    
    open (my $fh, $file);

    my $header = <$fh>;
    my @fileData;
    while(<$fh>) {
        my $line = $_;
        push(@fileData,$line);
    }

    return (\@fileData,$header);
}
sub clearNoValues {
#This clears all values that contain the word NoValue, NoAx, or NoIm
my $NoValueFile = $_[1];
open(NV, ">>$NoValueFile") or die "$! can't open $NoValueFile\n";
my @Data = @{$_[0]};
chomp @Data;
my $old = @Data;
my @NoValues;
for my $i (0 .. $#Data){
    my @values = split( ',', $Data[$i] );
    foreach my $value (@values){
        if ($value eq "NoValue" or $value eq "NoAx" or $value eq "NoIm" or $value eq ""){
            push(@NoValues,$i);
            print NV "$Data[$i]\n";
            }else{
            #print "$value and NoValue don't match\n";                
                }
        }
    
    }

my %NoValues = map { $_ => 1 } @NoValues;
my @keeps = grep !$NoValues{$_}, 0..$#Data;
@Data = @Data[@keeps];

my $new = @Data;

print "Data file checked for fields that contain 'NoValue' before running regression. Data array size reduction from said check: $old to $new.\n";
print "Recorded the removed lines in $NoValueFile.\n";
return @Data;
close NV;

}
1;