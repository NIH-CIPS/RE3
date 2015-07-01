		Radiation Exposure Extraction Engine (RE3)

		A NIH Clinical Image Processing Service (CIPS) Project

		Authors: 	Will Kovacs (william.kovacs@mail.nih.gov, 
						wckovacs@comcast.net)
				Sam Weisenthal (samweisenthal@gmail.com)
				Jack Yao (jyao@mail.nih.gov)

Please note: This software is provided as is and without warranty or guarantee of any 
kind. It is for research purposes only and not to be used for patient care. While we are
interested in learning about bugs in the software, no software support of any kind will
be provided. If it is used in research, a citation to the publication* is required in 
any publications of presentations.

*Citation forthcoming

(1) Description
---------------

RE3 is an open-source engine coded in Perl that connects with an institution's PACS 
system in order to obtain dose relevant information based on DICOM header information, 
so there is no need to rely on manual or optical character recognition of dose pages, 
and works if structured reports are not available. It is able to take this information 
and organize it into files, to increase its availability. It also has the capability to
create a patient-specific regression model based on the data to predict a typical exam 
of specific study descriptions at that institution. If it comes across an exam whose DLP
is higher than it should be, that exam is flagged and will be reported in an automated 
dose report.

(2) Requirements
--------------------

-The Windows 7 OS: Due to implementation of running executables, this OS is needed


-perl: An interpreter for running the Perl scripts. Tested on v5.16.3. 
		See https://www.perl.org/

-Perl Modules: Split into the following categories:
	-Those included in Perl distributions:
		File::Find, File::Copy, Data::Dumper, Time::HiRes, File::Path, POSIX, 
		List::Util, and Encode
	-Those that can be found on CPAN (www.cpan.org):
		XML::Simple, Win32::OLE, Win32::Job, List::MoreUtils, PDF::API2, 
		PDF::Table, Math::Round, File::Slurp, Statistics::Regression, 
		Statistics::Basic, DBI, DBD::Chart, Math::Sigfigs, 
		Statistics::Descriptive
	-Those included with this code:
		MakeRegression, RE3reportFiguregenerator, DetectOutliers	
	-Optional if web UI is desired: 
		Mojolicious::Lite and Mojo::Server::Morbo


-Dicom Toolkit (DCMTK): A collection of libraries and applications that implement parts
			of the DICOM standard.
			Three applications are needed from this: findscu.exe, movescu.exe, and dcmdump.exe
			See http://dicom.offis.de/dcmtk.php.en


-Computer with an AE Title (requiring a static IP), so that DCMTK applications can
	connect to the PACS



(3) Package Files
-----------------

_projects_NIH_FatMeasurement.exe	Program that calculates the body volume of a CT
						series
1_1_correspondencer.pl			Script that removes remaining duplicates and 
						organizes the data into final results
config.xml				The configuration file
DetectOutliers.pm			Runs an exam through the regression model to see
						if it's an outlier
kfactors.txt				K factors to convert DLP to effective dose based
						on study description Dicom tag
					Example from our own institution, may need to 
						change for new hospital
kfactorsBody.txt			K factors to convert DLP to effective dose based
						on the body region Dicom tag
					Example from our own institution, may need to 
						change for new hospital
MakeRegression.pm			Creates a regression model that is robust to 
						outliers
RE3_Main.pl				The main program that will be run.
RE3reportFigureGenerator.pm		Creates figures based on the dose data.
RE3WebUI.pl				A web UI that allows for configuration of RE3 
						for a single run
ReadMe.txt				Helpful file
StartUI.pl				Script to set up a local server and starts the 
						web UI


(4) Set-Up
----------------


Once the files and perl modules are downloaded and moved to the same directory, the 
configuration file needs to be updated. Information about the specific configurations 
can be found in config.xml. Briefly, the necessary fields to update include:


program_path	
perl_path	
CAD_Path	
k_factor_file	
k_factor_body_file	
aec_title/ip/port
aet_title/ip/port


The remaining fields are preferences for how RE3 should run.


Important Files to Update:

	-kfactors.txt and kfactorsBody.txt - should be updated to reflect the hospital's
		own study descriptions and body part examined Dicom tags. When creating 
		this file, it should be noted that RE3 removes white spaces and 
		non-alphanumeric characters from the study description. Also, it looks 
		for matching phrases, so in the example below, if Abd is the first one 
		of the file, ChestAbdPelvis would still use those k factors because Abd
		is found in that study description. 


		An example line should be as follows:

		bodypart/StudyDescription, k for adult,age 10-15,age 5-10,age 1-5,for <1
		Abd,.015,.030,.040,.060,.098


	-RegressionFeaturesDefault.csv - Contains the coefficients for a default
		regression model to be used if RE3 encounters a new study description.

 
	-Exceptions.txt - Each line specifies changing a study description to a 
			different one. For instance, the line "CTAbdomenMultiphase, 
			CTAbdomenTriphase" changes all instances of the multiphase to 
			triphase. Useful for separating multiphase exams. Can be left 
			blank.
	-MissingAcq.txt - Each line specifies a protocol name that does not include all
			of the series on the PACS. When a protocol is specified, a 
			message will appear on the dose report of this problem. Can be 
			left blank.


Overscan Equations:

	Located within the subroutine get_header_data are equations that calculate the 
	overscan DLP values for the different scanners. Since this is scanner specific,
	we recommend calculating your own regression models for your scanners and
	replacing what we have in there.


(5) Usage
---------


There are two methods to run RE3:
   a) On the command line:
	The settings can be either specified in the configuration file or passed
	as arguments. If only settings from the config file is desired, the 
	follwing should be run:

		perl "path to RE3_Main.pl" "path to config file"
		e.g. perl C:/RE3/RE3_Main.pl C:/RE3/config.xml

	Arguments that can be appended to the end of this command are as follows:

	-nospec			Not running for a specific exam (overrides config)
	-p			Look at only pediatric patients
	-public			Put dose report in a "public" folder, used by the Web UI
	-r "date"		Creating a report from pre-existing data for the date
				Format date as YYYYMMDD-YYYYMMDD.
	-prot "protocol"	Running for only a specific protocol
	-retro "date"		Run retrospectively for the specified date. 
				Format date as YYYYMMDD-YYYYMMDD.
	-prospective		Running RE3 prospectively
	-fd			Make figures daily
	-fw			Make figures weekly
	-night			Sets RE3 to run nightly
	-day			Sets RE3 to run during the day
	-exam "Accession #"	Runs for the specified study
	-ud			Updating both the results and the regression model
	-nud			Not updating the results nor the regression model
			

   b) Using the Web UI:
	-To start the UI, from the command line, go to the directory with the files, 
	then type
		perl startUI.pl
	-This should open the Web UI, from which you will have to select the location.
	of the configuration file, and the types of options that you would like to run
	the program in.
	-Press "Run RE3".
	-After RE3 is done running, you should be redirected to the dose report.
	-To stop the program, hit Quit on the main page of the options menu.
	-This method is particularly helpful to create outlier dose reports for a
	variety of date ranges.


The final data will be split into two main files: 
	one-to-one_series.csv	Contains series level dose information
	one-to-one_study.csv	Contains study level dose information


Other areas of interest:
	CalcResultsLog.csv	Contains all dose information before tge secibd filter 
				of duplicates. Helpful to see scans if a scanner doesn't
				provide dose information
	The Model directory	Contains all the data for the regression models, as well
				as the models themselves
	The Figures directory	Contains the created figures
	The reports directory	Contains the created dose reports
	The logs directory	Contains the Configurations directory, saving old copies
				of the config page, among other temporary logs

-----------------
End of README.txt
-----------------



