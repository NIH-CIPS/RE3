
package DetectOutliers;
#Author:SJWeisenthal
#Runs an exam through the model to see if it's an outlier.

sub DetectOutlier{
    my $RegressionFeaturesFile = $_[0];
    my @predictors = @{$_[1]};
    print "Predictors in regression @predictors\n";
    my $observation = $_[2];
my @RegressionFeatures = getLatestRegressionFeatures($RegressionFeaturesFile);
#take off the last element of regression features, which is 3*SD of Residuals
my $ResidualCutOff  = pop @RegressionFeatures;
my $resStdDev = $RegressionFeatures[$#RegressionFeatures];
chomp $ResidualCutOff;
#Now coefficients are all that remains
if($predictors[3]){
        $ResidualCutOff = ($ResidualCutOff-3*$resStdDev)+2*$resStdDev;
}
my @coefficients = @RegressionFeatures; @RegressionFeatures=();

#Add a predictor that corresponds to the constant (the first coefficient will always be the constant)
#COMMENTED since just going to add one to the array that is passed to this subroutine
#unshift(@predictors,1);


my ($predictedValue,$residualValue) = PredictValueWithRegression(\@coefficients,\@predictors,$observation);
print "Prediction $predictedValue; Residual $residualValue.\n";

my $outlierFlag = AboveCutoff($residualValue,$ResidualCutOff);

if($outlierFlag == 1){
    print"High outlier.\n";
}elsif($outlierFlag == 0){
    print"Not outlier.\n";
}elsif($outlierFlag == -1){
    print"Low outlier.\n";
}
    return ($predictedValue,$residualValue,$outlierFlag);
}


sub AboveCutoff{
    #checks whether a value is above (strictly greater than) a cutoff. Takes a value and a cutoff
    #Note that it doesn't convert to absolute value
    my $value = shift;
    my $cutoff = shift;
    my $Ncutoff = -$cutoff;
    if ($value and $cutoff){
        print "Everything defined. Checking $value against $cutoff.\n";
    }else{
    warn "Value '$value' or cutoff '$cutoff' is not defined.\n";
        
    }
    my $above;
    if($value>$cutoff){
        $above = 1;
    }elsif($value<=$cutoff){
        $above = 0;
        if($value < $Ncutoff){
            $above = -1;
        }
        
        
    }
    else{
        warn "Couldn't compare values '$value' and '$cutoff'\n"
    }
    
    return $above;

}

sub PredictValueWithRegression{
    #runs regression using the coefficients and predictors in its argument and returns a predicted value and residual based on the observation in argument
    my @coefficientsToRegress = @{$_[0]};
    my @predictorsToRegress = @{$_[1]};
    my $observed = $_[2];
    print "COEFF @coefficientsToRegress\n";
    #check that the vectors with predictors and coefficients have the same dimensions before running regression
    my $DimensionsMatch = checkDimensions(\@coefficientsToRegress,\@predictorsToRegress);
    if ($DimensionsMatch == 1){
    print "The dimensions of the coefficient and predictor vectors match! Proceeding.\n";
    }elsif($DimensionsMatch == 0){
    warn "The dimensions of the coefficient and predictor vectors DON'T match! Dying.\n";
        die;
        
    }else{
        warn "Don't have a value for the dimension check. Is the script missing sub checkDimensions{}?\n";
        die;
    }
    
    my $predictionToReturn = 0;
    for my $i (0 .. $#coefficientsToRegress){
        #print "Before: $predictionToReturn\n";
        #print "$predictionToReturn + $predictorsToRegress[$i] X $coefficientsToRegress[$i]\n";
        $predictionToReturn = $predictionToReturn + $predictorsToRegress[$i]*$coefficientsToRegress[$i];
 
   
        print "After: $predictionToReturn\n";
    }
    my $residualToReturn = $observed - $predictionToReturn;
    return ($predictionToReturn,$residualToReturn);
    
    
    
    
    
    
}
sub checkDimensions{
    #checks that the dimensions of two arrays are the same
    my @a1 = @{$_[0]};
    my @a2 = @{$_[1]};
        
    my $Size1 = @a1;
    my $Size2 = @a2;
    print "Checking dimensions of:\n($Size1)@a1\n($Size2)@a2\n";
    my $DimensionSwitch;
    if ($Size1 == $Size2){
        $DimensionSwitch = 1;
    }else{
        $DimensionSwitch = 0;
    }
    return $DimensionSwitch;
}

sub getLatestRegressionFeatures{
    #gets the LAST coefficients from the coefficients file (since it's going to be continually updated, want last, but also want to keep a log)

my $coefficientsLog = shift;
print "Reading coefficents in last line of $coefficientsLog.\n";
open(CO,"<$coefficientsLog") or die "Can't open $coefficientsLog $!";
my @coefficientsToGet = <CO>;
    close CO;
    my $coefSize =@coefficientsToGet;
    print "There are $coefSize versions of the coefficients.\n";
    print "Latest coefficients:$coefficientsToGet[$coefSize-1]\n";
    checkCoefficients(\@coefficientsToGet);
    my @coefficientsArray = split(',',$coefficientsToGet[$coefSize-1]);
    
    print "Returning @coefficientsArray\n";
    return @coefficientsArray;
  

        }
    



sub checkCoefficients{
    #Checks that the number of coefficients are the same in each line. If there's some weird bug in the program that prints the coefficients, hopefully this will catch it
    print "Checking that the number of coefficients in each line is the same...\n";
    my @coefficientsToCheck = @{$_[0]};
    my @versionSizes;
    for my $i (0 .. $#coefficientsToCheck){
        my @version =split (',',$coefficientsToCheck[$i]);
        my $sizeCoefVersion= @version;
        #print "size $sizeCoefversion\n";
        push(@versionSizes,$sizeCoefVersion);
    }
    for my $i (1 .. $#versionSizes){
        if($versionSizes[$i-1]==$versionSizes[$i]){
            #print "\tLine $i looks OK.\n";
        }else{
        warn "\tCoefficients in line ",($i-1)," are NOT the same as those in line $i of $coefficientsLog! You should check this.\n";
        }
        }
    }
    

1;