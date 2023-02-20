package Table::RecommendationGC;

use strict;
use warnings;
use Dir::Self;
use parent 'Table';
use lib __DIR__;

use Aoddb;
use Atlas;
use File::Basename;
use Data::Dumper;
use Storable 'dclone';
use Encode qw(is_utf8 encode decode decode_utf8);
use List::Util qw(max);
use Mojo::Base -base;

has tablename	=> 'RecommendationGC';
has id_field	=> 'recommendationgcid';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub ClinicalInterpretation {
	my $class = shift;
	return Table::ClinicalInterpretation->fetch($class->{DB}, $class->info->{clinicalinterpretationid});
	}

































1;
