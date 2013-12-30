#! /usr/bin/perl -w
use strict; 
use Time::Local;
use CGI;
use feature "switch";  # NOTE: perl 5.10 is required to use the switch construct

my $display_comments = 0;
my $display_graph = 0;

print <<END;
Content-Type: text/html; charset=iso-8859-1

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN">
END

my $query = new CGI;
$query->import_names('FORM');

my $min_date = $query->param('start_date');
my $max_date = $query->param('end_date');
my $format = $query->param('format');
my $height = $query->param('height');
my $width = $query->param('width');

if ( $query->param('comments') eq "include" ) { $display_comments = 1; }
if ( $query->param('graph') eq "include" ) { $display_graph = 1; }
my $weight_threshold= $query->param('weight_threshold');
my $print_detail=$query->param('print_detail');
my $time_threshold=300;
my $print_wx=1;


my ($year, $mon, $mday, $hour, $min, $sec);
my $print_summary;
my ($min_epoch_date,$max_epoch_date,$epoch_date);
my (@comment,@columns);
my ($last_date, $last_weight,$weight,$daily_change,$comments);
my ($delta_weight, $delta_time);
my ($last_epoch_date,$manipulation_change);
my $day_of_year;

if ( $print_detail ) { $print_summary = 0; }
else { $print_summary = 1; }

if ( $min_date ) {
   ($mon, $mday, $year) = split('/',$min_date);
   $sec = 0;
   $min = 0;
   $hour = 0;
   $min_epoch_date = timelocal($sec,$min,$hour,$mday,($mon-1),$year);
   }
else {
   $min_epoch_date = 0;
   }

if ( $max_date ) {
   ($mon, $mday, $year) = split('/',$max_date);
   $sec = 0;
   $min = 59;
   $hour = 23;
   $max_epoch_date = timelocal($sec,$min,$hour,$mday,($mon-1),$year);
   }
else {
   $max_epoch_date = 2147483647;
   }

open LOG, "/home/hivetool/hive.log" or die $!;

given($format) {
 when ("raw") 
      {
      print "date,time,weight,temp,ambient";
      if  ( $print_wx ) {
              print ",wx_Temp,wx_Wind_Direction,wx_Wind_Speed,wx_Wind_Gusts,wx_Dewpoint,wx_Humidity,wx_Sea_Level_Pressure,wx_Radiation,wx_Evapotranspiration,wx_Vapor_Pressure,wx_Daily_Rain";
              }
      print "<br>\r\n";
      while ( <LOG> ) 
        {

       if ( substr( $_,0,1) ne "#" )
        {
        @comment = split('"', $_);
        @columns = split(' ', $_);

        ($year, $mon, $mday) = split('/',$columns[0]);

        ($hour, $min) = split(':',$columns[1]);
        $sec = 0;

        $epoch_date = timelocal($sec,$min,$hour,$mday,($mon-1),$year);

        if ( $epoch_date > $max_epoch_date) { last; }   # if date > end_date, done, so break out of loop 
        if ( $epoch_date >= $min_epoch_date )  {
           print "$columns[0],$columns[1],$columns[3],$columns[5],$columns[6]";
           if ( $print_wx ) {
              print ",$columns[7],$columns[8],$columns[9],$columns[10],$columns[11],$columns[12],$columns[13],$columns[14],$columns[15],$columns[16],$columns[17]";
              }
           if ( $comment[1] && $display_comments ) {
                print ",\"$comment[1]\"";
                }
            print "<br>\r\n"; 
           }
        }  # endif substr
        }  # end while
      }

 when ("nasa") 
      {
      $manipulation_change = 0;
      if ( $print_summary ) {
         print "\"Date\",\"Day of Year\",\"Weight\",\"Manipulation Change,\"Daily Change\"<br>\r\n";
         }
      if ( $print_detail ) {
         print "\"Date\",\"Day of Year\",\"Time\",\"Weight\",\"Manipulation Change,\"Delta Weight\",\"Daily Change\"<br>\r\n";
         }

      while ( <LOG> ) 
        {

       if ( substr( $_,0,1) ne "#" )
        {

        @comment = split('"', $_);
        @columns = split(' ', $_);

        ($year, $mon, $mday) = split('/',$columns[0]);

        ($hour, $min) = split(':',$columns[1]);
        $sec = 0;

        $epoch_date = timelocal($sec,$min,$hour,$mday,($mon-1),$year);

        if ( $epoch_date > $max_epoch_date) { last; }   # if date > end_date, done, so break out of loop 
        if ( $epoch_date >= $min_epoch_date ) {

           if ( $last_date && $last_date ne $columns[0] ) {

              if ( $print_summary ) {
                $day_of_year = (localtime( $last_epoch_date ) )[7] + 1;  # first day of year is 1, not zero
                printf '%s,%d,%6.1f,%6.1f,%6.1f', $last_date,$day_of_year,$weight,$manipulation_change,$daily_change;
                 if ( $comments && $display_comments ) {
                    chop($comments);
                    print ",\"$comments\"";
                    }
                 print "<br>\r\n"; 
                 }

               $daily_change = 0;
               $comments = "";
              }

           if ( $comment[1] && $display_comments ) {
              $comments = $comments . "$comment[1] ";
              }

           $weight = $columns[3];

           if ( $last_weight ) {
              $delta_weight = $weight - $last_weight;
              $delta_time = $epoch_date - $last_epoch_date;
              if ( abs $delta_weight > $weight_threshold && $delta_time <= $time_threshold )
                 { 
                 $manipulation_change +=  $delta_weight;
                 }
              else
                 {
                 $daily_change += $delta_weight;
                 }
              if ( $print_detail ) {
                 $day_of_year = (localtime( $epoch_date ) )[7] + 1;
                 printf '%s,%d,%s,%6.1f,%6.1f,%6.1f,%6.1f', $columns[0],$day_of_year,$columns[1],$weight,$manipulation_change,$delta_weight,$daily_change;
                 if ( $comment[1] && $display_comments ) {
                    print ",\"$comment[1]\"";
                    }
                 print "<br>\r\n"; 
                 }
              }

           $last_weight = $weight;
           $last_epoch_date = $epoch_date;
           $last_date = $columns[0];
           }
         } # endif
        }

        $day_of_year = (localtime( $epoch_date ) )[7] + 1;      
        if ( $print_summary ) {
           printf '%s,%d,%6.1f,%6.1f,%6.1f', $columns[0],$day_of_year,$weight,$manipulation_change,$daily_change;
           if ( $comments && $display_comments ) {
              chop($comments);
              print ",\"$comments\"";
              }
           print "<br>\r\n"; 
           }
      }
 }



1; 
