#!/usr/bin/perl -w
use XML::Parser;
use FileHandle;
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use HTML::LinkExtor; # allows you to extract the links off of an HTML page.
use DBI;

use strict;

sub parse_line($);
sub parse_picks($);
sub read_scores($);
sub write_html($);
sub fill_db();

#
my %picks;
my %games;
my %team2gameid;
my @titles;
my $week_num;
my $season;

my $dir_name = $ARGV[0];

my @files = <$dir_name/*>;

foreach my $file (@files)
{
   if ($file =~ /week/ and -d $file )
   {

      my $line_filename = "$file\/line.txt";
      my $picks_filename = "$file\/Pick10.csv";
      my $html_filename = "$file\/pick10.html";
      print "$html_filename\n";
      read_scores($file);
      parse_picks($picks_filename);
      parse_line($line_filename);
      if ($week_num eq 17)
      {
         fill_db();
      }
      %games = ();
      %picks = ();
      %team2gameid = ();
      @titles = ();
   }

#write_html($html_filename);
}

sub parse_line($)
{
   my ($filename) = @_;

   open FILE, "<$filename" or die $!;

   while ( <FILE> )
   {
      if ( $_ =~ /(\S+)\s+(\S+)\s+(\S+)/ )
      {
         my $winner = uc($1);
         my $loser  = uc($3);
         my $spread = $2;

         my $id = $team2gameid{$winner};

         if ( defined( $id ) and exists( $games{$id} ) )
         {
            if ( $games{$id}{'h'} eq $winner )
            {
               $games{$id}{'spread'} = 1*$2;
            }
            else
            {
               $games{$id}{'spread'} = -1*$2;
            }
         }
         else
         {
            print "$winner vs $loser error\n";
         }
      }
   }
}


sub parse_picks($)
{
   my ($filename) = @_;
   open FILE, "<$filename" or die "Opening $filename: $!";

#eat unused lines
   my $line = <FILE>;
   $line = <FILE>;
   $line = <FILE>;

   @titles = split(/,/, $line);

   shift @titles;

   while ( <FILE> )
   {
      my @picks = split(/,/, $_);
      my $name = shift @picks;

      $name =~ s/\"//g;

      if ( $name ne "" )
      {
         $picks{$name} = {};

         foreach my $title (@titles)
         {
            if ( $title =~ /\d+/ )
            {
               $picks{$name}{$title} = uc (shift @picks);
            }
            else
            {
               $picks{$name}{$title} = shift @picks;
            }
            $picks{$name}{$title} =~ s/\"//g;
         }
      }
      else
      {
         last;
      }
#print $_;
   }
   close FILE;
}

sub read_scores($)
{
   my ($week) = @_;

   my $browser = LWP::UserAgent->new();
   $browser->timeout(10);

   my $request = HTTP::Request->new(GET => 'http://www.nfl.com/liveupdate/scorestrip/ss.xml' );
   my $response = $browser->request($request);
   my $contents = $response->content();

#print "$contents\n";
#

   my $parser = new XML::Parser(Handlers => {Start => \&handle_week});

   $parser->parse($contents);

   my $tmp_week = 0;
   if ($week =~ /week(\d+)/)
   {
      $tmp_week = int($1);
   }

   $parser->setHandlers(Start => \&handle_games);
   my $filename = "$week\/scores.xml";
   if ($tmp_week eq $week_num)
   {
      $parser->parse($contents);

      open FILE, ">$filename" or die $!;
      print FILE "$contents";
      close FILE;
   }
   else
   {
      $week_num = $tmp_week;
      if ( -f $filename )
      {
         $parser->parsefile($filename);
      }
   }
}

sub handle_games()
{
   my ($p, $elt, %attrs) = @_;

   if ($elt eq 'g')
   {
#print "$attrs{'h'}\n";
      my $id = $attrs{'eid'};
      $games{$id} = {};

      $games{$id}{'h'} = (uc($attrs{'h'} eq 'ARI')) ? 'ARZ' : uc($attrs{'h'});
      $games{$id}{'hs'} = $attrs{'hs'};

      $games{$id}{'v'} = (uc($attrs{'v'} eq 'ARI')) ? 'ARZ' : uc($attrs{'v'});
      $games{$id}{'vs'} = $attrs{'vs'};

      $games{$id}{'q'} = $attrs{'q'};
      $games{$id}{'d'} = $attrs{'d'};
      $games{$id}{'t'} = $attrs{'t'};

      $team2gameid{$games{$id}{'h'}} = $id;
      $team2gameid{$games{$id}{'v'}} = $id;
   }
   return;
}

sub handle_week()
{
   my ($p, $elt, %attrs) = @_;

   if ($elt eq 'gms')
   {
      $week_num = $attrs{'w'};
      $season = $attrs{'y'};
   }
}

sub fill_db()
{
   my $dbh = DBI->connect('DBI:mysql:pick10', 'dan', '') 
      or die "Could not connect to database: $DBI::errstr";

   my $sth = $dbh->prepare("INSERT INTO games (week, year, gametime, day, hometeam, homescore, visitorteam, visitorscore, spread, quarter) VALUE (?,?,?,?,?,?,?,?,?,?)");

   print "$week_num, $season\n";
   
   foreach my $key (keys %games)
   {
# convert the quarter into the correct numeric value
      my $quarter = $games{$key}{'q'};
      my $input = 0;
      if ($quarter =~ "F") { $input = 5; }
      elsif ($quarter =~ "1") { $input = 1; }
      elsif ($quarter =~ "2") { $input = 2; }
      elsif ($quarter =~ "3") { $input = 3; }
      elsif ($quarter =~ "4") { $input = 4; }

# create a data-time entry for this game
      my $year = substr($key, 0, 4);
      my $month = substr($key, 4, 2);
      my $day = substr($key, 6, 2);
      my $time = $games{$key}{'t'};
      $time =~ /^(\d+):(\d+)$/;
      my $hr = $1;
      my $min = $2;

      my $datetime = sprintf("%04d-%02d-%02d %02d:%02d:00", $year, $month, $day, $hr, $min);

#insert into database
      $sth->execute($week_num, $season, $datetime, $games{$key}{'d'}, $games{$key}{'h'}, $games{$key}{'hs'}, $games{$key}{'v'}, $games{$key}{'vs'}, $games{$key}{'spread'}, $input); 
   }

   my $player_query = $dbh->prepare("SELECT id FROM players WHERE name = ?");
   my $player_insert = $dbh->prepare("INSERT INTO players (name) VALUE (?)");
   my $game_query = $dbh->prepare("SELECT id, hometeam, visitorteam FROM games WHERE ( week = ? AND year = ? and ( hometeam = ? OR visitorteam = ? ) )");

   foreach my $name (keys %picks)
   {
      my $player_id = 0;
      my $result = $player_query->execute($name);
      if ( $player_query->rows == 0 )
      {
         $player_insert->execute($name);
         $result = $player_query->execute($name);
      }
      my $row = $player_query->fetchrow_hashref();

      $player_id = $row->{'id'};

      $player_query->finish;

      my @gameIDs = ();
      my @gamePicks = ();
      for (my $i = 1; $i <= 10; $i++)
      {
         my $team = $picks{$name}{$i};
         $result = $game_query->execute($week_num, $season, $team, $team);
      
         if ( $game_query->rows == 0 )
         {
            $gameIDs[$i-1] = 0;
            $gamePicks[$i-1] = 0;
         }
         else
         {
            my $row = $game_query->fetchrow_hashref();
            $gameIDs[$i-1] = $row->{'id'};
            if ( $team eq $row->{'hometeam'} )
            {
               $gamePicks[$i-1] = 1;
            }
            else
            {
               $gamePicks[$i-1] = 2;
            }
         }

         $game_query->finish;
      }
      
      my $pick_statement = $dbh->prepare("INSERT INTO picks (playerid, week, year, 10pointgame,10pointpick,9pointgame,9pointpick,8pointgame,8pointpick,7pointgame,7pointpick,6pointgame,6pointpick,5pointgame,5pointpick,4pointgame,4pointpick,3pointgame,3pointpick,2pointgame,2pointpick,1pointgame,1pointpick) VALUE (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");

      $pick_statement->execute($player_id, $week_num, $season,
                                          $gameIDs[9], $gamePicks[9], 
                                           $gameIDs[8], $gamePicks[8], 
                                           $gameIDs[7], $gamePicks[7], 
                                           $gameIDs[6], $gamePicks[6], 
                                           $gameIDs[5], $gamePicks[5], 
                                           $gameIDs[4], $gamePicks[4], 
                                           $gameIDs[3], $gamePicks[3], 
                                           $gameIDs[2], $gamePicks[2], 
                                           $gameIDs[1], $gamePicks[1], 
                                           $gameIDs[0], $gamePicks[0] );
   }

   $dbh->disconnect();
}

sub write_html($)
{
   my ($filename) = @_;
   open HTML, ">$filename" or die $!;

   print HTML "<html>\n<table>\n";
   print HTML "<tr>\n<th></th>";

   foreach my $title ( @titles )
   {
      print HTML "<th>$title</th>";
   }

   print HTML "</tr>\n";

   foreach my $name ( sort keys %picks )
   {
      print HTML "<tr><td>$name</td>";

      my $total = 0;
      foreach my $title (@titles)
      {
         if ( $title =~ /\d+/ and
               exists $team2gameid{$picks{$name}{$title}} )
         {
            my $id = $team2gameid{$picks{$name}{$title}};
            my $diff = $games{$id}{'hs'} - $games{$id}{'vs'};

            if ($games{$id}{'q'} eq "P")
            {
               print HTML "<td bgcolor=\"white\">$picks{$name}{$title}</td>";
            }
            elsif ( $games{$id}{'h'} eq $picks{$name}{$title} )
            {
               if ( $diff > $games{$id}{'spread'} )
               {
                  print HTML "<td bgcolor=\"green\">$picks{$name}{$title}</td>";
                  $total += $title;
               }
               elsif ( $diff < $games{$id}{'spread'} )
               {
                  print HTML "<td bgcolor=\"red\">$picks{$name}{$title}</td>";
               }
               else
               {
                  print HTML "<td bgcolor=\"blue\">$picks{$name}{$title}</td>";
                  $total += $title/2.0;
               }
            }
            else
            {
               if ( $diff < $games{$id}{'spread'} )
               {
                  print HTML "<td bgcolor=\"green\">$picks{$name}{$title}</td>";
                  $total += $title;
               }
               elsif ( $diff > $games{$id}{'spread'} )
               {
                  print HTML "<td bgcolor=\"red\">$picks{$name}{$title}</td>";
               }
               else
               {
                  print HTML "<td bgcolor=\"blue\">$picks{$name}{$title}</td>";
                  $total += $title/2.0;
               }
            }
         }
         elsif ( $title =~ /TOT/  )
         {
            $picks{$name}{'total'} = $total;
            print HTML "<td>$total</td>";
         }
         else
         {
            print HTML "<td>$picks{$name}{$title}</td>";
         }
      }
      print HTML "</tr>\n";
   }
   print HTML "</table>\n";


   print HTML "<table>\n";
   foreach my $name ( sort {$picks{$b}{'total'} <=> $picks{$a}{'total'}} keys %picks )
   {
      print HTML "<tr><td>$name</td><td>$picks{$name}{'total'}</td></tr>\n";
   }
   print HTML "</table>\n";
   print HTML "</html>\n";

   close HTML;
}


