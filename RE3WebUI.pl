#!/usr/bin/perl
use strict;
use warnings;

#A web UI that allows the user to select certain settings and run RE3, complete with the dose report appearing at the end.
#Created by WCK

use Mojolicious::Lite;


#For the "home page" Tells to create what is first seen.

get '/' => sub {
  my $c = shift;
  $c->render('first');
}=>'first';


#Creates a url for a page that doesn't work.

get '/failure' => sub{
  my $c=shift;
  $c->render('failure');
};


post '/quit'=> sub{
  my $c = shift;
  $c->redirect_to('http://google.com');
  $c->tx->on( finish => sub { exit } );
};

#Takes care of setting up a command for RE3

post '/results' => sub {
  my $c = shift;
  
  
  
  my $report = $c->param('report');
  my $retro = $c->param('retro');
  my $rstart = $c->param('rstart');
  my $rend = $c->param('rend');
  my $night = $c->param('nightly');
  my @options =$c->param('options');  
  my $protocol =$c->param('protocol');
  my $config = $c->param('config');
  my $retroStartDate = $c->param('retroStartDate');
  my $retroEndDate = $c->param('retroEndDate');
  my $updateData=$c->param('updateData');
  my $specific=$c->param('exam');
  my $prog_path='';
  
  print ("The config that is being selected is $config while the report is being $report\n");
  
  open(my $Con, "<",$config);
  
  while(<$Con>){
	if($_ =~ m/<program_path>/g){
	  print ("In here!\n");
	  ($prog_path) = $_ =~ /h>(.*)<\//;
	}
  }
	close $Con;
 print "Config: $prog_path\n";
 
  # Adds tags that are self-explnatory. Public is to send the generated report to the public folder. Maybe add another tag to get the directory of the public folder?
 
 print "The ending date is $rend\n";
 my $tags =" -public";
  if($report eq "yes"){
    if($rstart){
      $tags .= " -nospec -r $rstart";
    }
    else{
      $tags .= " -r 00000000";
    }
    if($rend){
      $tags .= "-$rend";
    }   
  }
  elsif($report eq "no"){
	  if($retro eq "retrospective"){
		$tags.=" -retro $retroStartDate";
		if($retroEndDate){
                  $tags.="-$retroEndDate";
		}
	  }
	  else{
	    $tags .= " -prospective";
	  }
   }
  if($night && $night eq "yes"){
    $tags .= " -night";
  }
  if($specific&& !$rstart){
    $tags .= " -exam $specific";
  }
  
  if($updateData && $updateData eq "yes"){
    $tags .= " -ud";
  }
  elsif($updateData eq "no"){
    $tags .= " -nud";
  }
  for(@options){
    if($_ eq "peds"){
      $tags .=" -p";
    }
  }
  if($protocol){
    $tags .= " -prot $protocol";
  }
my $cmd =
"start cmd.exe /c perl $prog_path/RE3_checkDupe_2.pl $prog_path/config.xml $tags";
            print
              "\tCalling RE3 with command\n\t$cmd\n";
            `$cmd`;
   print "Finished creating report?\n";
   my $image="";
   my $url = app->home->rel_dir('/public');
   print ("The directory is: $url\n");
   opendir(DIR,$url) or die "$url can't open because $!\n";
   while(readdir(DIR)){
     if($_ ne "." && $_ ne ".."){
       $image = $_;
     }
   }
   close DIR;
   print "The image is: $image\n";
   if($image eq""){
     $image = "failure";
   }
   $c->render('results', image=> $image);
};



app->start;
#Setting up the html code for the web UI
__DATA__


@@ results.html.ep
<!DOCTYPE html>
<html>
<!-- For the results page, immediately redirects to the url for the report to be seen (should be in public folder so that this works)-->
<head><meta http-equiv="refresh" content="0; url=<%=(url_for $image)->to_abs%>" /></head>
<body>
<h1>  </h1>
<h2>Something went wrong wtih the redirect </h2>
<h3>Loading...</h3>
	
</body>
</html>

@@ failure.html.ep
<!DOCTYPE html>
<html>
<body>
<h1>Something went wrong. Please check the settings and try again.<h1>
</body>
</html>


@@ first.html.ep
<!DOCTYPE html>
<html>
<head><title>RE3</title>
<style>
	h1{
	  color:green;
	  font-family:verdana;
	  font-size:160%;
	}
	form{
	  margin:auto;
	  position:relative;
	  border-radius: 10px;
	  padding:10px;	  
	}
	input{
	  float:center;
	  width: 100px;
	  display:run-in;
	  border:1px solid #999;
	  height 25 px;
	}
	fieldset{
	  width:500 px;
	}
</style>
</head>
<body>
  <h1 style="color:green">Radiation Exposure Extraction Engine Options Menu</h1>
  <script type="text/javascript"> 

		function runningCheck(){
		  if(document.getElementById('reportCheck').checked){
			document.getElementById('YesRun').style.display='none';
			document.getElementById('reportDate').style.display='block';
		  }
		  else{
			document.getElementById('YesRun').style.display='block';
			document.getElementById('reportDate').style.display='none';
		  }
		}
		function quit(){
                    document.getElementById('forming').action="<%=url_for('quit')->to_abs%>";
		}

</script> 
  <p>Specify the options that you would like to run</p>
	<form action="<%=url_for('results')->to_abs%>" method = "post" id="forming">
		<input type="file" name = "config" style = "width:200px"/> Config File <br><br>
		<h3>RE3 Running Type</h2>
		<input type="radio" name="report" value="yes" id="reportCheck" onclick="javascript:runningCheck();">Only Report		
		<input type="radio" name="report" value="no" onclick="javascript:runningCheck();">Run cases<br><br>
		<div id="reportDate" style="display:none">	
			Report Start Date: <input type="text" name="rstart"/> 
			End Date: <input type="text" name="rend"/> (Use style YYYYMMDD)<br><br>
		</div>
		Specific Accession number?: <input type="text" name="exam"/><br><br>
		<fieldset id="YesRun" style="display:none">
			<h3 style="padding: 0px">Running Options</h3>
			<input type="radio" name="retro" value="retrospective"/>Retrospective
			<input type="radio" name="retro" value="prospective"/>Prospective<br>
			Retrospective Start Date: <input type="text" name="retroStartDate"/>
			End Date: <input type="text" name="retroEndDate"/><br>
			<h4>Nightly</h4>
			<input type="radio" name="nightly" value="yes"/>Yes
			<input type="radio" name="nightly" value="no"/>No<br><br>
			<h4>Update Data</h4>
			<input type="radio" name="updateData" value="yes">Yes
			<input type="radio" name="updateData" value="no">No
		</fieldset>
		<h3>Reporting Options</h3>	
		<input type="checkbox" name="options" value="peds"/>Pediatric Only<br>
		Specific Protocol: <input type="text" name="protocol"/><br><br>
		<input type="submit" value="Run RE3"/> <br>
		<input type="submit" value="Quit" onclick ="javascript:quit();">
		
	</form>	
</body>
</html>


