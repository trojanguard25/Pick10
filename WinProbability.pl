#!/usr/bin/perl -w
use XML::Parser;
use FileHandle;
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use HTML::LinkExtor; # allows you to extract the links off of an HTML page.

use strict;

sub parse_line($);
sub parse_picks($);
sub read_scores($);
sub write_html($);

#
my %picks;
my %games;
my %team2gameid;
my @titles;
my $week_num;
my $year;
my $PermutationCount = 0;

my $dir_name = $ARGV[0];
my $line_filename = "$dir_name\/line.txt";
my $picks_filename = "$dir_name\/pick10.csv";
my $html_filename = "$dir_name\/pick10.html";

read_scores($dir_name);
parse_picks($picks_filename);
parse_line($line_filename);

#write_html($html_filename);

PermuteGames();

print "Total number of permutations: $PermutationCount\n";
print "/************************************************/\n";

foreach my $key (sort { $picks{$b}{'wins'} <=> $picks{$a}{'wins'} } keys %picks)
{
   print "$key\t$picks{$key}{'wins'}\n";
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
   open FILE, "<$filename" or die $!;

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
               #$picks{$name}{$title} = uc (shift @picks);
               my $team = uc (shift @picks);
               $team =~ s/\"//g;
               $picks{$name}{$team} = $title;
            }
            #else
            #{
            #   $picks{$name}{$title} = shift @picks;
            #}
            #$picks{$name}{$title} =~ s/\"//g;
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
      $parser->parsefile($filename);
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
      $year = $attrs{'y'};
   }
}

sub PermuteGames()
{
   my @GamesArr = ();
   my @ResultsArr = ();
   foreach my $id (keys %games)
   {
      my $game_ref = \$games{$id};
      push @GamesArr, \$games{$id};
      #my $val = $$game_ref{'h'};
      #print "${$$game_ref}{'h'}\n";
      #print "$val\n";
   } 
   PermuteRecurse(\@GamesArr, \@ResultsArr);
}

sub PermuteRecurse()
{
   my ($gamesLeft, $gamesPicked) = @_;

   if (@$gamesLeft)
   {
      my $game = pop @$gamesLeft;
      #print "${%$games}{'h'}\n";

      if ( ${$$game}{'q'} eq 'F' )
      {
         if ( ${$$game}{'hs'} - ${$$game}{'vs'} > ${$$game}{'spread'})
         {
            push @$gamesPicked, ${$$game}{'h'};
         }
         else
         {
            push @$gamesPicked, ${$$game}{'v'};
         }
         PermuteRecurse($gamesLeft, $gamesPicked);
         pop @$gamesPicked;
      }
      else
      {
         push @$gamesPicked, ${$$game}{'h'};
         PermuteRecurse($gamesLeft, $gamesPicked);
         pop @$gamesPicked;
         push @$gamesPicked, ${$$game}{'v'};
         PermuteRecurse($gamesLeft, $gamesPicked);
         pop @$gamesPicked;
      }
      push @$gamesLeft, $game;
   }
   else
   {
      #print @$gamesPicked;

      $PermutationCount++;
      my %score = ();
      foreach my $team (@$gamesPicked)
      {
         foreach my $key (keys %picks)
         {
            if (exists $picks{$key}{$team})
            {
               unless (exists $score{$key})
               {
                  $score{$key} = 0;
               }
               $score{$key} += $picks{$key}{$team};
            }
            unless (exists $picks{$key}{'wins'})
            {
               $picks{$key}{'wins'} = 0;
            }
         }
      }
      my $max = 0;
      foreach my $key (keys %score)
      {
         if (exists($score{$key}) and $score{$key} >= $max)
         {
            $max = $score{$key};
            print "$key = $max\n";
         }
      }
      print "$max\n";
      foreach my $key (keys %score)
      {
         if (exists($score{$key}) and $score{$key} == $max)
         {
            foreach my $pick (%{$picks{$key}})
            {
               unless ( $pick eq 'wins' )
               {
                  print "$pick ";
               }
            }
            print "\n";
            $picks{$key}{'wins'}++;
         }
      }
   }
}


