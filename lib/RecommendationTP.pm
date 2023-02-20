package Table::RecommendationTP;

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

has tablename	=> 'RecommendationTP';
has id_field	=> 'recommendationtpid';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub ClinicalInterpretation {
	my $class = shift;
	return Table::ClinicalInterpretation->fetch($class->{DB}, $class->info->{clinicalinterpretationid});
	}

sub TreatmentScheme {
	my $class = shift;
	return Table::TreatmentScheme->fetch($class->{DB}, $class->info->{treatmentschemeid});
	}

sub references {
	my $class = shift;
	my @references;
	my $sql_cmd = "select referenceDicId from ReferenceAssociation where recommendationTPId = '".$class->get_id."'";
	my $sth = $class->{DB}->execute($sql_cmd);
	my $counter = 0;
	while (my $row = $sth->fetchrow_arrayref) {
		push @references, Table::ReferenceDic->fetch($class->{DB}, $$row[0]);
		}
	return @references;
	}

sub addReference {
	my $class = shift;
	my $Reference = shift;
	my $sql_cmd = "INSERT INTO ReferenceAssociation (recommendationTPId, referenceDicId) VALUES (".$class->get_id.", ".$Reference->get_id.");";
	$class->{DB}->execute($sql_cmd);
	}

sub addGuideline {
	my $class = shift;
	my $guideline = shift;
	my %guidelineDic;
	$guidelineDic{'NCCN'} = 1;
	$guidelineDic{'ESMO'} = 1;
	$guidelineDic{'ASCO'} = 1;
	$guidelineDic{'RUSSCO'} = 1;
	return undef unless defined $guidelineDic{uc($guideline)};
	my $sql_cmd = "INSERT INTO RecommendationTPGuideline (recommendationTPId, GLine) VALUES (".$class->get_id.", '".uc($guideline)."');";
	$class->{DB}->execute($sql_cmd);
	}

sub guidelines {
	my $class = shift;
	my @result;
	my $sql_cmd = "select GLine from RecommendationTPGuideline where recommendationTPId = '".$class->get_id."'";
	my $sth = $class->{DB}->execute($sql_cmd);
	my $counter = 0;
	while (my $row = $sth->fetchrow_arrayref) {
		push @result, $$row[0];
		}
	return @result;
	}


























1;
