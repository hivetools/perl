#! /usr/bin/perl -w
# 
# This perl program reads date, time, max, min, and average hive weight, temperature, ambient temperature, etc
# from a sql database and outputs an html stats page with a img tag to hive_graphXxxxx.pl that creates the graph.
#

use strict; 
use Time::Local;
use Date::Format;
use Sys::Hostname;
use DBI;
use CGI;

my $debug  = 9;                           # set the debug level - 0 is off, 9 is all
my $data_source = "local";                # which database to use: prod, dev, local ### put in config file with db login parameters

my ($dbh, $sql, $sth, $rc);
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
my $dropdown_hive_select;
my @row;
my ($alt, $title);
my ($first_date, $last_weight, $date, $manipulation_change,$last_temperature,$last_ambient_temperature,$last_wx_temp_f,$last_humidity, $last_ambient_humidity,$last_wx_wind_direction,$last_wx_wind_speed, $last_wx_wind_gust, $last_wx_dewpoint,$last_wx_relative_humidity, $last_wx_pressure, $last_wx_radiation, $last_wx_evapotranspiration, $last_wx_vapor_pressure, $last_wx_rain, $last_graph_date)=(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0.0);
my $hivename = "";
my $nasa = "";
my $status = "";
my $location = "";
my $altitude = "";
my $weather_station_id = "";
my $start_date;
my $last_update;
my $hive_name;
my $html_title;
my $weather_station_location = "";
my ($avg_weight, $min_weight, $max_weight)=(0,0,0);
my ($avg_temperature, $min_temperature, $max_temperature) = (0,0,0);
my ($avg_humidity, $min_humidity, $max_humidity) = (0,0,0);
my ($avg_ambient_temperature, $min_ambient_temperature, $max_ambient_temperature) = (0,0,0);
my ($avg_ambient_humidity, $min_ambient_humidity, $max_ambient_humidity) = (0,0,0);
my ($avg_wx_temp_f, $min_wx_temp_f, $max_wx_temp_f);
my ($avg_wx_relative_humidity, $min_wx_relative_humidity, $max_wx_relative_humidity);
my ($avg_wx_wind_degrees, $min_wx_wind_degrees , $max_wx_wind_degrees);
my ($avg_wx_wind_mph, $min_wx_wind_mph, $max_wx_wind_mph);
my ($avg_wx_wind_gust_mph, $min_wx_wind_gust_mph, $max_wx_wind_gust_mph);
my ($avg_wx_dewpoint, $min_wx_dewpoint, $max_wx_dewpoint); 
my ($avg_wx_pressure, $min_wx_pressure,  $max_wx_pressure); 
my ($avg_wx_rain, $min_wx_rain,  $max_wx_rain);

my $query = new CGI;
$query->import_names('FORM');

if ($debug ) {
  open(LOG, ">debug.log") or 
                die "Cannot open debug.log for write: $!";
  print LOG "hive_stats3wDownload.pl  $ENV{REMOTE_ADDR} " . `date`;

  my ($name, $value);
  foreach $name ( $query->param() ) {
      $value = $query->param($name);
      if ( $value or $debug > 8 ) { print LOG "FORM: $name = $value\n"; }
  }
}


# URL and FORM parameters
my $hive_id     = $query->param('hive_id');
my $new_hive_id = $query->param('new_hive_id');
my $raw = $query->param('raw');
my $midnight = $query->param('midnight');
my $width = $query->param('width');
my $height = $query->param('height');
my $graph_name = $query->param('output');
my $last_start_time = $query->param('start_time');
$last_start_time =~ s/%20/ /g;
my $last_end_time =  $query->param('end_time');
$last_end_time =~ s/%20/ /g;
my $last_number_of_days = $query->param('number_of_days');

my $start_time = $query->param('begin');
my $end_time = $query->param('end');
my $number_of_days = $query->param('days');
my $last_max_dwdt_lbs_per_hour = $query->param('last_max_dwdt_lbs_per_hour');
my $chart = $query->param('chart');
my $download = $query->param('download');
my $download_file_format = $query->param('download_file_format');
my $download_data_format = $query->param('download_data_format');

my $metatag_refresh = "";
if (not $download) { $metatag_refresh="<meta http-equiv=\"refresh\" content=\"303\" >\n"; }

my $epoch_time;

if ( not defined $chart or not $chart ) { $chart="Temperature"; }
if ( not defined $midnight or not $midnight ) { $midnight=0; }
if ( not defined $width or not $width ) { $width=1150; }
if ( not defined $height or not $height ) { $height=500; }

if ( defined $new_hive_id and $new_hive_id ) { $hive_id = $new_hive_id; }

my $navigation_button = $query->param('navigation_button');
my $start_chart = $query->param('start_chart');
my $weight_filter      = $query->param('weight_filter');
my $weight_filter_switch =  $query->param('weight_filter_switch');
my $max_dwdt_lbs_per_hour = $query->param('max_dwdt_lbs_per_hour');
my $ambient_filter_switch =  $query->param('ambient_filter_switch');
my $temp_humidity_switch =   $query->param('temp_humidity_switch');
my $download_checked =  $query->param('download');
my $midnight_checked;

if ( not defined $max_dwdt_lbs_per_hour  or not $max_dwdt_lbs_per_hour)
   {
   if ( defined $last_max_dwdt_lbs_per_hour and $last_max_dwdt_lbs_per_hour )
      {  $max_dwdt_lbs_per_hour = $last_max_dwdt_lbs_per_hour; }
   else { $max_dwdt_lbs_per_hour = 60; }
   }

if ( not defined $navigation_button ) { $navigation_button = ""; }
my ($weight_filter_title, $temp_humidity_title);
#turn off refresh if not at end of chart and define variables if not defined
#if ( defined $first ) {}
#else { $first = " "; }
#if ( defined $back1 and $back1) { $metatag_refresh=""; }
#else { $back1 = " "; }
#if ( defined $back7 and $back7 ) { $metatag_refresh=""; }
#else { $back7 = " "; }
#if ( defined $back30 and $back30 ) { $metatag_refresh=""; }
#else { $back30 = " "; }
#if ( defined $forward1 and $forward1 ) { $metatag_refresh=""; }
#else { $forward1 = " "; }
#if ( defined $forward7 and $forward7 ) { $metatag_refresh=""; }
#else { $forward7 = " "; }
#if ( defined $forward30 and $forward30 ) { $metatag_refresh=""; }
#else { $forward30 = " "; }
#if ( defined $last ) {}
#else { $last = " "; }

my ( $temperature_checked, $humidity_checked );
if ( defined $temp_humidity_switch ) { $chart = $temp_humidity_switch; }
#if ( defined $chart  ) { 
   if ( $chart eq "Humidity") { $temp_humidity_switch = "Temperature"; $temperature_checked = ""; $humidity_checked = "checked"; }
   else { $temp_humidity_switch = "Humidity"; $temperature_checked = "checked"; $humidity_checked = ""; }
# }
#else { $chart = "temperature"; $temp_humidity_switch = "Humidity";  $temperature_checked = "checked"; $humidity_checked = ""; }


my ($weight_filter_checked, $weight_filter_raw_checked, $ambient_filter_checked, $ambient_raw,$ambient_filter_raw_checked);

if ( defined $weight_filter_switch ) { $weight_filter = $weight_filter_switch; }

if ( defined $weight_filter  ) { 
   if ( $weight_filter eq "NASA") { $weight_filter_switch = "Raw"; $weight_filter_raw_checked = ""; $weight_filter_checked = "checked";  $weight_filter_title="Display raw weight data.";}
   elsif ( $weight_filter eq "Raw") { $weight_filter_switch = "NASA"; $weight_filter_raw_checked = "checked"; $weight_filter_checked = ""; $weight_filter_title="Filters out big weight changes (manipulation, swarms). Distorts hive weight by amount of sudden weight change.";}
 }
else { $weight_filter = "Raw"; $weight_filter_switch = "NASA";  $weight_filter_raw_checked = "checked"; $weight_filter_checked = ""; $weight_filter_title="Filters out big weight changes (manipulation, swarms). Distorts hive weight by amount of sudden weight change.";}

if ( defined  $ambient_filter_switch ) { 
   if ( $ambient_filter_switch eq "Filtered" ) { $ambient_raw = 0; $ambient_filter_raw_checked = ""; $ambient_filter_checked = "checked";}
   else { $ambient_raw = 1; $ambient_filter_raw_checked = "checked"; $ambient_filter_checked = ""; }
 }
else { $ambient_raw = 0;  $ambient_filter_raw_checked = ""; $ambient_filter_checked = "checked"; }


if ( defined  $download ) { 
   if ( $download eq "Download" ) { $download_checked = "checked";}
   else { $download = 0; $download_checked = ""; }
 }
else { $download = 0;   $download_checked = ""; }

if ( defined  $midnight ) { 
   if ( $midnight eq "Midnight" ) { $midnight_checked = "checked";}
   else { $midnight= 0; $midnight_checked = ""; }
 }
else { $midnight = 0;   $midnight_checked = ""; }

select_data_source();
query_hive_parameters();
calculate_dates();
query_weather_station();
query_last_hive_data();
query_max_min_hive_data();

print "Content-type: text/html\n\n";

my ($header_bg_color,  $status_string);

if ( $status == 5 ) {$header_bg_color = "#80FF80"; $status_string="";}
elsif ( $status == 4 ) {$header_bg_color = "#FFD401"; $status_string="<b><font size=+1>HIVE UNDERGOING TESTING</font></b><br>";}
elsif ( $status == 3 ) {$header_bg_color = "#FFD401"; $status_string="<b><font size=+1>HIVE UNDER CONSTRUCTION</font></b><br>";}
my $wx_info = "Weather conditions at $weather_station_location at $end_time";
my $end_date = $end_time;
my $hidden_start_time = $start_time;
my $hidden_end_time   = $end_time;
$hive_id =~ s/ /%20/g;
$hidden_start_time =~ s/ /%20/g;
$hidden_end_time =~ s/ /%20/g;
$weight_filter =~ s/ /%20/g;
$midnight =~ s/ /%20/g;
$width =~ s/ /%20/g;
$height =~ s/ /%20/g;
my $width2 = $width+300;
$width2 = $width . "px";
my $hive_bg="#FFCC66";
my $hive_ambient_bg="#80FF80";
my $wx_bg="#66CCFF";
my $number_of_days_formated = sprintf '%6.2f',$number_of_days;
my $display;
my $dropdown_chart_select;

chart_select_list();

if ($download)
{
$display="<iframe src=hive_graph3wDownload.pl?hive_id=$hive_id&begin=$hidden_start_time&end=$hidden_end_time&chart=$chart&weight_filter=$weight_filter&nasa_weight_dwdt=$max_dwdt_lbs_per_hour&midnight=$midnight&width=$width&height=$height&download=$download&download_file_format=$download_file_format
 width=\"100%\" height=\"350px\" frameborder=\"0\" scrolling=\"yes\">
</iframe>"
}
else {
$display="<img src=hive_graph3wDownload.pl?hive_id=$hive_id&begin=$hidden_start_time&end=$hidden_end_time&chart=$chart&weight_filter=$weight_filter&nasa_weight_dwdt=$max_dwdt_lbs_per_hour&midnight=$midnight&width=$width&height=$height alt=\"$alt\" title=\"$title\">";
}


#$display="";

my $web_page = <<EOT;
<html>
<head>
   <title>HiveTool: $html_title</title>
   <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=ISO-8859-1">
   <meta name="description" content="Monitor hive weight, temperature, humidity with computer and electronic scale">
   <META name="keywords" content="beehive bee hive scale hivetool monitor data computer computerized electronic scalehive data logger">
   <meta name="robots" CONTENT="all">
   $metatag_refresh
   <META HTTP-EQUIV="CACHE-CONTROL" CONTENT="NO-CACHE">
   <META HTTP-EQUIV="PRAGMA" CONTENT="NO-CACHE">
   <META HTTP-EQUIV="EXPIRES" CONTENT="Mon, 22 Jul 2002 11:12:01 GMT">
</head>
<body bgcolor=#EDEEEB>
 <form  name="FORM" method="get" action="hive_stats3wDownload.pl">
    <input style="overflow: visible !important; height: 0 !important; width: 0 !important; margin: 0 !important; border: 0 !important; padding: 0 !important; display: block !important;" type="submit" value="Submit">
  <center>
  <table width=100% bgcolor=$header_bg_color>
   <tr><td width=30%>
        <input type="submit" title="Go to beginning" name="navigation_button" value="<<">
        <input type="submit" title="Go back 30 days" name="navigation_button" value="<30">
        <input type="submit" title="Go back 7 days" name="navigation_button" value="<7">
        <input type="submit" title="Go back 1 day" name="navigation_button" value="<">
<b><font size=+0>$dropdown_chart_select</font></b>
   </td><td align=center>
$status_string
<b><font size=+0>$dropdown_hive_select</font></b>
   </td><td width=25%>
        <input type="submit" title="$weight_filter_title" name="weight_filter_switch" style="color: red" value="$weight_filter_switch">
        <input type="submit" title="Go forward 1 day" name="navigation_button" value=">">
        <input type="submit" title="Go forward 7 days" name="navigation_button" value="7>">
        <input type="submit" title="Go forward 30 days"  name="navigation_button" value="30>">
        <input type="submit" title="Go to end"  name="navigation_button" value=">>">
        <input type="hidden" name="start_time" value="$start_time">
        <input type="hidden" name="end_time" value="$end_time">
        <input type="hidden" name="hive_id" value="$hive_id">
        <input type="hidden" name="number_of_days" value="$number_of_days">
        <input type="hidden" name="last_max_dwdt_lbs_per_hour" value="$max_dwdt_lbs_per_hour">
   </td></tr>
 </table>

$display
EOT
$web_page .= <<EOT;

<table align=center border=1>
 <tr>
   <td></td>
   <td bgcolor=red>Weight</td>
   <td bgcolor=$hive_bg>Temp</td>
   <td bgcolor=$hive_bg>Humidity</td>
   <td bgcolor=$hive_ambient_bg>Temp</td>
   <td bgcolor=$hive_ambient_bg>Humidity</td>
   <td bgcolor=$wx_bg>Temp</td>
   <td bgcolor=$wx_bg>Humidity</td>
   <td bgcolor=$wx_bg>Wind</td>
   <td bgcolor=$wx_bg>Gusts</td>
   <td bgcolor=$wx_bg>Direction</td>
   <td bgcolor=$wx_bg>Dewpoint</td>
   <td bgcolor=$wx_bg>Pressure</td>
   <td bgcolor=$wx_bg>Rain</td>
 </tr>

EOT
$web_page .= <<EOT;

 <tr align=right>
   <td>Last</td>
   <td bgcolor=red>$last_weight lb.</td>
   <td bgcolor=$hive_bg>$last_temperature °F</td>
   <td bgcolor=$hive_bg>$last_humidity %</td>
   <td bgcolor=$hive_ambient_bg>$last_ambient_temperature °F</td>
   <td bgcolor=$hive_ambient_bg>$last_ambient_humidity %</td>
   <td bgcolor=$wx_bg>$last_wx_temp_f °F</td>
   <td bgcolor=$wx_bg>$last_wx_relative_humidity %</td>
   <td bgcolor=$wx_bg>$last_wx_wind_speed mph</td>
   <td bgcolor=$wx_bg>$last_wx_wind_gust mph</td>
   <td bgcolor=$wx_bg>$last_wx_wind_direction</td>
   <td bgcolor=$wx_bg>$last_wx_dewpoint °F</td>
   <td bgcolor=$wx_bg>$last_wx_pressure mb</td>
   <td bgcolor=$wx_bg>$last_wx_rain in.</td>
 </tr>
EOT
$max_wx_rain = sprintf '%6.2f',$max_wx_rain;
$min_wx_rain = sprintf '%6.2f',$min_wx_rain;
$avg_wx_rain = sprintf '%6.2f',$avg_wx_rain;

$web_page .= <<EOT;
 <tr align=right>
   <td>Max</td>
   <td bgcolor=red>$max_weight lb.</td>
   <td bgcolor=$hive_bg>$max_temperature °F</td>
   <td bgcolor=$hive_bg>$max_humidity %</td>
   <td bgcolor=$hive_ambient_bg>$max_ambient_temperature °F</td>
   <td bgcolor=$hive_ambient_bg>$max_ambient_humidity %</td>
   <td bgcolor=$wx_bg>$max_wx_temp_f °F</td>
   <td bgcolor=$wx_bg>$max_wx_relative_humidity %</td>
   <td bgcolor=$wx_bg>$max_wx_wind_mph mph</td>
   <td bgcolor=$wx_bg>$max_wx_wind_gust_mph mph</td>
   <td bgcolor=$wx_bg>$max_wx_wind_degrees</td>
   <td bgcolor=$wx_bg>$max_wx_dewpoint °F</td>
   <td bgcolor=$wx_bg>$max_wx_pressure mb</td>
   <td bgcolor=$wx_bg>$max_wx_rain in.</td>
 </tr>
EOT
$web_page .= <<EOT;
 <tr align=right>
   <td>Min</td>
   <td bgcolor=red>$min_weight lb.</td>
   <td bgcolor=$hive_bg>$min_temperature °F</td>
   <td bgcolor=$hive_bg>$min_humidity %</td>
   <td bgcolor=$hive_ambient_bg>$min_ambient_temperature °F</td>
   <td bgcolor=$hive_ambient_bg>$min_ambient_humidity %</td>
   <td bgcolor=$wx_bg>$min_wx_temp_f °F</td>
   <td bgcolor=$wx_bg>$min_wx_relative_humidity %</td>
   <td bgcolor=$wx_bg>$min_wx_wind_mph mph</td>
   <td bgcolor=$wx_bg>$min_wx_wind_gust_mph mph</td>
   <td bgcolor=$wx_bg>$min_wx_wind_degrees</td>
   <td bgcolor=$wx_bg>$min_wx_dewpoint °F</td>
   <td bgcolor=$wx_bg>$min_wx_pressure mb</td>
   <td bgcolor=$wx_bg>$min_wx_rain in.</td>
 </tr>
EOT
$web_page .= <<EOT;
 <tr align=right>
   <td>Avg</td>
   <td bgcolor=red>$avg_weight lb.</td>
   <td bgcolor=$hive_bg>$avg_temperature °F</td>
   <td bgcolor=$hive_bg>$avg_humidity %</td>
   <td bgcolor=$hive_ambient_bg>$avg_ambient_temperature °F</td>
   <td bgcolor=$hive_ambient_bg>$avg_ambient_humidity %</td>
   <td bgcolor=$wx_bg>$avg_wx_temp_f °F</td>
   <td bgcolor=$wx_bg>$avg_wx_relative_humidity %</td>
   <td bgcolor=$wx_bg>$avg_wx_wind_mph mph</td>
   <td bgcolor=$wx_bg>$avg_wx_wind_gust_mph mph</td>
   <td bgcolor=$wx_bg>$avg_wx_wind_degrees</td>
   <td bgcolor=$wx_bg>$avg_wx_dewpoint °F</td>
   <td bgcolor=$wx_bg>$avg_wx_pressure mb</td>
   <td bgcolor=$wx_bg>$avg_wx_rain in.</td>
 </tr>
 <tr>
   <td></td>
   <td bgcolor=$hive_bg colspan=3 align=center>Inside Hive</td>
   <td bgcolor=$hive_ambient_bg colspan=2 align=center>Outside Hive</td>
   <td bgcolor=$wx_bg colspan=8 align=center>$wx_info</td>
 </tr>

</table>

EOT
$web_page .= <<EOT;


<table align=center>
 <tr>
  <td>

<table>
 <tr>
 <td align=right>Weight Filter:</td>
 <td><input type="radio" name="weight_filter" value="Raw" $weight_filter_raw_checked>Raw<input type="radio" name="weight_filter" value="NASA" $weight_filter_checked>NASA</td>
 </tr>
 
 <tr>
 <td colspan=2 align=right>Threshold (lbs/hr): <input type="text" maxlength="6" size="6" name="max_dwdt_lbs_per_hour"> $max_dwdt_lbs_per_hour</td>
 </tr>

 <!--tr>
 <td align=right>Ambient Filter:</td>
 <td><input type="radio" name="ambient_filter_switch" value="Raw" $ambient_filter_raw_checked>Raw<input type="radio" name="ambient_filter_switch" value="Filtered" $ambient_filter_checked>Filtered</td>
 </tr-->
 <tr>
 <td align=right>Only sample at:</td>
 <td><input type="checkbox" name="midnight" value="Midnight" $midnight_checked>Midnight</td>
 </tr>
</table>
</td>

<td width=25px></td>

<td>
<table>
 <tr>
 <td align=right>Number of Days:</td>
 <td><input type="text" name="days"> $number_of_days_formated</td>
 </tr>

 <tr>
 <td align=right>Begin Date:</td>
 <td><input type="date" title="Graph start date"  name="begin"> $start_time</td>
 </tr>
 <tr>
 <td align=right>End Date:</td>
 <td><input type="date" title="Graph end date"  name="end"> $end_time</td>
 </tr>
</table>
</td>

<td width=25px></td>

<td>
<table>
 <tr>
 <td align=right>Chart:</td>
 <td><input type="radio" name="chart" value="Temperature" $temperature_checked>Temperature<input type="radio" name="chart" value="Humidity" $humidity_checked>Humidity</td>
 </tr>
 <tr>
 <td align=right>Download:</td>
 <td><input type="checkbox" name="download" value="Download" $download_checked>

    <!--input type="radio" name="download_data_format" value="nasa" checked>NASA Honey Bee Net
    <input type="radio" name="download_data_format" value="raw">raw<br-->

    <input type="radio" name="download_file_format" value="html" checked>HTML
    <input type="radio" name="download_file_format" value="csv">CSV<br>

 </td>
 </tr>
 <tr>
  <td colspan=2 align=center><input type="submit" value="Submit"></td>
 </tr>
 </table>
</td>
</tr>
</table>
</center>
</form>
</body>
</html>
EOT
      
print $web_page;

#
#
# =================================== calculate_dates  ==========================
#
#

sub calculate_dates
{
if ( $debug > 8 ) { print LOG "Calculating first_epoch_date from $start_date\n" }
my $time;                    
my $first_epoch_date;                         # the first data in the database - Don't read before this date
my $last_epoch_date;                          # the last data in the database  - Don't read after this date

# $start_time                                 # user entered date/time begin to start graph
# $end_time                                   # user entered date/time begin to end graph
# $number_of_days                             # user entered numer of days to graph

$first_epoch_date = date_to_epoch($start_date);

($date, $time) = split(" ",$last_update);
$time="23:59:59";
$last_epoch_date =  date_to_epoch("$date $time"); # force last_epoch_date to end of the day so refreshes work

if ( $debug > 8 ) { print LOG "First_epoch_date from $start_date -> $first_epoch_date\n"; }
if ( $debug > 8 ) { print LOG "Last_epoch_date from $last_update -> $last_epoch_date\n"; }
if ( $debug > 8 ) { print LOG "Figuring out start and end times\n" }
if ( $debug > 4 ) { print LOG "start_time_0: $start_time  end_time: $end_time number_of_days: $number_of_days\n"; }

# try to figure out start and end times

if ( $start_time and $end_time ) {                              # if we have a start and end times
   if ( $debug > 8 ) { print LOG "have start time and end times\n" }
   if ( $start_time eq $end_time )                              # if equal, won't work, number_of_days will be zero
      {
      ($date, $time) = split(" ",$end_time);
      if ( $time eq "" ) {$time="23:59:59";}
      $end_time = "$date $time";
      }
   if ( $debug > 8 ) { print LOG "start_time $start_time end_time=$end_time\n" }
   $number_of_days = calc_number_of_days( $end_time, $start_time );
   }

if ( (not $start_time) and (not $end_time) and (not $number_of_days) )
   {                                                             # if no start, end times, or number of days
   if ( $debug > 8 ) { print LOG "start_time, end_time, number_of_days are not defined\n" }
    if ( (not  $last_start_time) and (not  $last_end_time) and (not  $last_number_of_days) )
       {                                                         # and no last times are defined (probably first hit)
       if ( $debug > 8 ) { print LOG "Nothing is defined\n"; }    
       ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
       $year+=1900;
       $mon+=1;
       $end_time = "$year-$mon-$mday 23:59:59";                  # set end_time to end of today
#       $epoch_time = timelocal(0,0,0,$mday,($mon-1),$year);	 # convert end_time to epoch time
       $epoch_time = time();
       $number_of_days = 7;                                      # set default length to a week
       }
    else                                                         
       {                                                         # last times are defined (probably a refresh)
       if ( $debug > 8 ) { print LOG "last_start_time, last_end_time, last_number_of_days are defined\n" }
       $start_time = $last_start_time;
       $end_time = $last_end_time;
       $number_of_days = $last_number_of_days;
       }
    }


if ( ( $start_time) and (not $end_time) and (not $number_of_days) )
   {
   if ( $debug > 8 ) { print LOG "only start_time is defined\n"; }
   if ( $last_number_of_days ) { $number_of_days = $last_number_of_days;}
  else
     {
     if ( $last_end_time ) { $end_time = $last_end_time;}
     else
       {
       ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
       $year+=1900;
       $mon+=1;
       $end_time = "$year-$mon-$mday 23:59:59"; 
       }
   $number_of_days = calc_number_of_days( $end_time, $start_time );
   }
}

if ( ( not $start_time) and (not $end_time) and ( $number_of_days) )
   {
   if ( $debug > 8 ) { print LOG "only number_of_days is defined.  Last_end_time=$last_end_time\n"; }

   if ( $last_end_time )                                               # use last_end_time 
      { 
      ($date, $time) = split(" ",$last_end_time);
      ($year,$mon,$mday) = split("-",$date);
      }
   else                                                                # else use the current time
      {
      ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
      $year+=1900;
      $mon+=1;
      }
   $end_time = "$year-$mon-$mday 23:59:59";                            # set end_time to end of day
   $epoch_time = timelocal(0,0,0,$mday,($mon-1),$year);	               # convert end_time to epoch time

   ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($epoch_time-(($number_of_days-1)*86400));
   $year+=1900;
   $mon+=1;
   $start_time = "$year-$mon-$mday";                         # set start_time to number_of_days ago
   }


if ( ( not $start_time) and ($end_time) and ( not $number_of_days) )
   {                                                        # Only end_time is provided
   if ( $debug > 8 ) { print LOG "only end_time is defined\n"; }

   if ( $last_number_of_days )
      {                                                     # use last_number_of_days 
      $number_of_days = $last_number_of_days;
      }
   else
      {                                                     # use a default value
      $number_of_days = 7;
      }
   }

if ( ( $start_time) and (not $end_time) and ( $number_of_days) )
   {
   if ( $debug > 8 ) { print LOG "start_time and number_of_days are defined\n"; }

   $epoch_time = date_to_epoch($start_time);

   ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($epoch_time+(($number_of_days-1)*86400));
   $year+=1900;
   $mon+=1;
   $end_time = "$year-$mon-$mday $hour:$min:$sec";                         # set end_time to start_time plus number_of_days
   }


if ( $debug > 4 ) { print LOG "start_time_1: $start_time  end_time: $end_time number_of_days: $number_of_days\n"; }

$epoch_time = date_to_epoch($end_time);
if ( $debug > 8 ) { print LOG "before navigation buttons epoch_time: $epoch_time\n"; }

# Were any navigation buttons clicked?

   if ( $navigation_button eq '<<' ) {  $epoch_time = $first_epoch_date+(($number_of_days-1)*86400); }	#convert start_time to epoch time
elsif ( $navigation_button eq '<' ) { $epoch_time -= 86400; }
elsif ( $navigation_button eq '<7' ) { $epoch_time -= 7*86400; }
elsif ( $navigation_button eq '<30' ) { $epoch_time -= 30*86400; }
elsif ( $navigation_button eq '>' ) { $epoch_time += 86400; }
elsif ( $navigation_button eq '7>' ) { $epoch_time += 7*86400; }
elsif ( $navigation_button eq '30>' ) { $epoch_time += 30*86400; }
elsif ( $navigation_button eq '>>' ) { $epoch_time = $last_epoch_date; }

if ( $debug > 8 ) { print LOG "after navigation buttons epoch_time: $epoch_time\n"; }
if ( $debug > 4 ) { print LOG "start_time_1.5: $start_time end_time: $end_time epoch: $epoch_time  number_of_days: $number_of_days\n"; }

# Are the calculated times within the dataset?  If not, clamp to the dataset times.

if ( $epoch_time > $last_epoch_date ) {
        $epoch_time = $last_epoch_date; 
        }

$end_time = epoch_to_date($epoch_time);        
$epoch_time = $epoch_time-(($number_of_days)*86400);


if ( $epoch_time < $first_epoch_date ) {
        $epoch_time = $first_epoch_date;
        }

        
$start_time = epoch_to_date($epoch_time);        
$number_of_days = calc_number_of_days($end_time,$start_time);

if ( $debug > 4 ) { print LOG "start_time_2: $start_time  end_time: $end_time number_of_days: $number_of_days\n"; }

my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = localtime(time);
 $year+=1900;
 $month+=1;
 if ( $month < 10 ) { $month = "0".$month; }
 if ( $day <10 ) { $day = "0".$day; }

# ($date, $time) = split(" ",$end_time);
# if ($date ne $year-$month-$day) {$metatag_refresh="";}

 $date = "$year-$month-$day";
 if ( calc_number_of_days($date, $end_time) > 1 ) {$metatag_refresh="";}
 
 # ### end of figuring out the times.

}
#
# =====================================================================================
#
sub select_data_source
{
my ($database, $user, $password);

if ( $data_source eq "dev" ) 
   {
   $database = "";
   $user = "";
   $password = "";
   }
elsif  ( $data_source eq "prod" )
   {
   $database = "";
   $user = "";
   $password = "";
   }
elsif ( $data_source eq "local" )
   {
   $database = "hivetool_raw:localhost:3306";
   $user = "root";
   $password = "raspberry"; 
   }


$dbh = DBI->connect("DBI:mysql:$database", $user, $password)  or
      badLogin("Your username/password combination was incorrect.");
}

#
# =====================================================================================
#
sub query_hive_parameters
{

 if ( $debug > 8 ) {
     print LOG "read_data \n";
     }

 $sql = "SELECT name,nasa,status,city,state,altitude_feet,weather_station_id, last_update, hive_id, start_date
 FROM  HIVE_PARAMETERS
 WHERE status = 5 or status = 4
 order by name";

  if ( $debug > 8 ) { print LOG "$sql\n" }

     $sth = $dbh->prepare("$sql") or
               htmlDie("Could not prepare query: $sql\n$DBI::errstr\n");

     $rc = $sth->execute or
               htmlDie("Could not execute query: $sql\n$DBI::errstr\n");

$dropdown_hive_select="<select name=\"new_hive_id\" onchange=\"this.form.submit()\">";

      while ( @row = $sth->fetchrow() )
      {
        $hivename = $row[0];
        $nasa = $row[1];
        if ( defined $row[3] ) {$location = "$row[3]";} else { $location = ""; }
        if ( defined $row[4] ) {$location .= ", $row[4]";}
        if ( defined $row[5] ) { $altitude = $row[5]; } else { $altitude = ""; }

      if ( $row[8] != $hive_id )
         {
         $dropdown_hive_select .= "<option  value=\"$row[8]\">$hivename $location - $altitude feet elevation</option>\n";
         }
      else
         {
         $dropdown_hive_select .= "<option  value=\"$row[8]\" selected>$hivename $location - $altitude feet elevation Filter: $weight_filter</option>\n";
         $weather_station_id = $row[6];
         $hive_name = "$hivename $location - $altitude feet elevation Filter: $weight_filter";
         $start_date = $row[9];
         $last_update = $row[7];
         $status = $row[2];
         $alt = "Graph of Hive Weight and $chart $hivename $location $altitude feet elevation";
         $title="Hive $hivename\nWeight and $chart Graph\n$location\n$altitude feet elevation";
         $html_title = $hivename;
         }
      }
$dropdown_hive_select .= "</select>";
}

#
# =====================================================================================
#
sub query_weather_station
{
     if ( defined $weather_station_id and $weather_station_id) {

        $sql = "SELECT name FROM WEATHER_STATIONS WHERE weather_station_id=$weather_station_id";

         if ( $debug > 8 ) { print LOG "$sql\n" }

        $sth = $dbh->prepare("$sql") or
               htmlDie("Could not prepare query: $sql\n$DBI::errstr\n");

        $rc = $sth->execute or
               htmlDie("Could not execute query: $sql\n$DBI::errstr\n");

        @row = $sth->fetchrow();
        $weather_station_location = $row[0];
     }

     if ( not $weather_station_location ) { $weather_station_location="Wunderground"; }
}

#
# =====================================================================================
#
sub query_last_hive_data
{
my ($date, $time) = split(" ",$end_time);
          $sql = "SELECT hive_observation_time_local,
                         hive_weight_lbs,
                         hive_temp_c,
                         hive_humidity,
                         ambient_temp_c,
                         ambient_humidity,
                         wx_temp_f,
                         wx_relative_humidity,
                         wx_wind_degrees,
                         wx_wind_mph,
                         wx_wind_gust_mph,
                         wx_pressure_mb,
                         wx_dewpoint_f,
                         wx_precip_today_in
                   FROM HIVE_DATA 
                   WHERE hive_id = $hive_id and
                         quality > 0 and
                         hive_observation_time_local like \"$date%\"
                order by hive_observation_time_local desc
                   limit 1";

  if ( $debug > 8 ) { print LOG "$sql\n" }

        $sth = $dbh->prepare("$sql") or
               htmlDie("Could not prepare query: $sql\n$DBI::errstr\n");

        $rc = $sth->execute or
               htmlDie("Could not execute query: $sql\n$DBI::errstr\n");

            @row = $sth->fetchrow();

            $last_end_time = $row[0];
            if ( $row[1] eq '' ) {$last_weight = "NULL"; } else { $last_weight = sprintf '%6.2f', $row[1]; }
            if ( $row[2] eq '' ) {$last_temperature = "NULL"; } else { $last_temperature = sprintf '%6.0f', $row[2]*1.8+32; }
            if ( $row[3] eq '' ) {$last_humidity = "NULL"; } else { $last_humidity = sprintf '%6.0f', $row[3]; }
            if ( $row[4] eq '' ) {$last_ambient_temperature = "NULL"; } else { $last_ambient_temperature = sprintf '%6.0f', $row[4]*1.8+32; }
            if ( $row[5] eq '' ) {$last_ambient_humidity = "NULL"; } else { $last_ambient_humidity = sprintf '%6.0f', $row[5]; }
            if ( $row[6] eq '' ) {$last_wx_temp_f = "NULL"; } else { $last_wx_temp_f = sprintf '%6.0f',$row[6]; }
            if ( $row[7] eq '' ) {$last_wx_relative_humidity = "NULL"; } else { $last_wx_relative_humidity = sprintf '%6.0f',$row[7]; }
            if ( $row[8] eq '' ) {$last_wx_wind_direction = "NULL"; } else { $last_wx_wind_direction = sprintf '%6.0f',$row[8]; }
            if ( $row[9] eq '' ) {$last_wx_wind_speed = "NULL"; } else { $last_wx_wind_speed = sprintf '%6.0f',$row[9]; }
            if ( $row[10] eq '' ) {$last_wx_wind_gust = "NULL"; } else { $last_wx_wind_gust = sprintf '%6.0f',$row[10]; }
            if ( $row[11] eq '' ) {$last_wx_pressure = "NULL"; } else { $last_wx_pressure = sprintf '%6.0f',$row[11]; }
            if ( $row[12] eq '' ) {$last_wx_dewpoint = "NULL"; } else { $last_wx_dewpoint = sprintf '%6.0f',$row[12]; }
            if ( $row[13] eq '' ) {$last_wx_rain = "NULL"; } else { $last_wx_rain = $row[13]; }
#            if ( defined  $row[1]) { $ = $row[1]; }
#$last_wx_relative_humidity
#            $last_wx_dewpoint = 0;
#            $last_wx_relative_humidity = 0;
#            $last_wx_pressure = 0;
#            $last_wx_radiation  = 0;
#            $last_wx_evapotranspiration  = 0;
#            $last_wx_vapor_pressure  = 0;
#            $last_wx_rain  = 0;
}


#
# =====================================================================================
#
sub query_max_min_hive_data
{
$sql = "SELECT count(*),
        avg(HIVE_DATA.hive_weight_lbs),
        min(HIVE_DATA.hive_weight_lbs), 
        max(HIVE_DATA.hive_weight_lbs), 
        avg(HIVE_DATA.hive_temp_c),
        min(HIVE_DATA.hive_temp_c), 
        max(HIVE_DATA.hive_temp_c), 
        avg(HIVE_DATA.hive_humidity),
        min(HIVE_DATA.hive_humidity), 
        max(HIVE_DATA.hive_humidity), 
        avg(HIVE_DATA.ambient_temp_c),
        min(HIVE_DATA.ambient_temp_c), 
        max(HIVE_DATA.ambient_temp_c), 
        avg(HIVE_DATA.ambient_humidity),
        min(HIVE_DATA.ambient_humidity), 
        max(HIVE_DATA.ambient_humidity), 
        avg(HIVE_DATA.wx_temp_f),
        min(HIVE_DATA.wx_temp_f), 
        max(HIVE_DATA.wx_temp_f),
        avg(HIVE_DATA.wx_relative_humidity),
        min(HIVE_DATA.wx_relative_humidity), 
        max(HIVE_DATA.wx_relative_humidity),
        avg(HIVE_DATA.wx_wind_degrees),
        min(HIVE_DATA.wx_wind_degrees), 
        max(HIVE_DATA.wx_wind_degrees),
        avg(HIVE_DATA.wx_wind_mph),
        min(HIVE_DATA.wx_wind_mph), 
        max(HIVE_DATA.wx_wind_mph),
        avg(HIVE_DATA.wx_wind_gust_mph),
        min(HIVE_DATA.wx_wind_gust_mph), 
        max(HIVE_DATA.wx_wind_gust_mph),
        avg(HIVE_DATA.wx_pressure_mb),
        min(HIVE_DATA.wx_pressure_mb), 
        max(HIVE_DATA.wx_pressure_mb),
       avg(HIVE_DATA.wx_dewpoint_f),
       min(HIVE_DATA.wx_dewpoint_f), 
       max(HIVE_DATA.wx_dewpoint_f),
       avg(HIVE_DATA.wx_precip_today_in),
       min(HIVE_DATA.wx_precip_today_in), 
       max(HIVE_DATA.wx_precip_today_in)
  FROM  HIVE_DATA
 where HIVE_DATA.hive_observation_time_local >= \"$start_time\"  and
       HIVE_DATA.hive_observation_time_local <= \"$end_time\"  and
       HIVE_DATA.hive_id = $hive_id and
       HIVE_DATA.quality > 0";

  if ( $debug > 8 ) { print LOG "$sql\n" }

        $sth = $dbh->prepare("$sql") or
               htmlDie("Could not prepare query: $sql\n$DBI::errstr\n");

        $rc = $sth->execute or
               htmlDie("Could not execute query: $sql\n$DBI::errstr\n");

    @row = $sth->fetchrow();

         if ( defined $row[1] ) { $avg_weight = sprintf '%6.2f', $row[1]; }
         if ( defined $row[2] ) { $min_weight = sprintf '%6.2f', $row[2]; }
         if ( defined $row[3] ) { $max_weight = sprintf '%6.2f', $row[3]; }

         if ( defined $row[4] ) { $avg_temperature = sprintf '%6.0f', $row[4]*1.8+32; }
         if ( defined $row[5] ) { $min_temperature = sprintf '%6.0f', $row[5]*1.8+32; }
         if ( defined $row[6] ) { $max_temperature = sprintf '%6.0f', $row[6]*1.8+32; }

         if ( defined $row[10] ) { $avg_humidity = sprintf '%6.0f', $row[7]; }
         if ( defined $row[11] ) { $min_humidity = sprintf '%6.0f', $row[8]; }
         if ( defined $row[12] ) { $max_humidity = sprintf '%6.0f', $row[9]; }

         if ( defined $row[7] ) { $avg_ambient_temperature = sprintf '%6.0f', $row[10]*1.8+32; }
         if ( defined $row[8] ) { $min_ambient_temperature = sprintf '%6.0f', $row[11]*1.8+32; }
         if ( defined $row[9] ) { $max_ambient_temperature = sprintf '%6.0f', $row[12]*1.8+32; }

         if ( defined $row[10] ) { $avg_ambient_humidity = sprintf '%6.0f', $row[13]; }
         if ( defined $row[11] ) { $min_ambient_humidity = sprintf '%6.0f', $row[14]; }
         if ( defined $row[12] ) { $max_ambient_humidity = sprintf '%6.0f', $row[15]; }

         $avg_wx_temp_f = sprintf '%6.0f', $row[16];
         $min_wx_temp_f = sprintf '%6.0f', $row[17];
         $max_wx_temp_f = sprintf '%6.0f', $row[18];
         $avg_wx_relative_humidity = sprintf '%6.0f', $row[19];
         $min_wx_relative_humidity = sprintf '%6.0f', $row[20];
         $max_wx_relative_humidity = sprintf '%6.0f', $row[21];
         $avg_wx_wind_degrees = sprintf '%6.0f', $row[22];
         $min_wx_wind_degrees = sprintf '%6.0f', $row[23];
         $max_wx_wind_degrees = sprintf '%6.0f', $row[24];
         $avg_wx_wind_mph = sprintf '%6.0f', $row[25];
         $min_wx_wind_mph = sprintf '%6.0f', $row[26];
         $max_wx_wind_mph = sprintf '%6.0f', $row[27];
         $avg_wx_wind_gust_mph = sprintf '%6.0f', $row[28];
         $min_wx_wind_gust_mph = sprintf '%6.0f', $row[29];
         $max_wx_wind_gust_mph = sprintf '%6.0f', $row[30];
         $avg_wx_dewpoint = sprintf '%6.0f', $row[34];
         $min_wx_dewpoint = sprintf '%6.0f', $row[35];
         $max_wx_dewpoint = sprintf '%6.0f', $row[36];
         $avg_wx_pressure = sprintf '%6.0f', $row[31];
         $min_wx_pressure = sprintf '%6.0f', $row[32];
         $max_wx_pressure = sprintf '%6.0f', $row[33];
         $avg_wx_rain = sprintf '%6.2f', $row[37];
         $min_wx_rain = sprintf '%6.2f', $row[38];
         $max_wx_rain = sprintf '%6.2f', $row[39];
}

#
# =====================================================================================
#

sub date_to_epoch
    {
    my ($date, $time, $year, $month, $day, $hours, $minutes, $seconds)=(0,0,0,0,0,0,0,0); 
    ($date, $time) = split(" ",$_[0]);
   if ( $debug > 8 ) { print LOG "sub date_to_epoch date=$date time=$time  " }
    if ( not $time ) {$time="00:00:00";}
    ($year,$month,$day) = split("-",$date);
    ($hours,$minutes,$seconds) = split(":",$time);
    my $epoch_date = timelocal($seconds, $minutes, $hours,$day,($month-1),$year);
    if ( $debug > 8 ) { print LOG "epoch=$epoch_date\n" }
    return $epoch_date;
    }
#
# =====================================================================================
#


sub epoch_to_date
    {
    my ($date, $time, $year, $month, $day, $hours, $minutes, $seconds,$wday,$yday,$isdst); 
   ($seconds,$minutes,$hours,$day,$month,$year,$wday,$yday,$isdst) = localtime($_[0]);
   $year+=1900;
   $month+=1;
   if ( $month < 10 ) { $month = "0".$month; }
   if ( $day <10 ) { $day = "0".$day; }
   $date = "$year-$month-$day $hours:$minutes:$seconds";                         
   return $date;
   }
#
# =====================================================================================
#

sub calc_number_of_days
   {
   my ($date, $time, $year, $month, $day, $hours, $minutes, $seconds)=(0,0,0,0,0,0,0,0); 
   ($date, $time) = split(" ",$_[0]);
    if ( not $time ) {$time="23:59:59";}
   ($year,$month,$day) = split("-",$date);
   ($hours,$minutes,$seconds) = split(":",$time);
   my $epoch_time = timelocal($seconds,$minutes,$hours,$day,($month-1),$year);	#convert end_time to epoch time

   ($date, $time) = split(" ",$_[1]);               #calculate the number of days
   ($year,$month,$day) = split("-",$date);
   ($hours,$minutes,$seconds) = split(":",$time);

   my $number_of_days = (( $epoch_time - timelocal($seconds,$minutes,$hours,$day,($month-1),$year) )/86400);      # + 1;	
   return $number_of_days;
   }
#
# =====================================================================================
#

sub chart_select_list
   {
   $dropdown_chart_select="<select name=\"chart\" onchange=\"this.form.submit()\">";
   $dropdown_chart_select .= "<option  value=\"Temperature\">Temperature</option>\n";
   $dropdown_chart_select .= "<option  value=\"Humidity\">Humidity</option>\n";
   $dropdown_chart_select .= "<option  value=\"Temp/Humidity\">Temp/Humidity</option>\n";
   $dropdown_chart_select .= "</select>";
   }

if ($debug ) { close LOG; }

1;
