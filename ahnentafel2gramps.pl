#! /usr/bin/perl
# 2015 Marti Cuquet
# https://github.com/mcuquet/

use warnings;
use strict;
use List::Util qw( max );
use Getopt::Long;

# Options
my $skip_lines = 3;
my $last_line = 0;
my $verbose = 0;
my $interactive = 0;
my $input = "inputfile.txt";
my $output = "output.gramps";
my $options = GetOptions(
    "input=s" => \$input,
    "interactive" => \$interactive,
    "last-line=i" => \$last_line,
    "output=s" => \$output,
    "skip-lines=i" => \$skip_lines,
    "verbose" => \$verbose
);

# Parameters
my $i_lines = 0;

my $ifh;
open($ifh, $input) or die;
my $ofh;
if ($output) {
    open($ofh, '>', $output) or die;
} else {
    $ofh = \*STDOUT;
}

# Hashes
my %people; # id => person object
my %families; # id => family object
my @family_checks;
my %places; # place => id
my %events; # id => event object
my %notes; #id => note object

# Main

my $buffer = Buffer->new();
Note->new(type => "Source Note", text => "Quadre Ahnentafel convertit a Gramps XML via ahnentafel2gramps.pl");

# Read file

foreach my $file_line (<$ifh>) {
    $i_lines++;
    next if ($i_lines <= $skip_lines);      # skip some lines
    next if ($file_line =~ m/generación/);  # skip generation lines
    next if ($file_line =~ m/^\s*$/);       # skip empty lines

    if ($file_line =~ m/^\s*(\d+)\./ and !$buffer->is_empty()) {        # person line
        my $person = Person->new();
        $person->populate($buffer->lines());
        $buffer->delete_lines();
        $person->print_gramps() if $verbose >= 1;
        $people{$person->id()} = $person unless $person->is_duplicate();
    }
    print "add $file_line" if $verbose >= 2;
    $buffer->add_lines($i_lines => "$file_line");

    last if ($last_line > 0 and $i_lines >= $last_line);
}
my $person = Person->new();
$person->populate($buffer->lines());
$person->print() if $verbose >= 1;
$people{$person->id()} = $person;

# Check family duplicates

foreach my $check_id (@family_checks) {
    my $check = $families{$check_id};
    my $check_fp = $check->fingerprint();

    my $family_id = $check->get_check();
    my $family_fp = $families{$family_id}->fingerprint();

    if ($check_fp eq $family_fp) {
        $families{$family_id}->merge($check);
        delete($families{$check_id});
    }
}

# Print results

print $ofh <<"HEAD";
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE database PUBLIC "-//Gramps//DTD Gramps XML 1.6.0//EN"
"http://gramps-project.org/xml/1.6.0/grampsxml.dtd">
<database xmlns="http://gramps-project.org/xml/1.6.0/">
  <header>
    <created version="4.1.2"/>
  </header>
HEAD
print $ofh "  <people>\n";
foreach my $i (sort {$a <=> $b} keys %people) {
    $people{$i}->print_gramps();
}
print $ofh "  </people>\n";
print $ofh "  <families>\n";
foreach my $i (sort {$a <=> $b} keys %families) {
    $families{$i}->print_gramps();
}
print $ofh "  </families>\n";
print $ofh "  <events>\n";
foreach my $i (sort {$a <=> $b} keys %events) {
    $events{$i}->print_gramps();
}
print $ofh "  </events>\n";
print $ofh <<"CITSOR";
  <citations>
    <citation handle="_cit0">
      <confidence>2</confidence>
      <sourceref hlink="_source0"/>
    </citation>
  </citations>
  <sources>
    <source handle="_source0">
      <stitle>Antecedents de Bartomeu Pedragosa i Falgà</stitle>
      <sauthor>Ramon Rodés</sauthor>
      <noteref hlink="_note1"/>
    </source>
  </sources>
CITSOR
print $ofh "  <places>\n";
foreach my $p (sort keys %places) {
    my $place = Place->new({name => "$p"});
    $place->print_gramps();
}
print $ofh "  </places>\n";
print $ofh "  <notes>\n";
foreach my $n (sort {$a<=>$b} keys %notes) {
    $notes{$n}->print_gramps();
}
print $ofh "  </notes>\n";
print $ofh "</database>\n";


sub prompt {
    my $out_text = shift;
    my $current_value = shift;

    if ($current_value) {
        print $out_text, "[", $current_value, "]: ";
    } else {
        print $out_text, "[", "undef", "]: ";
    }
    $| = 1;
    $_ = <STDIN>;
    chomp;

    return $_ ? $_ : $current_value;
}


package Buffer;

sub new {
    my $class = shift;

    my $self = {
        lines => {},
    };

    bless($self, $class);
    return($self);
}

sub add_lines {
    my $self = shift;
    my %line = @_;

    foreach my $ln (sort {$a<=>$b} keys %line) {
        $self->{lines}->{$ln} = $line{$ln};
    }

    return %line;
}

sub delete_lines {
    my $self = shift;

    $self->{lines} = {};

    return 0;
}

sub is_empty {
    my $self = shift;

    return (%{$self->{lines}}) ? 0 : 1;
}

sub lines {
    my $self = shift;

    return %{$self->{lines}};
}

sub print_lines {
    my $self = shift;

    foreach my $ln (sort {$a<=>$b} keys $self->{lines}) {
        print "$ln: $self->{lines}->{$ln}\n" if $verbose >= 2;
    }

    return 0;
}

package Person;

sub new {
    my $class = shift;

    my $self = {
        person => undef,
        fullname => undef,
        firstname => undef,
        lastname1 => undef,
        lastname2 => undef,
        gender => undef,
        birthdate => undef,
        birthplace => undef,
        deathdate => undef,
        deathplace => undef,
#        family_id => undef,
        marriagestatus => undef,
        marriedto => undef,
        marriagedate => undef,
        marriageplace => undef,
        parentin => [],
        childof => [],
        events => [],
        notes => [],
    };
    bless($self, $class);
    return($self);
}

sub attributes_var {
    my $self = shift;
    my @atts = qw(person fullname firstname lastname1 lastname2 gender birthdate birthplace deathdate deathplace marriagestatus marriedto marriagedate marriageplace);
    return @atts;
}

sub attributes_arr {
    my $self = shift;
    return(qw(parentin childof events notes));
}

sub add_family_as_child {
    my $self = shift;
    my $family_id = shift;
    my %stored = map { $_ => 1 } @{$self->{childof}};
    push(@{$self->{childof}}, $family_id) unless (exists($stored{$family_id}));
}

sub add_family_as_parent {
    my $self = shift;
    my $family_id = shift;
    my %stored = map { $_ => 1 } @{$self->{parentin}};
    push(@{$self->{parentin}}, $family_id) unless (exists($stored{$family_id}));
}

sub add_event {
    my $self = shift;
    my $event_id = shift;
    my %stored = map { $_ => 1 } @{$self->{events}};
    push(@{$self->{events}}, $event_id) unless (exists($stored{$event_id}));
}

sub id {
    my $self = shift;
    return $self->{person};
}

sub is_duplicate {
    my $self = shift;
    return $self->{duplicateof} ? 1 : 0;
}

sub populate {
    my $self = shift;
    my %lines = @_;

    print "++\n" if $verbose >= 2;
    print %lines if $verbose >= 2;
    print "++\n" if $verbose >= 2;

    foreach my $ln (sort {$a<=>$b} keys %lines) {
        my $line_processed = 0;
        my $sentences_processed = 0;
        $_ = $lines{$ln};
        chop;

        print "< $_\n" if $verbose >= 2;

        # Get person ID, GENDER and FAMILY_ID
        if (s/^\s*(\d+)\.\s*//) {
            $self->{person} = $1;
            my $family_id = undef;
            unless ($1 == 1) {
                $self->{gender} = $1 % 2 == 0 ? "M" : "F";
                $family_id = $1 % 2 == 0 ? $1 : $1-1;
            }

            # Flag duplicates
            if (m/se imprimió como #(\d+) /) {
                $self->{duplicateof} = $1;
                my $check = $self->{duplicateof} % 2 == 0 ? $self->{duplicateof} : $self->{duplicateof}-1;
                my $family = exists($families{$family_id}) ?  $families{$family_id} : Family->new(family_id => $family_id);
                $family->add_check($check);
                $family->add_father($self->{duplicateof}) if $self->{gender} eq "M";
                $family->add_mother($self->{duplicateof}) if $self->{gender} eq "F";
                $self->add_family_as_parent($family_id);
                my $child = $family_id / 2;
                $family->add_child($child);
                $people{$child}->add_family_as_child($family_id);
                next;
            }

            # If NN.
            if (m/^NN\.$/) {
                $self->{fullname} = "NN";
                $self->{firstname} = "NN";
                next;
            }

            my $save_line = $_;

            # Get person FULLNAME
            if (m/^(.*) nació/) {
                $self->{fullname} = $1;
                if ($self->{fullname} =~ m/^(.+?) ([Dd]e .+?)( | i )([Dd]e .+?)$/) {
                    $self->{firstname} = "$1";
                    $self->{lastname1} = "$2";
                    $self->{lastname2} = "$4";
                } elsif ($self->{fullname} =~ m/^(.+?) ([Dd]e .+?) (.+?)$/) {
                    $self->{firstname} = "$1";
                    $self->{lastname1} = "$2";
                    $self->{lastname2} = "$3";
                } elsif ($self->{fullname} =~ m/^(.+?) (.+?) ([Dd]e .+?)$/) {
                    $self->{firstname} = "$1";
                    $self->{lastname1} = "$2";
                    $self->{lastname2} = "$3";
                } elsif ($self->{fullname} =~ m/^(.+?) ([Dd]e .+?)$/) {
                    $self->{firstname} = "$1";
                    $self->{lastname1} = "$2";
                } elsif ($self->{fullname} =~ m/^(.+?) (.+?) (.+?)$/) {
                    $self->{firstname} = "$1";
                    $self->{lastname1} = "$2";
                    $self->{lastname2} = "$3";
                } elsif ($self->{fullname} =~ m/^(.+?) (.+?)$/) {
                    $self->{firstname} = "$1";
                    $self->{lastname1} = "$2";
                } elsif ($self->{fullname} =~ m/^(.+?)$/) {
                    $self->{firstname} = "$1";
                } else {
                    print STDERR "Unprocessed fullname at line $ln: $self->{fullname}\n" unless $verbose >= 2;
                    $self->print_summary() if $verbose >= 2;
                    $self->populate_interactively($ln, $self->{fullname}) if $interactive;;
                }
            # Dangerous mode:
            } else {
                m/^(.+?)( se casó| murió|\.)/;
                $self->{fullname} = $1;
                if ($self->{fullname} =~ m/^(.+?) ([Dd]e .+?)( | i )([Dd]e .+?)$/) {
                    $self->{firstname} = "$1";
                    $self->{lastname1} = "$2";
                    $self->{lastname2} = "$4";
                } elsif ($self->{fullname} =~ m/^(.+?) ([Dd]e .+?) (.+?)$/) {
                    $self->{firstname} = "$1";
                    $self->{lastname1} = "$2";
                    $self->{lastname2} = "$3";
                } elsif ($self->{fullname} =~ m/^(.+?) (.+?) ([Dd]e .+?)$/) {
                    $self->{firstname} = "$1";
                    $self->{lastname1} = "$2";
                    $self->{lastname2} = "$3";
                } elsif ($self->{fullname} =~ m/^(.+?) ([Dd]e .+?)$/) {
                    $self->{firstname} = "$1";
                    $self->{lastname1} = "$2";
                } elsif ($self->{fullname} =~ m/^(.+?) (.+?) (.+?)$/) {
                    $self->{firstname} = "$1";
                    $self->{lastname1} = "$2";
                    $self->{lastname2} = "$3";
                } elsif ($self->{fullname} =~ m/^(.+?) (.+?)$/) {
                    $self->{firstname} = "$1";
                    $self->{lastname1} = "$2";
                } elsif ($self->{fullname} =~ m/^(.+?)$/) {
                    $self->{firstname} = "$1";
                } else {
                    print STDERR "Unprocessed fullname at line $ln: $self->{fullname}\n" unless $verbose >= 2;
                    $self->print_summary() if $verbose >= 2;
                    $self->populate_interactively($ln, $self->{fullname}) if $interactive;;
                }
                if ($interactive) {
                    print "Please confirm the following information extracted from line $ln:\n";
                    print "  $_\n";
                    foreach my $a (qw(fullname firstname lastname1 lastname2)) {
                        my $val = ::prompt($a, $self->{$a});
                        $self->{$a} = $val if $val;
                    }
                }
            }

            # Split sentences
            $_ = $save_line;
            my @sentences = split('\.', $_);
            my $n_sentences = @sentences;
            foreach (@sentences) {
                $_ = "$_.";
                my $sentence_processed = 0;
                print "  < $_\n" if $verbose >= 2;
                if (m/nació/) {
                    if (m/en (\d{4})/) {
                        $self->{birthdate} = $1;
                        $sentence_processed = 1;
                    }
                    if (m/en (\D+)\./) {
                        $self->{birthplace} = $1;
                        my $place = Place->new({name => "$1"});
                        $sentence_processed = 1;
                    }
                    if ($self->{birthplace} or $self->{birthdate}) {
                        my $event = Event->new(
                            type => "Birth",
                            date => $self->{birthdate},
                            place => $self->{birthplace},
                            place_id => $places{"$self->{birthplace}"}
                        );
                        $self->add_event($event->id());
                    }
                } elsif (m/murió/) {
                    if (m/en (\d{3,4})/) {
                        $self->{deathdate} = $1;
                        $sentence_processed = 1;
                    }
                    if (m/en (\D+)\./) {
                        $self->{deathplace} = $1;
                        my $place = Place->new({name => "$1"});
                        $sentence_processed = 1;
                    }
                    my $event = Event->new(
                        type => "Death",
                        date => $self->{deathdate},
                        place => $self->{deathplace},
                        place_id => $places{"$self->{deathplace}"}
                    );
                    $self->add_event($event->id());
                } elsif (m/casó/) {
                    if (m/con (.*?)( el| en|\.)/) {
                        $self->{marriedto} = $1;
                        $sentence_processed = 1 if("$2" eq "\.");
                    }
                    if (m/el\s*(\d*)\s*(\w+)\s*(\d{4})/) {
                        my %month_num = (Enero => '01', Febrero => '02', Marzo =>
                            '03', Abril => '04', Mayo => '05', Junio => '06',
                            Julio => '07', Agosto => '08', Septiembre => '09',
                            Octubre => '10', Noviembre => '11', Diciembre => '12');
                        my $m = $month_num{$2};
                        $self->{marriagedate} = "$3-$m-$1";
                        $sentence_processed = 1;
                    } elsif (m/en (\d{4})/) {
                        $self->{marriagedate} = $1;
                        $sentence_processed = 1;
                    }
                    if (m/en (\D+)\./) {
                        $self->{marriageplace} = $1;
                        my $place = Place->new({name => "$1"});
                        $sentence_processed = 1;
                    }
                    # The following detects a grammar mistake:
                    # FIRSTNAME se casó WIFENAME.
                    if (m/casó ([A-Z].*)\./) {
                        $self->{marriedto} = $1;
                        $sentence_processed = 1;
                    }
                    $self->{marriagestatus} = "Married";
                } elsif ($_ eq "$self->{fullname}.") {
                    $sentence_processed = 1;
                }

                unless ($self->{person} == 1) {
                    my $family = exists($families{$family_id}) ?  $families{$family_id} : Family->new(family_id => $family_id);
                    $family->add_father($self->{person}) if $self->{gender} eq "M";
                    $family->add_mother($self->{person}) if $self->{gender} eq "F";
                    $self->add_family_as_parent($family_id);
                    my $child = ($self->{person} % 2 == 0 ? $self->{person} : $self->{person} - 1) / 2;
                    $family->add_child($child);
                    if (! $people{$child} ){
                        my $p = Person->new();
                        $p->set_id($child);
                        $p->set_firstname("NN");
                        $people{$child} = $p;
                    }
                    $people{$child}->add_family_as_child($family_id);
                    $family->set_rel_type($self->{marriagestatus}) if $self->{marriagestatus};
                    if ($self->{marriagedate} or $self->{marriageplace}) {
                        my $marriage = Event->new(
                            type => "Marriage",
                            date => $self->{marriagedate},
                            place => $self->{marriageplace}
                        );
                        $family->add_event($marriage->id());
                    }
                }

                $sentences_processed += $sentence_processed;
            }

            if ($sentences_processed < $n_sentences) {
                print "Unprocessed sentence at line $ln ($sentences_processed/$n_sentences): $_\n" if $verbose >= 2;
                print STDERR "Unprocessed sentence at line $ln ($sentences_processed/$n_sentences): $_\n" unless $verbose >= 2;
                $self->print_summary() if $verbose >= 2;
                $self->populate_interactively($ln, $_) if $interactive;
            }
        } else { # Note line
            my $note = Note->new(text => "$_");
            push @{$self->{notes}}, $note->id();
        }
    }

    return 0;
}

sub populate_interactively {
    my $self = shift;
    foreach my $a ($self->attributes_var()) {
        my $val = ::prompt($a, $self->{$a});
        $self->{$a} = $val if $val;
        $self->{$a} = undef if $val eq "undef";
    }
}

sub print_gramps {
    my $self = shift;
    my $indent = " " x (4 - 1);

    print $ofh "$indent <person handle=\"_p$self->{person}\">\n";
    print $ofh "$indent   <gender>$self->{gender}</gender>\n" if $self->{gender};
    print $ofh "$indent   <name>\n";
    print $ofh "$indent     <first>$self->{firstname}</first>\n" if $self->{firstname};
    print $ofh "$indent     <surname>$self->{lastname1}</surname>\n" if $self->{lastname1};
    print $ofh "$indent     <surname prim=\"0\">$self->{lastname2}</surname>\n" if $self->{lastname2};
    print $ofh "$indent   </name>\n";
    foreach my $e (@{$self->{events}}) {
        print $ofh "$indent   <eventref hlink=\"_e$e\" role=\"Primary\"/>\n";
    }
    foreach my $f (@{$self->{parentin}}) {
        print $ofh "$indent   <parentin hlink=\"_f$f\"/>\n";
    }
    foreach my $f (@{$self->{childof}}) {
        print $ofh "$indent   <childof hlink=\"_f$f\"/>\n";
    }
    foreach my $n (@{$self->{notes}}) {
        print $ofh "$indent   <noteref hlink=\"_note$n\"/>\n";
    }
    print $ofh "$indent   <citationref hlink=\"_cit0\"/>\n";
    print $ofh "$indent </person>\n";
}

sub print_summary {
    my $self = shift;

    my @atts = $self->attributes_var();
    my @atts_arr = $self->attributes_arr();
    print STDERR "-" x 20 . "\n";
    foreach my $a (@atts) {
        if ($self->{$a}) {
            print STDERR "$a: $self->{$a}\n";
        } else {
            print STDERR "$a: undef\n";
        }
    }
    foreach my $a (@atts_arr) {
        print STDERR "$a: ";
        print STDERR join( ',', @{$self->{$a}} );
        print STDERR "\n";
    }
    print STDERR "-" x 20 . "\n";
}

sub remove_family_as_child {
    my $self = shift;
    my $family_id = shift;
    @{$self->{childof}} = grep { $_ != $family_id } @{$self->{childof}};
}

sub remove_family_as_parent {
    my $self = shift;
    my $family_id = shift;
    @{$self->{parentin}} = grep { $_ != $family_id } @{$self->{parentin}};
}

sub set_id {
    my $self = shift;
    $self->{person} = shift;
}

sub set_firstname {
    my $self = shift;
    $self->{firstname} = shift;
}

package Event;

sub new {
    my $class = shift;
    my %options = @_;

    my $self = {
        type => undef,
        date => undef,
        place => undef,
        place_id => undef,
        %options,
        event_id => undef,
    };
    
    $self->{place_id} = $places{"$self->{place}"} if(! $self->{place_id} and $self->{place});

    $self->{event_id} = keys %events ? (sort {$a<=>$b} keys %events)[-1] + 1 : 1;
    $events{$self->{event_id}} = $self;

    bless($self, $class);
    return($self);
}

sub id {
    my $self = shift;
    return($self->{event_id});
}

sub print_gramps {
    my $self = shift;
    my $indent = " " x (4 - 1);

    print $ofh "$indent <event handle=\"_e$self->{event_id}\">\n";
    print $ofh "$indent   <type>$self->{type}</type>\n";
    print $ofh "$indent   <dateval val=\"$self->{date}\"/>\n" if $self->{date};
    print $ofh "$indent   <place hlink=\"_place$self->{place_id}\"/>\n" if $self->{place_id};
    print $ofh "$indent   <citationref hlink=\"_cit0\"/>\n";
    print $ofh "$indent </event>\n";
}

package Family;

sub new {
    my $class = shift;
    my %options = @_;

    my $self = {
        rel_type => "Unknown",
        father_id => undef,
        mother_id => undef,
        marriage_id => undef,
        childs => [],
        events => [],
        family_id => undef,
        check_with => undef,
        %options,
    };

    $families{$self->{family_id}} = $self;

    bless($self, $class);
    return($self);
}

sub add_check {
    my $self = shift;
    my $c = shift;
    $self->{check_with} = $c;
    my %stored = map { $_ => 1 } @family_checks;
    push(@family_checks, $self->{family_id}) unless (exists($stored{$self->{family_id}}));
}

sub add_child {
    my $self = shift;
    my $c = shift;
    my %stored = map { $_ => 1 } @{$self->{childs}};
    push(@{$self->{childs}}, $c) unless (exists($stored{$c}));
#    $people{$c}->add_family_as_child($self->{family_id});
}

sub add_father {
    my $self = shift;
    $self->{father_id} = shift;
#    $people{$self->{father_id}}->add_family_as_parent($self->{family_id});
}

sub add_mother {
    my $self = shift;
    $self->{mother_id} = shift;
#    $people{$self->{mother_id}}->add_family_as_parent($self->{family_id});
}

sub add_marriage {
    my $self = shift;
    $self->{marriage_id} = shift;
    $self->{rel_type} = "Married";
}

sub add_event {
    my $self = shift;
    my $event_id = shift;
    my %stored = map { $_ => 1 } @{$self->{events}};
    push(@{$self->{events}}, $event_id) unless (exists($stored{$event_id}));
}

sub fingerprint {
    my $self = shift;
    return $self->{father_id} . "-" . $self->{mother_id};
}

sub get_check {
    my $self = shift;
    return $self->{check_with};
}

sub merge {
    my $self = shift;
    my $in = shift;

    # Merge families
    $self->{rel_type} = $in->{rel_type} unless $self->{rel_type};
    $self->{marriage_id} = $in->{marriage_id} unless $self->{marriage_id};
    push @{$self->{childs}}, @{$in->{childs}};
    push @{$self->{events}}, @{$in->{events}};

    # Update people
    $people{$in->{father_id}}->remove_family_as_parent($in->{family_id});
    $people{$in->{father_id}}->add_family_as_parent($self->{family_id});
    $people{$in->{mother_id}}->remove_family_as_parent($in->{family_id});
    $people{$in->{mother_id}}->add_family_as_parent($self->{family_id});
    foreach my $c (@{$in->{childs}}) {
        $people{$c}->remove_family_as_child($in->{family_id});
        $people{$c}->add_family_as_child($self->{family_id});
    }
}

sub print_gramps {
    my $self = shift;
    my $indent = " " x (4 - 1);

    print $ofh "$indent <family handle=\"_f$self->{family_id}\">\n";
    print $ofh "$indent   <rel type=\"$self->{rel_type}\"/>\n";
    print $ofh "$indent   <father hlink=\"_p$self->{father_id}\"/>\n" if $self->{father_id};
    print $ofh "$indent   <mother hlink=\"_p$self->{mother_id}\"/>\n" if $self->{mother_id};
#    print "$indent   <eventref hlink=\"_e$self->{marriage_id}\" role=\"Family\"/>\n" if $self->{marriage_id};
    foreach my $e (@{$self->{events}}) {
        print $ofh "$indent   <eventref hlink=\"_e$e\" role=\"Family\"/>\n";
    }
    foreach my $child (@{$self->{childs}}) {
        print $ofh "$indent   <childref hlink=\"_p$child\"/>\n";
    }
    print $ofh "$indent   <citationref hlink=\"_cit0\"/>\n";
    print $ofh "$indent </family>\n";
}

sub set_rel_type {
    my $self = shift;
    $self->{rel_type} = shift;
}

package Place;

sub new {
    my ($class, $args) = @_;
    my $id = undef;
    my $pl = $args->{name};

    if ($places{"$pl"}) {
        $id = $places{"$pl"};
    } else {
        $id = keys %places ? (sort {$a<=>$b} values %places)[-1] + 1 : 1;
        $places{"$pl"} = $id;
    }

    my $self = {
        id => $id,
        name => $pl,
    };
    bless($self, $class);
    return($self);
}

sub get_id {
    my $self = shift;
    return($self->{id});
}

sub get_name {
    my $self = shift;
    return($self->{name});
}

sub print_gramps {
    my $self = shift;
    my $indent = " " x (4 - 1);

    print $ofh "$indent <placeobj handle=\"_place$self->{id}\">\n";
    print $ofh "$indent   <ptitle>$self->{name}</ptitle>\n";
    print $ofh "$indent </placeobj>\n";
}

package Note;

sub new {
    my $class = shift;
    my %args = @_;

    my $self = {
        text => undef,
        type => undef,
        %args,
        note_id => undef,
    };
    
    $self->{note_id} = keys %notes ? (sort {$a<=>$b} keys %notes)[-1] + 1 : 1;
    $notes{$self->{note_id}} = $self;

    bless($self, $class);
    return($self);
}

sub id {
    my $self = shift;
    return($self->{note_id});
}

sub print_gramps {
    my $self = shift;
    my $indent = " " x (4 - 1);

    if ($self->{type}) {
        print $ofh "$indent <note handle=\"_note$self->{note_id}\" type=\"$self->{type}\">\n";
    } else {
        print $ofh "$indent <note handle=\"_note$self->{note_id}\">\n";
    }
    print $ofh "$indent   <text>$self->{text}</text>\n";
    print $ofh "$indent </note>\n";
}
