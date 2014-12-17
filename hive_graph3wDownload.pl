#! /usr/bin/perl -w
# 
# This perl script reads date, time, weight, hive temperature, ambient temperature
# from a sql database
#
#
# and creates a graph to display on a web page or writes the graph to a file.
#
# IMPORTANT: As of August, 2011 the perl module GD::Graph must be patched before it will
# properly display 2 y axes.  Apply adjust_axes.diff and min_range_fix.diff.
# See https://rt.cpan.org/Public/Bug/Display.html?id=62665
# 0.1.4 added NASA manipulation filter
# 0.2 reading from db
# 0.5 select from local db or hivetool db, read hive.conf, 

use strict; 

use Time::Local;
use Date::Format;
use Sys::Hostname;
use Getopt::Long;
use DBI;
use CGI;
use lib '../perl_pkgs';
#use GD::Graph::lines;
use GD::Graph::mixed; 

my $ip = $ENV{REMOTE_ADDR};          # get the IP of the user
my $data_source = "local";           # which database to use: prod, dev, local  ### put in config file with db login parameters ###
my $debug=0;                         # debug log level 0= none 9= maximum verbosity

my $date2=`date +"%m%d%Y%H%M%S"`;
my ($database, $user, $password);
my $dbh;
my @row;
my ($first_graph_date, $last_graph_date);
my $ambient_filter_threshold = 10;
my $ambient_raw = 0;
my ($weight_filter_raw_checked, $ambient_filter_raw_checked, $weight_filter_checked, $ambient_filter_checked);
my $number_of_rows;
my ($name, $value);
my $hive_id     = 1;
my $weather_station_location = "";
my $weather_station_id = 0;
my $weight_filter      = "Raw";
my $weight_filter_switch;
my $ambient_filter_switch;
my $first       = 0;
my $back1       = 0;
my $back7       = 0;
my $back30      = 0;
my $forward1    = 0;
my $forward7    = 0;
my $forward30   = 0;
my $last         = 0;
my $start_chart = 0;
my $end_chart   = 1440;
my $raw;
my $midnight = 0;
my $midnight_where = "";
my $width  = 1200;
my $height = 500;
my $graph_name;
my $min_date;
my $min_time;
my $max_date;
my $max_time;
my $log_name;
my $draw_graph;
my $download_data;
my $print_wx=0;
#my $html;
my $number_of_days=7;
my $legend = 1;
my $title="";
my ($x_label, $y1_label, $y2_label)=("","","");
my $x_label_skip=2;
my $x_tick_number=1;
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
my $epoch_time=0;
my $chart= "";   # "humidity";
#my $download_string;
my ($table_begin,$table_end);
my $download_file_format;
my $hivename;
my $location;
my $altitude;
my $nasa;
my $temperature_sensor = 0;
my $humidity_sensor = 0;

#my $hive_name;
my $graph;            

my (@data, @comment_line, @columns, @comments, @date, @ambient );
my $i = 0;
#my ($year, $mon, $mday, $hour, $min, $sec);
my ($day_of_year, $last_day_of_year)=(0,0);

my ($time, $rain, $weight, $ambient, $temperature, $humidity, $ambient_humidity);
my $max_weight = -999;
my $min_weight = 440;
my $max_ambient = -40;
my $min_ambient = 120;
my $max_temperature = -40;
my $min_temperature = 120;
my $max_humidity = 0;
my $min_humidity = 100;
my $max_ambient_humidity = 0;
my $min_ambient_humidity = 100;


my ($min_y, $max_y);
my $first_date = 0;

my $last_date=0;
my ($last_weight, $last_ambient, $last_temperature)=(0,0,0);
my ($last_wx_temperature, $last_wx_wind_direction, $last_wx_wind_degrees, $last_wx_wind_speed, $last_wx_wind_gust, $last_wx_dewpoint, $last_wx_humidity, $last_wx_pressure,  $last_wx_radiation, $last_wx_evapotranspiration, $last_wx_vapor_pressure, $last_wx_rain, $last_humidity, $last_ambient_humidity)=(0,0,0,0,0,0,0,0,0,0,0,0,0,0);
my ($last_time, $delta_time, $delta_weight, $delta_rain, $daily_change, $manipulation_change)=(1, 0, 0, 0, 0, 0);
my $time_threshold=300;
my $weight_threshold=1; 
my $max_dwdt_lbs_per_hour = 60;
my $start_zero_weight = 0;
my $dwdt = 0;
my $status=0;
my ($weight_span, $weight_offset, $number_of_points)=(0,0,0);
my $hive_ambient_temperature=0;
#my $temperature_source="hive";
my $temperature_source="WX";
my $humidity_source="WX";
my $hive_bg="#FFCC66";   #="#66CCFF";
my $hive_ambient_bg="#80FF80";
my $wx_bg="#66CCFF";       #="#FFCC66";

# create a CGI object and get the form and url variables
my $query = new CGI;
$query->import_names('FORM');

# #######################################################################################################

get_form();                                             # read the form and command line variables
initialize();                                           # initialize variables that were left blank
select_data_source();                                   # select the data source to graph
read_data();						# read the data into arrays and display if download
if ( ! $download_data ) { graph_data(); }               # generate the graph if not a download
# #######################################################################################################



sub graph_data
{

if ( $chart eq "Humidity" ) 
  {
  if ( $max_ambient_humidity > $max_humidity ) {$max_y = $max_ambient_humidity;}
else {$max_y = $max_humidity;}

  if ( $min_ambient_humidity < $min_humidity ) {$min_y = $min_ambient_humidity;}
else {$min_y = $min_humidity;}
  }

elsif ( $chart eq "Temp/Humidity" ) 
  {
  if ( $max_temperature > $max_humidity ) {$max_y = $max_temperature;}
else {$max_y = $max_humidity;}

  if ( $min_temperature < $min_humidity ) {$min_y = $max_temperature;}
else {$min_y = $min_humidity;}
  }

else
  {
  if ( $debug > 4 ) { print LOG "$chart min_ambient: $min_ambient max_ambient: $max_ambient min_temperature: $min_temperature max_temperature: $max_temperature\n"; }

  if ( $max_ambient > $max_temperature ) {$max_y = $max_ambient;}
else {$max_y = $max_temperature;}

  if ( $min_ambient < $min_temperature ) {$min_y = $min_ambient;}
else {$min_y = $min_temperature;}
  }
#foreach my $x (@array) { $x = $x * $scalar; }

if ( $debug > 4 ) { print LOG "min_weight: $min_weight  max_weight: $max_weight min_y: $min_y max_y: $max_y\n"; }

# Scale the rain data so it will fit on the weight axiz

 $weight_offset =  int $min_weight;
 $weight_span   =  int ($max_weight - $min_weight + 1);
 $weight_span   =  $weight_span * 40;

if ($debug ) { print LOG "Weight_offset = $weight_offset   Weight span = $weight_span\n"; }

for ($i = 0; $i < $number_of_points; $i++) {
    if ( defined $data[1][$i] )
      {
      $data[1][$i] = ($data[1][$i] * $weight_span) + $weight_offset;
      if ($data[1][$i] < $weight_offset) { $data[1][$i] = $min_weight; }
      if ($data[1][$i] > $max_weight) { $data[1][$i] = $max_weight; }
      
      if ($debug > 8) { print LOG "$i $data[0][$i] $data[1][$i] $data[4][$i]\n"; }
      }
     }

my @dclrs;

if ($weight_filter eq "Raw") {$y1_label="Weight (Pounds)";  $x_label = "Time"; }
elsif ($weight_filter eq "NASA") {
   $y1_label="Filtered Weight (Pounds)";
   $manipulation_change = sprintf '%6.2f',$manipulation_change;
   $x_label = "Time               NASA Weight Filter max dw/dt is $max_dwdt_lbs_per_hour lbs/hour. Manipulation change is $manipulation_change lbs.";}


if ($chart eq "Humidity"  ) {
   if ($legend )
      {
      $title = "$hivename $location - $altitude feet elev.           Hive Weight and Humidity            $first_graph_date - $last_graph_date";
      }
  else {
      $title = "$hivename $first_graph_date - $last_graph_date";
      }
   $y2_label = "Relative Humidity (Percent)";
#   @dclrs=("white","green","blue","red");   
   @dclrs=("white","lgreen","dgreen","red");
#   @dclrs=("white","lgreen","#FFCC66","red");
   }

elsif ($chart eq "Temp/Humidity"  ) {
   if ($legend )
      {
      $title = "$hivename $location - $altitude feet elev.         Hive Weight Temperature and Humidity            $first_graph_date - $last_graph_date";
      }
  else {
      $title = "$hivename $first_graph_date - $last_graph_date";
      }
   $y2_label = "Temp (F) and Relative Humidity (Percent)";
#   @dclrs=("white","green","blue","red");   
   @dclrs=("white","dgreen","dblue","red");
#   @dclrs=("white","lgreen","#FFCC66","red");
   }

else {
   if ($legend)
      {
      $title = "$hivename $location - $altitude feet elev.         Hive Weight and Temperature           $first_graph_date - $last_graph_date";
      }
  else {
      $title = "$hivename  $last_graph_date";
      }
   $y2_label = "Temperature (Fahrenheit)";
#   @dclrs=("white","green","#FFCC66","red");
   @dclrs=("white","lblue","dblue","red");
   }

  if ($debug > 4) { print LOG "title: $title"; }
 
  $x_tick_number =  $number_of_days+$number_of_days;
  if ( $number_of_rows > 14*288 ) { $x_label_skip = 7; $x_tick_number=$number_of_days; }
  if ( $number_of_rows > 30*288 ) { $x_label_skip = 14; }

  if ( $debug > 4 ) { print LOG "Number of rows: $number_of_rows  x_label_skip: $x_label_skip x_tick_number: $x_tick_number\n"; }

$graph = GD::Graph::mixed->new($width,$height);            

$graph->set( 
 types => [ qw( lines lines lines lines ) ], 
 default_type => 'lines', 
); 

 $graph->set( 						#set the graph parameters
 two_axes        => 2, 
 zero_axis       => 0, 
 title           => "$title", 
 use_axis        => [1,2,2,1],
 line_width      => 3,
 x_label         => $x_label, 
 x_ticks         => 1,
 x_long_ticks    => 1,
 y_long_ticks    => 1,
 x_tick_number   => $x_tick_number,
 x_number_format => sub { time2str( "%D", $_[0] ) },
 x_label_skip    => $x_label_skip,
 x_label_position => .3,
 y1_label        => $y1_label, 
 y2_label        => $y2_label,
 y1_min_value    => int $min_weight,
 y1_max_value    => int ($max_weight+1),
 x_min_value     => $first_date,
 x_max_value     => $last_date,
 y2_min_value    => int ($min_y-1),
 y2_max_value    => int ($max_y+1),
 transparent     => 0, 
 boxclr          => 'lgray',
 dclrs           => \@dclrs, 
 bar_width       => 1, 
 bgclr           => '#EDEEEB',
 skip_undef      => 1,
 legend_marker_width => 20,
 legend_marker_height => 40,
); 

if ( $legend ) { 
  if ( $chart eq "Humidity" )
     {
     $graph->set_legend( 'Rain (White)', "Outside Humidity", 'Inside Humidity','Weight' ); 
     }
  elsif ( $chart eq "Temp/Humidity" )
     {
     $graph->set_legend( 'Rain (White)', "Hive Humidity", 'Hive Temperature','Weight' ); 
     }
 else {
     $graph->set_legend( 'Rain (White)', "$temperature_source Ambient Temperature", 'Hive Temperature','Weight' ); 
     }
  $graph->set_legend_font('./LucidaSansRegular.ttf', 12);
}

if ( $legend ) { 
$graph->set_title_font('./LucidaSansRegular.ttf', 12);
$graph->set_x_label_font('LucidaSansRegular.ttf', 12);
$graph->set_x_axis_font('./LucidaSansRegular.ttf', 10);
$graph->set_y_label_font('./LucidaSansRegular.ttf', 12);
$graph->set_y_axis_font('./LucidaSansRegular.ttf', 12);
$graph->set_values_font('./LucidaSansRegular.ttf', 12);
}
else {
$graph->set_title_font('./LucidaSansRegular.ttf', 8);
$graph->set_x_label_font('LucidaSansRegular.ttf', 6);
$graph->set_x_axis_font('./LucidaSansRegular.ttf', 6);
$graph->set_y_label_font('./LucidaSansRegular.ttf', 6);
$graph->set_y_axis_font('./LucidaSansRegular.ttf', 6);
$graph->set_values_font('./LucidaSansRegular.ttf', 6);
}
#print STDERR "Processing $graph_name\n"; 
$graph->plot(\@data); 
print_chart($graph, $graph_name); 
}                                                            # end of graph_data

#
#
#=================================== read_data ================================
#

sub read_data
{
my ($where, $sql, $sth, $rc, $date_time, $date);
my (@row);
my $abs_ambient;
my $weight_bias=0;
my $quality;

my ($wx_temp_f, $wx_relative_humidity, $wx_wind_mph, $wx_wind_gust_mph, $wx_wind_degrees, $wx_dewpoint_f,  $wx_pressure_mb);

my $temp_correction;

if ( $debug > 4 ) {
     print LOG "read_data \n";
     }
     
$dbh = DBI->connect("DBI:mysql:$database", $user, $password)  or
      badLogin("Your username/password combination was incorrect.");

get_hive_parameters();                                                        # get the hive parameters




#     $graph_name = "../tmp/$ip" . "_" . "$html" . "_" . "$hivename" . "_" . "$date2";
     $graph_name = "../tmp/$ip" . "_" . "$hivename" . "_" . "$date2";
     $graph_name =~ s/ //g;
     chomp($graph_name);
#     $hive_name = "$hivename $location - $altitude feet elevation Filter: $weight_filter";

get_number_of_rows();                                                          # get the number of rows

  if ( $debug > 6 ) { print LOG "read_data \n"; }

          $sql = "SELECT hive_observation_time_local, hive_weight_lbs, hive_temp_c, wx_temp_f, wx_relative_humidity, wx_wind_degrees, wx_wind_mph, wx_wind_gust_mph, wx_pressure_mb, wx_dewpoint_f, wx_precip_today_in, hive_humidity, ambient_humidity, ambient_temp_c, quality
           FROM HIVE_DATA 
           WHERE hive_id = $hive_id and quality > 0 and
           hive_observation_time_local >= \"$min_date\" and
           $midnight_where
           hive_observation_time_local <= \"$max_date\"
           ORDER BY hive_observation_time_local";

#          hive_observation_time_local like \"% 00:00:%\"

  if ( $debug > 6 ) { print LOG "$sql\n" }

        $sth = $dbh->prepare("$sql") or
               htmlDie("Could not prepare query: $sql\n$DBI::errstr\n");

        $rc = $sth->execute or
               htmlDie("Could not execute query: $sql\n$DBI::errstr\n");

#  $temperature_source="WX";
  if ( $temperature_sensor == 1 or $temperature_sensor == 3 ) { $temperature_source="Hive"; }
  if ( $humidity_sensor == 1 or $humidity_sensor == 3 ) { $humidity_source="Hive"; }

  if ($download_data)  { print_table_header(); }


      $i=0;
      while ( @row = $sth->fetchrow() )
      {
      if ( defined $row[1] ) { $weight = $row[1]; }
      else { $weight = 0; }
      if ( defined $row[2] ) { $temperature = $row[2]; }
      else { $temperature = 0; }
      if ( defined $row[3] ) { $wx_temp_f = $row[3]; }
#      else { $wx_temp_f = 0; }
      if ( defined $row[4] ) { $wx_relative_humidity = $row[4]; }
#      else { $wx_relative_humidity = 0; }
      if ( defined $row[5] ) { $wx_wind_degrees = $row[5]; }
      else { $wx_wind_degrees = 0; }
      if ( defined $row[6] ) { $wx_wind_mph = $row[6]; }
      else { $wx_wind_mph = 0; }
      if ( defined $row[7] ) { $wx_wind_gust_mph = $row[7]; }
      else { $wx_wind_gust_mph = 0; }
      if ( defined $row[8] ) { $wx_pressure_mb = $row[8]; }
      else { $wx_pressure_mb = 0; }
      if ( defined $row[9] ) { $wx_dewpoint_f = $row[9]; }
      else { $wx_dewpoint_f = 0; }
      if ( defined $row[10] ) { $rain = $row[10]; }
      else { $rain = 0; }
      if ( defined $row[11] ) { $humidity = $row[11]; }
      else { $humidity = 0; }
      if ( defined $row[12] ) { $ambient_humidity = $row[12]; }
      else { $ambient_humidity = 0; }

      if ( $temperature_source eq "Hive" ) {
         if ( defined $row[13] ) { $ambient = $row[13]*1.8+32; }
#         else { $ambient = 0; }
         }
      else {
         if ( defined $row[3] ) { $ambient = $row[3]; }
#         else { $ambient = 50; }
          else {undef $ambient; }
          }
      if ( defined $row[14] ) { $quality = $row[14]; }

# ### Need same tests for humidity

      ($date, $time) = split(' ',$row[0]);
      ($year, $mon, $mday) = split('-',$date);
      ($hour, $min, $sec) = split(':',$time);
      $sec = 0;

      $time = timelocal($sec,$min,$hour,$mday,($mon-1),$year);	#convert to epoch time
      $day_of_year = (localtime( $time ) )[7] + 1;  # first day of year is 1, not zero

# ############################## ### WARNING ### ####################################
#     If two hives have the same ID, there can be multiple records for the same time.
#     The NASA filter (dw/dt) bombs, because dt = 0
#     This shouldn't ever happen - unless someone clones an SD card...
#     or maybe during testing when running hive.sh manually?

if ($last_time > 0 and $time != $last_time )   # this throws away additional data records with the same time
{                                              # maybe add a column and filter for IP?
      if ( $first_date == 0 ) 
         { $first_date = timelocal(0,0,0,$mday,($mon-1),$year);    #set the start date to midnight the day before
 #        print LOG "first_date = 0\n";
        if ( not defined $weight or $weight == 0)
             { $start_zero_weight = 1;
 #            print LOG "Start_zero_weight = $start_zero_weight\n";
             }
         }
      if ( $last_weight ) {
         $delta_weight = $weight - $last_weight;
         $delta_time = ($time - $last_time)/3600;
         $delta_rain =  $rain - $last_wx_rain;

         if ($delta_time) { $dwdt = $delta_weight/$delta_time; }

 # Begin NASA manipulation change filter

         if ( ($weight_filter eq "NASA") 
           && (abs $dwdt > $max_dwdt_lbs_per_hour)             # if the change in weight exceeds the threshold
           && ($start_zero_weight == 0)                        # and the data is not starting off with zeros
           && ($quality != 6) )                                # and this record is not flagged as a swarm (Quality 6)
            {                                                  # then don't count the change as daily change,
            $manipulation_change +=  $delta_weight;            # count it as manipulation change
            }
         else
            {
            $daily_change += $delta_weight;                    # otherwise, count it as part of the daily change
            }

         }
      else {                                                #first time through
            $daily_change = $weight;
              $first_graph_date = $row[0];
#              $last_ambient = $ambient;
              $last_wx_rain = $rain;
              $delta_rain = 0;
         }

         $last_weight = $weight;
         $weight = $daily_change;

# end NASA filter

         $last_temperature = $temperature;

#           $abs_ambient = abs( $ambient - $last_ambient);
#           if ( $abs_ambient < $ambient_filter_threshold || $ambient_raw  )  {  
#                $last_ambient = $ambient; 
#                } 
#           else { $ambient = $last_ambient; }         # *1.8+32;

         $last_time = $time;
         if ( $day_of_year != $last_day_of_year or not $midnight ) {     
              $data[0][$i] = $time;
              $data[1][$i] = $delta_rain;
              if ( $chart eq "Humidity" )
                {
                $data[2][$i] = $ambient_humidity; 
                $data[3][$i] = $humidity;
                }
              elsif ( $chart eq "Temp/Humidity" )
                {
                $data[2][$i] = $humidity;
                $data[3][$i] = $temperature*1.8+32;
                }

              else
                {
                $data[2][$i] = $ambient; 
                $data[3][$i] = $temperature*1.8+32;
                }
#              $data[4][$i] = $weight;

#             if ( $data[3][$i] > 72 ) { $temp_correction = (13 * 0.0312976479); }
#           else { $temp_correction = ($data[3][$i]-59) * 0.0312976479; }

#            $temp_correction = ($data[3][$i]-59) * 0.0312976479;
#            $temp_correction = sprintf '%6.1f', $temp_correction;
             $temp_correction = 0;
             
             if ( defined $weight and $weight > 0  and $start_zero_weight) { $start_zero_weight=0 }
             if ( $start_zero_weight == 0 )
                { $data[4][$i] = $weight - $temp_correction; }

#      $data[5][$i] = $ambient_humidity; 
#      $data[6][$i] = $humidity;

#       if ( $debug > 8 ) { print LOG "read_data: $i $row[0] $weight $delta_weight $manipulation_change $ambient $row[13]\n";}
#       if ( $debug > 8 ) { print LOG "read_data: $i $row[0] $last_weight $weight $delta_weight $manipulation_change\n";}
       if ( $debug > 8 ) { print LOG "read_data: $i $row[0] lw=$last_weight dc=$weight dw=$delta_weight mc=$manipulation_change wb=$weight_bias szw=$start_zero_weight wa=$data[4][$i]\n";}

#test for min and max
      if ( $weight > $max_weight ) {$max_weight = $weight;}
      if ( $weight < $min_weight and defined $data[4][$i] and $start_zero_weight == 0) {$min_weight = $weight;}
      if ( defined $data[2][$i] and $data[2][$i] > $max_ambient ) {$max_ambient = $data[2][$i];}
      if ( defined $data[2][$i] and $data[2][$i] < $min_ambient ) {$min_ambient = $data[2][$i];}
      if ( defined $data[3][$i] and $data[3][$i] > $max_temperature ) {$max_temperature = $data[3][$i];}
      if ( defined $data[3][$i] and $data[3][$i] < $min_temperature ) {$min_temperature = $data[3][$i];}
      if ( $humidity > $max_humidity ) {$max_humidity = $humidity;}
      if ( $humidity < $min_humidity ) {$min_humidity = $humidity;}
      if ( $ambient_humidity > $max_ambient_humidity ) {$max_ambient_humidity = $ambient_humidity;}
      if ( $ambient_humidity < $min_ambient_humidity ) {$min_ambient_humidity = $ambient_humidity;}

      
       if ( $comment_line[1] ) {
          push @comments, scalar localtime($time) ."  ". $comment_line[1];
          }
         $last_graph_date = $row[0]; 
         $last_wx_temperature = $row[3];
         $last_wx_humidity =  $row[4];
         $last_wx_wind_direction = $row[5];
#         if (~$last_wx_wind_direction) {$last_wx_wind_direction="NA";}
#$last_wx_wind_direction ="NA";
         $last_wx_wind_speed = $row[6];
         $last_wx_wind_gust = $row[7];
         $last_wx_pressure =  $row[8];
         $last_wx_dewpoint =  $row[9];
       if ( defined $row[10] ) { $last_wx_rain = $row[10]; }
      else { $last_wx_rain = 0; }
#        $last_wx_rain =  $row[10];
         $last_humidity =  $row[11];
         $last_ambient_humidity = $row[12];
         $last_day_of_year = $day_of_year;

    if ($download_data)
       {
       $weight = sprintf '%6.2f', $weight;
       $temperature = sprintf '%6.1f', ($temperature * 9 / 5 )+32;

       if ($download_file_format eq "csv") {

           print "$row[0],$weight,$temperature,$ambient,$humidity,$ambient_humidity,$rain";
           print "<br>\r\n"; 
#           if ( $print_wx ) {
#              print ",$columns[7],$columns[8],$columns[9],$columns[10],$columns[11],$columns[12],$columns[13],$columns[14],$columns[15],$columns[16],$columns[17]";
              }
       else {
              print "<tr><td>$i $mon/$mday $hour:$min</td><td  bgcolor=red>$weight</td><td  bgcolor=$hive_bg>$temperature</td><td bgcolor=$hive_bg>$humidity</td><td bgcolor=$hive_ambient_bg>$ambient</td><td bgcolor=$hive_ambient_bg>$ambient_humidity</td><td bgcolor=$wx_bg>$wx_temp_f</td><td bgcolor=$wx_bg>$wx_relative_humidity</td><td bgcolor=$wx_bg>$wx_wind_mph</td><td bgcolor=$wx_bg>$wx_wind_gust_mph</td><td bgcolor=$wx_bg>$wx_wind_degrees</td><td bgcolor=$wx_bg>$wx_dewpoint_f</td><td bgcolor=$wx_bg>$wx_pressure_mb</td><td bgcolor=$wx_bg>$rain</td></tr>\n";
            }
       }    # end of if download_data
     } # end of if ($day_of_year != $last_day_of_year or not $midnight)
  } # end of if ($last_time > 0 and $time != $last_time )
     $last_time = $time;
     $i++;


}  #end of while loop

       if ( $debug > 4 ) {   print LOG "max_weight: $max_weight min_weight: $min_weight\n"; }

#      $last_date = timelocal(59,59,23,$mday,($mon-1),$year);	#set the end date to midnight
      $last_date = timelocal(59,59,$hour,$mday,($mon-1),$year);	#set the end date to midnight

      if ( $i )  {						#calculate the averages

#       if ( $debug > 4 ) { print LOG "read_data (last time): $row[0] $weight $temperature $ambient $row[5] $row[7]\n";}
         $number_of_points = $i;

         $last_weight = $data[4][$i-1];
#         $last_ambient = $data[2][$i-1];
         $last_ambient = $ambient;
         $last_temperature = $data[3][$i-1];
         }

        $number_of_days = ($last_date - $first_date)/86400;

#print LOG "number_of_days: $number_of_days\n";

  if ($download_data)
     {

 print <<END;


 $table_end
 </table>
</body>
</html>

END
    }

}

#
#============================================================================================
#


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
#
#============================================================================================
#

sub print_chart
{
        my $chart = shift or die "Need a chart!";
#        my $graph_name = shift or die "Need a name!";
        my $ext = $chart->export_format;
 
        print "Content-type: image/gif\n\n";
        print  $chart->gd->$ext();
}
#
#============================================================================================
#

#sub print_data
#{
#if ($download_file_format ne "csv")
#   {
#   $table_begin = "<center><table border=1>";
#   $table_end ="</table></cener>";
#   }

#print <<END;
#Content-Type: text/html; charset=iso-8859-1

#<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN">
#<html>
#<body>
# $table_begin
#$download_string
# $table_end
# </table>
#</body>
#</html>
#END

#}


#
#
#===================================== get_form =============================================
#


sub get_form
{

if ($debug ) {
  open(LOG, ">>debug.log") or 
                die "Cannot open debug.log for write: $!";
  print LOG "hive_graph3wDownload  $ENV{REMOTE_ADDR} " . `date`;

  foreach $name ( $query->param() ) {
      $value = $query->param($name);
      if ( $value or $debug > 8 ) { print LOG "FORM: $name = $value\n"; }
  }
}

# Navigation buttons and switches for GUI
$first       = $query->param('first');
$back1       = $query->param('back1');
$back7       = $query->param('back7');
$back30      = $query->param('back30');
$forward1    = $query->param('forward1');
$forward7    = $query->param('forward7');
$forward30   = $query->param('forward30');
$last         = $query->param('last');
$start_chart = $query->param('start_chart');
$hive_id     = $query->param('hive_id');
$weight_filter      = $query->param('weight_filter');
$weight_filter_switch =  $query->param('weight_filter_switch');
$ambient_filter_switch =  $query->param('ambient_filter_switch');
$chart =  $query->param('chart');
$download_file_format = $query->param('download_file_format');   # = "csv";

# URL parameters
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
$max_dwdt_lbs_per_hour = $query->param('nasa_weight_dwdt');
if ( not defined $max_dwdt_lbs_per_hour  or not $max_dwdt_lbs_per_hour) { $max_dwdt_lbs_per_hour = 3; }

# get the command line variables
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

} # End of get_form
#
#============================================================================================
#
sub initialize
{
if ( not defined $midnight or not $midnight )
   { $midnight = 0; $midnight_where = ""; }
else {$midnight_where = "hive_observation_time_local like \"% 00:00:%\" and"; }

if ( not defined $chart and not $chart ) { $chart = 0; }
if ( not defined $max_date and not $max_date )
   {
        ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
        $year+=1900;
        $mon+=1;
        $max_date= "$year-$mon-$mday"; 
        }
if (not defined $min_date and not $min_date ) { 
        $epoch_time = timelocal(0,0,0,$mday,($mon-1),$year);	#convert to epoch time
        ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($epoch_time-(($number_of_days-1)*86400));
        $year+=1900;
        $mon+=1;
        $min_date = "$year-$mon-$mday"; 
        }
if ( defined $weight_filter_switch ) { $weight_filter = $weight_filter_switch; }
if ( defined $weight_filter  ) { 
   if ( $weight_filter eq "NASA") { $weight_filter_switch = "Raw"; $weight_filter_raw_checked = ""; $weight_filter_checked = "checked"; }
   elsif ( $weight_filter eq "Raw") { $weight_filter_switch = "NASA"; $weight_filter_raw_checked = "checked"; $weight_filter_checked = ""; }
 }
else { $weight_filter = "Raw"; $weight_filter_switch = "NASA";  $weight_filter_raw_checked = "checked"; $weight_filter_checked = ""; }

if ( defined  $ambient_filter_switch ) { 
   if ( $ambient_filter_switch eq "Filtered" ) { $ambient_raw = 0; $ambient_filter_raw_checked = ""; $ambient_filter_checked = "checked";}
   else { $ambient_raw = 1; $ambient_filter_raw_checked = "checked"; $ambient_filter_checked = ""; }
 }
else { $ambient_raw = 0;  $ambient_filter_raw_checked = ""; $ambient_filter_checked = "checked"; }

if ( defined $width and $width ) {} else { $width = 1200; }
if ( defined $height and $height ) {} else { $height = 500; }

if ( $height < 401 ) { $legend = 0; }                     #turn off legend on small graphs

if ( $debug > 4 ) {  print LOG "height: $height  width: $width  legend: $legend\n"; }

if ( $debug > 8 ) {
    if ( defined $start_chart ) { print LOG "start_chart initilization: $start_chart\n"; }
    else { print LOG "start_chart initialization: start_chart is undefined\n"; }
    }
} # End of initialize
#
#====================================================================================
#
sub select_data_source
{

if ( $data_source eq "dev" ) 
   {
   $database = "hivetool_raw_dev1:woodhollow.netfirmsmysql.com:3306";
   $user = "beehive";
   $password = "2Bee|~2beE";
   }
elsif  ( $data_source eq "prod" )
   {
   $database = "hivetool_raw:woodhollow.netfirmsmysql.com:3306";
   $user = "hivetool";
   $password = "hivetool";
   }
elsif ( $data_source eq "local" )
   {
   $database = "hivetool_raw:localhost:3306";
   $user = "root";
   $password = "raspberry"; 
   }
} # end of select_data_source

#
#===================================================================================
#

# ### Combine these 2 selects ###

sub get_hive_parameters {
my ( $sql, $sth, $rc );

          $sql = "SELECT name,nasa,status,city,state,altitude_feet,weather_station_id, temperature_sensor, humidity_sensor FROM HIVE_PARAMETERS WHERE hive_id=$hive_id";

  if ( $debug > 6 ) { print LOG "$sql\n" }

        $sth = $dbh->prepare("$sql") or
               htmlDie("Could not prepare query: $sql\n$DBI::errstr\n");

        $rc = $sth->execute or
               htmlDie("Could not execute query: $sql\n$DBI::errstr\n");

     @row = $sth->fetchrow();
     $hivename = $row[0];
     $nasa = $row[1];
     $status = $row[2];
     $location = "$row[3], $row[4]";
     $altitude = $row[5];
     $weather_station_id = $row[6];
     $temperature_sensor =  $row[7];
     $humidity_sensor =  $row[8];

          $sql = "SELECT name FROM WEATHER_STATIONS WHERE weather_station_id=$weather_station_id";

  if ( $debug > 6 ) { print LOG "$sql\n" }

        $sth = $dbh->prepare("$sql") or
               htmlDie("Could not prepare query: $sql\n$DBI::errstr\n");

        $rc = $sth->execute or
               htmlDie("Could not execute query: $sql\n$DBI::errstr\n");

     @row = $sth->fetchrow();
     $weather_station_location = $row[0];
}



#
#===================================================================================
#


sub get_number_of_rows {
my ( $sql, $sth, $rc );

 if ( $debug > 4 ) {
     print LOG "read_data \n";
     }
          $sql = "SELECT count(*)
                  FROM HIVE_DATA
                  WHERE hive_id = $hive_id and
                        quality > 0 and
                        hive_observation_time_local >= \"$min_date\" and
                        hive_observation_time_local <= \"$max_date\"";

  if ( $debug > 6 ) { print LOG "$sql\n" }

        $sth = $dbh->prepare("$sql") or
               htmlDie("Could not prepare query: $sql\n$DBI::errstr\n");

        $rc = $sth->execute or
               htmlDie("Could not execute query: $sql\n$DBI::errstr\n");

     @row = $sth->fetchrow();
     
     $number_of_rows = $row[0];

}

sub print_table_header {

if ($download_file_format eq "csv")
   {$table_begin = "Date,weight,temperature,ambient_temperature,humidity,ambient_humidity,rain<br>\r\n";}
else {
$table_begin = "<center><table border=1>\n<tr><td>Date Time</td><td bgcolor=red>Weight</td><td bgcolor=$hive_bg>Temp</td><td bgcolor=$hive_bg>Humidity</td bgcolor=$hive_bg><td bgcolor=$hive_ambient_bg>Temp</td><td bgcolor=$hive_ambient_bg>Humidity</td>
<td bgcolor=$wx_bg>Temp</td>
<td bgcolor=$wx_bg>Humidity</td>
<td bgcolor=$wx_bg>Wind</td>
<td bgcolor=$wx_bg>Gusts</td>
<td bgcolor=$wx_bg>Direction</td>
<td bgcolor=$wx_bg>Dewpoint</td>
<td bgcolor=$wx_bg>Pressure</td>
<td bgcolor=$wx_bg>Rain</td></tr>";

$table_end ="</table></cener>";
   }

print <<END;
Content-Type: text/html; charset=iso-8859-1t

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN">
<html>
<body>
$table_begin
END

}

if ( $debug ) {close LOG; }
1;
