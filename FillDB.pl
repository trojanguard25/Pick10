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
my $year;

my $dir_name = $ARGV[0];
my $line_filename = "$dir_name\/line.txt";
my $picks_filename = "$dir_name\/pick10.csv";
my $html_filename = "$dir_name\/pick10.html";

read_scores($dir_name);
#parse_picks($picks_filename);
#parse_line($line_filename);

fill_db();

#write_html($html_filename);

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

sub fill_db()
{
    my $dbh = DBI->connect('DBI:mysql:pick10', 'dan', '') 
                or die "Could not connect to database: $DBI::errstr";



    my $sth = $dbh->prepare("INSERT INTO games (week, year, hometeam, homescore, visitorteam, visitorscore, quarter) VALUE (?,?,?,?,?,?,?)");

    foreach my $key (keys %games)
    {
        $sth->execute($week_num, $year, $games{$key}{'h'}, $games{$key}{'hs'}, $games{$key}{'v'}, $games{$key}{'vs'}, $games{$key}{'q'}); 
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


