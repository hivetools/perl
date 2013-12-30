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
# 0.4 added NASA manipulation filter
#
# 0.5 fixed y2_min/y2_max bug, ignore hive.log lines starting with #, and lines with weight, temp, ambient out of range.

use strict; 
use GD::Graph::lines; 
use GD::Graph::bars;
use Time::Local;
use Date::Format;
use Sys::Hostname;

my $hostname = hostname();				#declare and initialize the variables
my $location = "Mountain City, Georgia USA";
my $altitude = 2700;
my $date=`date +"%m/%d/%Y %H:%M %Z"`;

my $hive_name = "$hostname Mountain City, Georgia USA - $altitude feet elevation Filtered";		#this should be all that must be changed
my $graph_name = '/var/www/htdocs/hive_graph'; 		#and maybe the path to the web directory
my $graph = GD::Graph::lines->new(1200,500);            #change the size of the graph here
#my $graph_rain = GD::Graph::bars->new(1165,100);
my $graph_rain = GD::Graph::lines->new(1165,100);

my (@data, @rain, @comment_line, @columns, @comments);
my $i = 0;
my ($year, $mon, $mday, $hour, $min, $sec);

my ($time, $weight, $ambient, $temperature);
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
my ($last_rain_total, $rain_total) = (0,0);

print STDERR "Reading data\n"; 
read_data();						#read the data into arrays, check for min/max, calc averages

if ( $max_ambient > $max_temperature ) { $max_y2 = $max_ambient; }
else { $max_y2 = $max_temperature; }
if ( $min_ambient < $min_temperature ) { $min_y2 = $min_ambient; }
else { $min_y2 = $min_temperature; }



 $graph->set( 						#set the graph parameters
 two_axes        => 2, 
 zero_axis       => 0, 
 title           => "$hostname $location - $altitude feet elev.                     Hive Weight and Temperature                            $date", 
 use_axis        => [1,2,2],
 line_width      => 3,
 x_label         => 'Time', 
 x_ticks         => 1,
 x_long_ticks    => 1,
 y_long_ticks    => 1,
 x_tick_number   => $number_of_days+$number_of_days,
 x_number_format => sub { time2str( "%D", $_[0] ) },
 x_label_skip    =>   2,
 y1_label        => 'Weight (Pounds)', 
 y2_label        => 'Temperature (Fahrenheit)',
 y1_min_value    =>  int $min_weight,
 y1_max_value    =>  int ($max_weight+1),
 x_min_value     =>  $first_date,
 x_max_value     =>  $last_date,
 y2_min_value    =>  int $min_y2,
 y2_max_value    =>  int ($max_y2+1),
 transparent     => 0, 
 boxclr          => 'lgray',
); 
 
$graph->set_legend( 'Weight', 'Ambient Temperature', 'Hive Temperature', ); 
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



$graph_name = '/var/www/htdocs/rain_graph';  


 $graph_rain->set(
 title           => "$hostname $location - $altitude feet elev.                              Rain                                          $date",
 x_label         => 'Time',
 x_tick_number   => $number_of_days+$number_of_days,
 x_number_format => sub { time2str( "%D", $_[0] ) },
 x_min_value     =>  $first_date,
 x_max_value     =>  $last_date,
 y_label => 'Rain (inches)',
 x_label_skip    =>   2,
 overwrite => 1,
# bar_width => 1,
 transparent => 0,
 );


#$graph_rain->set(                                           #set the graph parameters
# title           => "$hostname $location - $altitude feet elev.                              Rain                                          $date",
# x_label         => 'Time',
# x_tick_number   => $number_of_days+$number_of_days,
# x_number_format => sub { time2str( "%D", $_[0] ) },
# x_label_skip    =>   2,
# y_label        => 'Rain (inches)',
# x_min_value     =>  $first_date,
# x_max_value     =>  $last_date,
# transparent     => 0,
# boxclr          => 'lgray',
#);

$graph->set_legend( 'Rain (inches', );
$graph->set_legend_font('/usr/lib/java/lib/fonts/LucidaSansRegular.ttf', 12);
$graph->set_title_font('/usr/lib/java/lib/fonts/LucidaSansRegular.ttf', 12);
$graph->set_x_label_font('/usr/lib/java/lib/fonts/LucidaSansRegular.ttf', 12);
$graph->set_x_axis_font('/usr/lib/java/lib/fonts/LucidaSansRegular.ttf', 12);
$graph->set_y_label_font('/usr/lib/java/lib/fonts/LucidaSansRegular.ttf', 12);
$graph->set_y_axis_font('/usr/lib/java/lib/fonts/LucidaSansRegular.ttf', 12);
$graph->set_values_font('/usr/lib/java/lib/fonts/LucidaSansRegular.ttf', 12);

print STDERR "Processing $graph_name\n";
$graph_rain->plot(\@rain);
save_chart($graph_rain, $graph_name);








html();



sub read_data
{
foreach $_ (`tail -n 1296 /home/hivetool/hive.log`)             #read the last 4 1/2 days worth of data
      {

  if ( substr($_,0,1) ne "#"  and length ($_) > 40  )
     {
      @comment_line = split('"', $_);				#split it apart at the first " if there is a comment
      @columns = split(' ', $_);				#split the rest of it on the spaces

      ($year, $mon, $mday) = split('/',$columns[0]);

      ($hour, $min) = split(':',$columns[1]);
      $sec = 0;

      $time = timelocal($sec,$min,$hour,$mday,($mon-1),$year);	#convert to epoch time
      if ( $first_date == 0 ) 
         { $first_date = timelocal(0,0,0,$mday,($mon-1),$year);}  #set the start date to midnight the day before

      $weight = $columns[3];
      $temperature = $columns[5];
      if ( defined $columns[6]  ) { $ambient = $columns[6]; }
      else { $ambient = 20; }
      if (defined $columns[17]) {$rain_total = $columns[17]; }
      else { $rain_total = $last_rain_total; }

 # Begin NASA manipulation change filter      
 # This should be conditional based on user input (checkbox somewhere) 


     if ( $weight >= 0 and $weight < 440 and
          $ambient >= 0 and $ambient <= 50 and
          $temperature >=0 and $temperature <= 50 and
          $rain_total >= 0 and $rain_total <= 5 )
          {
           if ( $last_weight ) {
              $delta_weight = $weight - $last_weight;
              $delta_time = $time - $last_time;
              if ( abs $delta_weight > $weight_threshold && $delta_time <= $time_threshold )
                 { 
                 $manipulation_change +=  $delta_weight;
                 }
              else
                 {
                 $daily_change += $delta_weight;
                 }
              }
          else {  #first time through
              $daily_change = $weight;
              }

           $last_weight = $weight;
           $last_time = $time;
           $last_date = $columns[0]; #is this needed?

           $weight = $daily_change;

# end NASA filter


#      if ( $columns[6] && $columns[6] > 0 && $columns[6] < 50 ) { $ambient = $columns[6]; }
#      if ( $columns[6]  && $columns[6] > -10 && $columns[6] < 50 ) { $ambient = $columns[6]; }

      if ( defined $columns[6]  ) { $ambient = $columns[6]; }
      else { $ambient = 20; }
       
      $temperature = $columns[5];

      $data[0][$i] = $time;

      $data[1][$i] = $weight;

#      $data[2][$i] = ($ambient-1.7)*1.8+32;			#convert from C to F and try to calibrate it

      $data[2][$i] = $ambient*1.8+32;
      $data[3][$i] = $temperature*1.8+32;

$rain[0][$i] =  $time;
#$rain[1][$i] = $rain_total;
if ($rain_total >= $last_rain_total ) { $rain[1][$i] = $rain_total - $last_rain_total; } 
else { $rain[1][$i] = 0; }

# print STDERR "$i $data[0][$i] $data[1][$i] $data[2][$i] $data[3][$i]\n";
# print STDERR "$i $rain[0][$i] $rain[1][$i]\n";

								#keep totals for averages
      $avg_weight += $weight;
      $avg_ambient += $data[2][$i];
      $avg_temperature += $data[3][$i];
								#test for min and max
      if ( $weight > $max_weight ) {$max_weight = $weight;}
      if ( $weight < $min_weight ) {$min_weight = $weight;}
      if ( $data[2][$i] > $max_ambient ) {$max_ambient = $data[2][$i];}
      if ( $data[2][$i] < $min_ambient ) {$min_ambient = $data[2][$i];}
      if ( $data[3][$i] > $max_temperature ) {$max_temperature = $data[3][$i];}
      if ( $data[3][$i] < $min_temperature ) {$min_temperature = $data[3][$i];}

      
     $last_rain_total = $rain_total;


  if ( $comment_line[1] ) {
          push @comments, scalar localtime($time) ."  ". $comment_line[1];
          }
      

     $i++;
      }  
  else
      {
      # log out of range lines to error log
      print STDERR "$_\n";
      }
     }
 else
     {
     # log commented out lines to somewhere
      print STDERR "$_\n";
     }
    }
      $last_date = timelocal(59,59,23,$mday,($mon-1),$year);	#set the end date to midnight

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
open(HTML, ">/var/www/htdocs/index.shtml") or 
                die "Cannot open index.shtml for write: $!";

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
$manipulation_change = sprintf '%6.1f', $manipulation_change;

$last_wx_wind_direction = $columns[8];
$last_wx_wind_speed = $columns[9];
$last_wx_wind_gust = $columns[10];


$heading = <<EOT;
<html>
<head>
   <title>HiveTool: $hostname</title>
   <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=ISO-8859-1">
   <meta name="description" content="Monitor hive weight, temperature, humidity with computer and electronic scale">
   <META name="keywords" content="beehive bee hive scale hivetool monitor data computer computerized electronic scalehive">
   <meta name="robots" CONTENT="all">
   <meta http-equiv="refresh" content="303" >
</head>


<body>

<img src=hive_graph.gif alt="Graph of hive weight and temperature $hostname $location $altitude feet elevation $date" title="Hive $hostname\nWeight and Temperature Graph\n$location\n$altitude feet elevation\n$date">

<img src=rain_graph.gif alt="Graph of rain at $hostname $location $altitude feet elevation $date" title="Hive $hostname\nRain Graph\n$location
\n$altitude feet elevation\n$date">


<table align=center border=1>
 <tr>
   <td></td>
   <td bgcolor=#80FF80>Weight</td>
   <td bgcolor=#80FF80>Temp</td>
   <td bgcolor=#80FF80>Ambient</td>
   <td bgcolor=#FFCC66>Temp</td>
   <td bgcolor=#FFCC66>Wind</td>
   <td bgcolor=#FFCC66>Speed</td>
   <td bgcolor=#FFCC66>Gusts</td>
   <td bgcolor=#FFCC66>Dewpoint</td>
   <td bgcolor=#FFCC66>Humidity</td>
   <td bgcolor=#FFCC66>Pressure</td>
   <td bgcolor=#FFCC66>Sunshine</td>
   <td bgcolor=#FFCC66>Evapotranspiration</td>
   <td bgcolor=#FFCC66>Vapor Pressure</td>
   <td bgcolor=#FFCC66>Rain</td>
 </tr>
 <tr>
   <td>Last</td>
   <td bgcolor=#80FF80>$last_weight lb.</td>
   <td bgcolor=#80FF80>$last_temperature°F</td>
   <td bgcolor=#80FF80>$last_ambient°F</td>
   <td bgcolor=#FFCC66>$last_wx_temperature°F</td>
   <td bgcolor=#FFCC66>$last_wx_wind_direction</td>
   <td bgcolor=#FFCC66>$last_wx_wind_speed mph</td>
   <td bgcolor=#FFCC66>$last_wx_wind_gust mph</td>
   <td bgcolor=#FFCC66>$last_wx_dewpoint°F</td>
   <td bgcolor=#FFCC66>$last_wx_humidity %</td>
   <td bgcolor=#FFCC66>$last_wx_pressure mb</td>
   <td bgcolor=#FFCC66>$last_wx_radiation Wm<sup>-2</sup></td>
   <td bgcolor=#FFCC66>$last_wx_evapotranspiration in.</td>
   <td bgcolor=#FFCC66>$last_wx_vapor_pressure mb</td>
   <td bgcolor=#FFCC66>$last_wx_rain in.</td>
 </tr>
 <tr>
   <td></td>
   <td bgcolor=#80FF80 colspan=3 align=center>Hive</td>
   <td bgcolor=#FFCC66 colspan=11 align=center><a href=http://weather.ggy.uga.edu/>University of Georgia Climatology Research Laboratory</a></td>
 </tr>

</table>
<p>

<table>
  <tr>
   <td>

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


   </td>
   <td width=20%>
   </td>
   <td>

<table>
 <tr>
  <th>
   Additional Links 
  </th>
 </tr>
 <tr>
  <td>
    <a href=hive_graph_wide.shtml>Graph of all the data</a>
  </td>
 </tr>
 <tr>
  <td>
    <a href=hive_graph_daily.shtml>Daily at Midnight Graph</a>
  </td>
 </tr>
 <tr>
  <td>
   <a href=download_form.html>Download Data</a>
  </td>
 </tr>
 <tr>
  <td>
   <a href=server_status.shtml>Server Status</a>
  </td>
 </tr>
 <tr>
  <td>
   <a href=/audio>Audio Archive</a>
  </td>
 </tr>
 <tr>
  <td>
   <a href=/video>Video Archive</a>
  </td>
 </tr>


</table>

   </td>
  </tr>
</table>

<p>Manipulation change: $manipulation_change lbs
<p>Comments:<br>
EOT

foreach $line (@comments) {
$heading .= "$line" . "<br>\n";
}


$heading .= <<EOT;
<br><br>

<!-- img src=hive_graph_2011.gif>
<br>
<img src=hive_graph_wide.gif height=400px>
<br -->

<center>
This page should automatically update every 5 minutes.<br><br>
<font color=red>Do not bookmark this page.  The dynamic IP of this computer will suddenly change.  Bookmark hivetool.org  This link on that page should update every 5 minutes.</font>
</center>

<table  width="1200px" align=center>
 <tr>
  <td align=left>
  <a href=http://hivetool.org>HiveTool ver 0.1</a>
  </td>
  <td align=center><b>$hive_name</b>
  </td>
  <td align=right>
   Last updated: $date
  </td>
 </tr>
</table>
</body>
</html>
EOT
print HTML $heading;
close HTML;

}

1;
