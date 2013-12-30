#! /usr/bin/perl -w
use strict; 
use Time::Local;
use CGI;

print <<END;
Content-Type: text/html; charset=iso-8859-1

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN">
<html>
<head>
   <title>HiveTool</title>
   <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=ISO-8859-1">
   <meta name="description" content="HiveTool:Comment">
   <META name="keywords" content="">
   <meta name="robots" CONTENT="all">
</head>


<body>
END

my $query = new CGI;
$query->import_names('FORM');

my $comment = $query->param('comment');
open LOG, ">>", "/home/hivetool/hive.log" or die $!;

#`echo -n " \"$comment\" " >> /home/hivetool/hive.test.log`;
print LOG ' "'.$comment.'"';
close LOG;

print "<table align=center>";
print "<tr><td align=center>";
print "Comment:";
print "</td></tr>";

print "<tr><td align=center>";
print "<b>\"$comment\"</b>";
print "</td></tr>";

print "<tr><td align=center>";
print "has been appended to the log:";
print "</td></tr>";

print "<tr><td>";
print "<pre>\n";

foreach $_ (`tail -n 5 /home/hivetool/hive.log`)
      {
       print "$_";
       }
print "</pre>\n";
print "</td></tr></table>";

print <<END;
</body>
</html>
END
1; 
