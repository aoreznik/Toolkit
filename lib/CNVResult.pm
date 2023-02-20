package Table::CNVResult;

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

has tablename	=> 'CNVResult';
has id_field	=> 'cnvresultid';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub Analysis {
	my $class = shift;
	my $analysis_name = $class->info->{analysisname};
	return undef unless defined $analysis_name;
	return $class->{DB}->Analysis($analysis_name);
	}

sub CNV {
	my $class = shift;
	return $class->{DB}->CNV($class->info->{cnvid});
	}

sub name {
	my $class = shift;
	my $Gene = $class->{DB}->Gene($class->info->{ezgeneid});
	return "".lc($Gene->info->{genesymbol}).":".lc($class->info->{type});
	}

sub is_signCT { # is significant for RecommendationCT
	my $class = shift;
	
	foreach my $RCT ($class->Analysis->Barcode->Case->ClinicalInterpretation->RCTs) {
		next unless (defined($RCT->info->{moleculartargetid}));
		my $MT = Table::MolecularTarget->fetch($class->{DB}, $RCT->info->{moleculartargetid});
		my $name = lc($class->CNV->name);
		return 1 if lc($MT->json) =~ /$name:/;
		}
	return 0;
	}

sub is_signTP { # is significant for RecommendationTP
	my $class = shift;
	foreach my $RTP ($class->Analysis->Barcode->Case->ClinicalInterpretation->RTPs) {
		next unless (defined($RTP->info->{moleculartargetid}));
		my $MT = Table::MolecularTarget->fetch($class->{DB}, $RTP->info->{moleculartargetid});
		my $name = lc($class->CNV->name);
		my $count = 1;
		$count = 2 if $RTP->info->{confidencelevel} eq '1';
		$count = 2 if lc($RTP->info->{confidencelevel}) eq '2a';
		$count = 2 if lc($RTP->info->{confidencelevel}) eq '2b';
		$count = 2 if lc($RTP->info->{confidencelevel}) eq 'r1';
		return $count if lc($MT->json) =~ /$name/;
		}
	return 0;
	}
		
sub variantDescription {
	my $class = shift;
	my $result;
	my @parts;
	
	my $pathology = $class->Analysis->Barcode->Case->ClinicalInterpretation->info->{pathologycodepurpose};
	my $Data = $class->CNV->Gene->geneDescription_biology_select($pathology);
	return '' unless defined $Data;
	return $Data->{'desc'};
	}

















1;
