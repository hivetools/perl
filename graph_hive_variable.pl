#! /usr/bin/perl -w
# 
# This perl script reads date, time, weight, hive temperature, ambient temperature and comments
# from the text file /home/hivetool/hive.log:
#
# 2011/11/12 13:05 + 100.4 lb 024.4 022.4
# 2011/11/12 13:15 + 100.5 lb 029.8 022.6 "Changed position of temp probe back to middle"
# 2011/11/12 13:20 + 100.5 lb 031.3 022.3
#
# and creates a graph and a html file to display the data on a web page.
#
# IMPORTANT: As of August, 2011 the perl module GD::Graph must be patched before it will
# properly display 2 y axes.  Apply adjust_axes.diff and min_range_fix.diff.
# See https://rt.cpan.org/Public/Bug/Display.html?id=62665

use strict; 
use GD::Graph::lines; 
use Time::Local;
use Date::Format;
use Sys::Hostname;
use Getopt::Long;
use CGI;

# When running on host with bad or unpatched perl modules, install your own like:
#use lib '../perl_pkgs';
#use GD::Graph::lines;

my $hostname = hostname();				#declare and initialize the variables
my $location = "Mountain City, Georgia USA - 2270 feet elevation";
my $hive_name = "$hostname Mountain City, Georgia USA - 2270 feet elevation";		#this should be all that must be changed
my $graph_name = '/var/www/htdocs/hive_graph_variable';        #and maybe the path to the web directory
my $log_name = "/home/hivetool/hive.log";

my $date=`date +"%m/%d/%Y %H:%M"`;


my (@data, @comment_line, @columns, @comments);
my $i = 0;
my ($year, $mon, $mday, $hour, $min, $sec);

my ($epoch_time, $weight, $ambient, $temperature, $temperature2, $humidity);
my ($avg_weight, $avg_ambient, $avg_temperature) = (0,0,0);
my $max_weight = -999;
my $min_weight = 440;
my $max_ambient = -40;
my $min_ambient = 120;
my $max_temperature = -40;
my $min_temperature = 120;
my ( $min_y2, $max_y2 );
my $first_date = 0;
my ($last_date, $number_of_days);
my ($last_weight, $last_ambient, $last_temperature);
my ($last_wx_temperature, $last_wx_wind_direction, $last_wx_wind_speed, $last_wx_wind_gust, $last_wx_dewpoint, $last_wx_humidity, $last_wx_pressure,  $last_wx_radiation, $last_wx_evapotranspiration, $last_wx_vapor_pressure, $last_wx_rain);
my ($last_time, $delta_time, $delta_weight, $daily_change, $manipulation_change) = (0,0,0,0,0);
my $time_threshold=300;
my $weight_threshold=1;
my $min_date;
my $max_date;
my ($min_epoch_date, $max_epoch_date);
my ($height, $width) = (0,0);
my $days = 0;
my $x_tick_number;
my ($download_data, $draw_graph);
my $raw=0;
my $filtered="Filtered";
my $midnight=0;

# get the form variables if any

my $query = new CGI;
$query->import_names('FORM');
$raw = $query->param('raw');
$midnight = $query->param('midnight');
$width = $query->param('width');
$height = $query->param('height');
$graph_name = $query->param('output');
$min_date = $query->param('begin');
$max_date = $query->param('end');
$log_name = $query->param('log');
$draw_graph    = $query->param('graph');
$download_data = $query->param('download');
#$ = $query->param('');

#get the command line variables
# these will override the form variables

Getopt::Long::Configure ("bundling");
GetOptions ('d=s'        => \$download_data,        # log file to read -l
            'download=s' => \$download_data,      # name of graph without .gif extension --output
            'g=s'        => \$draw_graph,        # log file to read -l
            'graph=s'    => \$draw_graph,      # name of graph without .gif extension --output
            'l=s'        => \$log_name,        # log file to read -l
            'log=s'      => \$log_name,        # log file to read -log
            'm'          => \$midnight,        # plot data sampled at midnight (NASA) -m
            'midnight'   => \$midnight,        # plot data sampled at midnight (NASA) --midnight
            'r'          => \$raw,             # do not apply NASA filter to the data -r
            'raw'        => \$raw,             # do not apply NASA filter to the data --raw
            'output=s'   => \$graph_name,      # name of graph without .gif extension --output
            'o=s'        => \$graph_name,      # name of graph without .gif extension -o
            'b=s'        => \$min_date,        # start date -b
            'e=s'        => \$max_date,        # end date -e
            'h=i'        => \$height,          # graph height in pixels -h
            'w=i'        => \$width            # graph width in pixels -w
            );

if (!$log_name) {$log_name="/home/hivetool/hive.log";}
if (!$graph_name) {$graph_name = "/var/www/htdocs/hive_graph_variable";}
if ($raw) {$filtered = "Raw";}

# set the parameters for read_data 
# these should come from the command line or cgi form

if ( $min_date ) {
   ($mon, $mday, $year) = split('/',$min_date);
   $sec = 0;
   $min = 0;
   $hour = 0;
   $min_epoch_date = timelocal($sec,$min,$hour,$mday,($mon-1),$year);
   }
else {
#   $min_epoch_date = 0;
#   this should come from the first line of the log file
   $sec = 0;
   $min = 0;
   $hour = 0;
   $mday = 1;
   $mon = 9;
   $year = 2011;
   $min_epoch_date = timelocal($sec,$min,$hour,$mday,($mon-1),$year);
   }

if ( $max_date ) {
   ($mon, $mday, $year) = split('/',$max_date);
   $sec = 0;
   $min = 59;
   $hour = 23;
   $max_epoch_date = timelocal($sec,$min,$hour,$mday,($mon-1),$year);
   }
else {
#   $max_epoch_date = 2147483647;
#   and this should come from the last line of the log file
    $max_epoch_date = timelocal(localtime());
   }

# get the data

open LOG, $log_name or die $!;
print STDERR "Reading data\n"; 
read_data();						#read the data into arrays, check for min/max, calc averages

# set the graph parameters

if ( $max_ambient > $max_temperature ) { $max_y2 = $max_ambient; }
else { $max_y2 = $max_temperature; }
if ( $min_ambient < $min_temperature ) { $min_y2 = $min_ambient; }
else { $min_y2 = $min_temperature; }

if ( !$height )
   {
   $height = 500;
   }

if ( !$width )
   {
   $width = $i;
   if ( $width < 1200 ) { $width = 1200; }
   if ( $width > 16000 ) { $width = 16000; }
   }

if ( !$days )
   {
   if   ( $midnight )
        { $days = $i-1; }
   else { $days = ($max_epoch_date - $min_epoch_date)/(3600*24); }
   }

#this whole section needs to be fxed 
my $cf = $width/$days;
if   ( $midnight ) 
     { 
     $x_tick_number = ($days+$days)/7;
#     $height = 300;
     }
else
     { $x_tick_number = ($number_of_days+$number_of_days)/7; }
# this needs to be fixed.


my $x_label_skip = $days/16;
if ( $x_label_skip < 2 ) { $x_label_skip = 2; }

my $graph = GD::Graph::lines->new($width,$height);           

print "width=$width height=$height  i=$i days=$days   x_label_skip=$x_label_skip x_tick_number=$x_tick_number\n";
print "graph_name=$graph_name midnight=$midnight raw=$raw filtered=$filtered\n";

$graph->set( 						#set the graph parameters
 two_axes        => 2, 
 zero_axis       => 0, 
 title           => "Hive: $hostname $location                      Weight and Temperature $filtered                          $date", 
 use_axis        => [1,2,2],
 line_width      => 3,
 x_label         => 'Time', 
 x_ticks         => 1,
 x_long_ticks    => 1,
 y_long_ticks    => 1,
 x_tick_number   => $x_tick_number,
 x_number_format => sub { time2str( "%D", $_[0] ) },
 y_tick_number   => 5, 
 x_label_skip    => int $x_label_skip,
 y1_label        => 'Weight (Pounds)', 
 y2_label        => 'Temperature (Fahrenheit)',
 y1_min_value    =>  int ($min_weight-1),
 y1_max_value    =>  int ($max_weight+1),
 x_min_value     =>  $first_date,
 x_max_value     =>  $last_date,
 y2_min_value    =>  int ($min_y2-1),
 y2_max_value    =>  int ($max_y2+1),
 y2_number_format => "%D",
 transparent     => 0, 
 boxclr          => 'lgray',
); 
 
$graph->set_legend( 'Weight', 'Ambient Temperature', 'Hive Temperature', ); 
#$graph->set_legend( 'Hive Humidity', 'Ambient Humidity', 'Hive Temperature',  'TEMPerHUM'); 
$graph->set_legend_font('/usr/lib/java/lib/fonts/LucidaSansRegular.ttf', 12);
$graph->set_title_font('/usr/lib/java/lib/fonts/LucidaSansRegular.ttf', 12);
$graph->set_x_label_font('/usr/lib/java/lib/fonts/LucidaSansRegular.ttf', 12);
$graph->set_x_axis_font('/usr/lib/java/lib/fonts/LucidaSansRegular.ttf', 12);
$graph->set_y_label_font('/usr/lib/java/lib/fonts/LucidaSansRegular.ttf', 12);
$graph->set_y_axis_font('/usr/lib/java/lib/fonts/LucidaSansRegular.ttf', 12);
$graph->set_values_font('/usr/lib/java/lib/fonts/LucidaSansRegular.ttf', 12);

print STDERR "Processing $graph_name\n"; 
$graph->plot(\@data); 
save_chart($graph, $graph_name); 
html();



sub read_data
{
while ( <LOG> ) 
      {
      if ( substr($_,0,1) ne "#" )
         {
         @comment_line = split('"', $_);			#split it apart at the first " if there is a comment
         @columns = split(' ', $_);				#split the rest of it on the spaces

         ($year, $mon, $mday) = split('/',$columns[0]);         #split the date on /
         ($hour, $min) = split(':',$columns[1]);                #split the time on :
         $sec = 0;
         $epoch_time = timelocal($sec,$min,$hour,$mday,($mon-1),$year);

#        $epoch_date = timelocal($sec,$min,$hour,$mday,($mon-1),$year);
#        $day_of_year = (localtime( $epoch_date ) )[7] + 1;

         if ( $epoch_time > $max_epoch_date) { last; }          # if date > end_date, done, so break out of loop 

         $weight = $columns[3];
         $temperature = $columns[5];
 
         if ( defined $columns[6]  ) { $ambient = $columns[6]; }
         else { $ambient = 20; }

         if ( defined $columns[18]  ) { $temperature2 = $columns[18]; }
         else { $temperature2 = 20; }
         if ( defined $columns[19]  ) { $humidity = $columns[19]; }
         else { $humidity = 50; }

         if ( $weight >= 0 and $weight < 440 and                # validity check the data 
              $temperature >= -20 and $temperature <50 and
              $ambient >= -20 and $ambient < 50 )
            {

            # Begin NASA manipulation change filter
            # This needs work - fails if missing log entries
            if ( $last_weight )
               {
               $delta_weight = $weight - $last_weight;
               $delta_time = $epoch_time - $last_time;
               if ( !$raw && abs $delta_weight > $weight_threshold && $delta_time <= $time_threshold )
                  { 
                  $manipulation_change +=  $delta_weight;
                  }
               else
                  {
                 $daily_change += $delta_weight;
                  }
               }
            else
               {  #first time through
               $daily_change = $weight;
               }
            # end NASA filter

            if ( $epoch_time >= $min_epoch_date )
               {
               if ( $first_date == 0 ) 
                  { $first_date = timelocal(0,0,0,$mday,($mon-1),$year);}  # set the start date to midnight the day before

               if (  $last_date and ($last_date ne $columns[0])            # if display midnight and date flipped
                     or !$midnight )                                       # if not display midnight (show all)
                  {
                  $data[0][$i] = $epoch_time;
                  $data[1][$i] = $daily_change;
                  $data[2][$i] = $ambient*1.8+32;
                  $data[3][$i] = $temperature*1.8+32;

		  						#keep totals for averages
                  $avg_weight += $weight;
                  $avg_ambient += $data[2][$i];
                  $avg_temperature += $data[3][$i];
          								#test for min and max
	          if ( $daily_change > $max_weight ) {$max_weight = $daily_change;}
                  if ( $daily_change < $min_weight ) {$min_weight = $daily_change;}
                  if ( $data[2][$i] > $max_ambient ) {$max_ambient = $data[2][$i];}
                  if ( $data[2][$i] < $min_ambient ) {$min_ambient = $data[2][$i];}
                  if ( $data[3][$i] > $max_temperature ) {$max_temperature = $data[3][$i];}
  	          if ( $data[3][$i] < $min_temperature ) {$min_temperature = $data[3][$i];}
      
#                  if ( $comment_line[1] ) {
#                     push @comments, scalar localtime($epoch_time) ."  ". $comment_line[1];
#                     }
                  $i++;
                  }
               $last_weight = $weight;
               $last_time = $epoch_time;
               $last_date = $columns[0]; #is this needed?

               if ( $comment_line[1] ) {
                  push @comments, "<tr><td>" . scalar localtime($epoch_time) ."</td><td>". $comment_line[1] . "</td></tr>";
                  }

               }  # endif epoch_time >= min_epoch_date

            }                       # endif $weight >= 0
       else                         # else weight or temps are out of range
            {                       # log out of range lines to error log
            print STDERR "$_\n";
            }
         }   # endif substr( $_,0,1) ne "#"
      else                          # else  substr( $_,0,1) == "#", so it is a comment line
         {                          # log commented out lines to somewhere
         print STDERR "$_\n";
         }

      }    # end while ( <LOG> )


#      $last_date = timelocal(59,59,23,$mday,($mon-1),$year);	#set the end date to midnight
      $last_date = $max_epoch_date;

      if ( $i )  {						#calculate the averages
         $avg_weight = sprintf '%6.1f', $avg_weight / $i;
         $avg_ambient = sprintf '%6.1f', $avg_ambient / $i;
         $avg_temperature = sprintf '%6.1f', $avg_temperature / $i;
         $last_weight = $data[1][$i-1];
         $last_ambient = $data[2][$i-1];
         $last_temperature = $data[3][$i-1];
         $last_wx_temperature = $columns[7];
         $last_wx_wind_direction = $columns[8];
         $last_wx_wind_speed = $columns[9];
         $last_wx_wind_gust = $columns[10];

         $last_wx_dewpoint =  $columns[11];
         $last_wx_humidity =  $columns[12];
         $last_wx_pressure =  $columns[13];
         $last_wx_radiation = $columns[14];
         $last_wx_evapotranspiration =  $columns[15];
         $last_wx_vapor_pressure =  $columns[16];
         $last_wx_rain =  $columns[17];
         }

        $number_of_days = ($last_date - $first_date)/86400;
}


sub save_chart
{
        my $chart = shift or die "Need a chart!";
        my $graph_name = shift or die "Need a name!";
        local(*OUT);

        my $ext = $chart->export_format;

        open(OUT, ">$graph_name.$ext") or 
                die "Cannot open $graph_name.$ext for write: $!";
        binmode OUT;
        print OUT $chart->gd->$ext();
        close OUT;
}


sub html {
open(HTML, ">$graph_name.html") or 
                die "Cannot open $graph_name.html for write: $!";

my $date=`date +"%m/%d/%Y %H:%M"`;
my $heading;
my $line;
						    #use string print formatted to format the variables
$max_weight = sprintf '%6.1f', $max_weight;
$min_weight = sprintf '%6.1f', $min_weight;
$max_ambient = sprintf '%6.1f', $max_ambient;
$min_ambient = sprintf '%6.1f', $min_ambient;
$max_temperature = sprintf '%6.1f', $max_temperature;
$min_temperature = sprintf '%6.1f', $min_temperature;
$last_weight = sprintf '%6.1f', $last_weight;
$last_ambient = sprintf '%6.1f', $last_ambient;
$last_temperature = sprintf '%6.1f', $last_temperature;

$last_wx_wind_direction = $columns[8];
$last_wx_wind_speed = $columns[9];
$last_wx_wind_gust = $columns[10];


$heading = <<EOT;

<table>
 <tr align=center>
  <th></th><th>Minimum&nbsp;</th><th>&nbsp;Maximum&nbsp;</th><th>&nbsp;Average&nbsp;</th><th>Last</th>
 </tr>
 <tr align=right>
  <td>Weight</td><td>$min_weight</td><td>$max_weight</td><td>$avg_weight</td><td>$last_weight</td>
 </tr>

 <tr align=right>
  <td>Hive Temp</td><td>$min_temperature</td><td>$max_temperature</td><td>$avg_temperature</td><td>$last_temperature</td>
 </tr>
 <tr align=right>
  <td>Ambient Temp</td><td>$min_ambient</td><td>$max_ambient</td><td>$avg_ambient</td><td>$last_ambient</td>
 </tr>




 <tr align=right>
  <td>Wind Dir</td><td></td><td></td><td></td><td>$last_wx_wind_direction</td>
 </tr>
 <tr align=right>
  <td>Wind Speed</td><td></td><td></td><td></td><td>$last_wx_wind_speed</td>
 </tr>
 <tr align=right>
  <td>Wind Gust</td><td></td><td></td><td></td><td>$last_wx_wind_gust</td>
 </tr>


</table>

<p>Comments:<br>
<table>
EOT

foreach $line (@comments) {
$heading .= "$line\n";
}


$heading .= <<EOT;
</table>
EOT
print HTML $heading;
close HTML;

}

1;
