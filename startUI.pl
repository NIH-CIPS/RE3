#!C:/usr/bin/env perl
#Sets up a local server and starts the web UI on it.
#Created by WCK
use strict;
use warnings;
use Mojo::Server::Morbo;
my $pid = fork;
if($pid){
  print "started the child process";
  my $morbo = Mojo::Server::Morbo->new;
  $morbo->run('C:/RE3/RE3WebUI.pl');
}
elsif($pid ==0){
  
  system("start", "http://127.0.0.1:3000");
  exit 0;
}